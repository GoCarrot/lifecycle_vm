# frozen_string_literal: true

# Copyright 2021 Teak.io, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

RSpec.describe LifecycleVM::VM do
  class BasicMemory < LifecycleVM::Memory
    attr_accessor :a, :b, :c, :d

    def initialize(a: 40, b: 2)
      self.a = a
      self.b = b
    end
  end

  class Add < LifecycleVM::OpBase
    reads :a, :b
    writes :c

    def call
      self.c = a + b
    end
  end

  class Mul < LifecycleVM::OpBase
    reads :a, :b
    writes :d

    def call
      self.d = a * b
    end
  end

  class Sub < LifecycleVM::OpBase
    reads :a, :b
    writes :d

    def call
      self.d = a - b
    end
  end

  class BasicVM < LifecycleVM::VM
    memory_class BasicMemory
    on :start, do: Add, then: :exit
  end

  class CondCGreater42 < LifecycleVM::CondBase
    reads :c

    def call
      c > 42
    end
  end

  it 'executes a basic vm' do
    expect(BasicVM.new.call.memory).to have_attributes(a: 40, b: 2, c: 42)
  end

  it 'takes preconfigured memory' do
    a = rand
    b = rand
    mem = BasicMemory.new(a: a, b: b)
    BasicVM.new(mem).call
    expect(mem).to have_attributes(a: a, b: b, c: a + b)
  end

  it 'reports no errors' do
    expect(BasicVM.new.call).to have_attributes(
      errors?: false,
      recovery_errors?: false,
      errors: nil,
      recovery_errors: nil
    )
  end

  context 'with a cond' do
    class CondVM < LifecycleVM::VM
      memory_class BasicMemory

      on :start, do: Add, then: {
        case: CondCGreater42,
        when: {
          true => :mul,
          false => :sub
        }
      }

      on :mul, do: Mul, then: :exit
      on :sub, do: Sub, then: :exit
    end

    it 'takes a branch' do
      expect(CondVM.new.call.memory).to have_attributes(a: 40, b: 2, c: 42, d: 38)
    end

    it 'takes another branch' do
      mem = BasicMemory.new(b: 3)
      CondVM.new(mem).call
      expect(mem).to have_attributes(a: 40, b: 3, c: 43, d: 120)
    end
  end

  context 'with an invalid cond' do
    class InvalidCondVM < LifecycleVM::VM
      memory_class BasicMemory

      on :start, do: Add, then: {
        case: CondCGreater42,
        when: {
          :true => :exit,
          :false => :exit
        }
      }
    end

    it 'raises invalid cond' do
      expect { InvalidCondVM.new.call }.to raise_error(LifecycleVM::Then::InvalidCond)
    end
  end

  context 'with an invalid state' do
    class InvalidState < LifecycleVM::VM
      memory_class BasicMemory
      on :start, then: :foo
    end

    it 'raises invalid state' do
      expect { InvalidState.new.call }.to raise_error(LifecycleVM::VM::InvalidState)
    end
  end

  context 'with an anonymous state' do
    class ValidAnonState < LifecycleVM::VM
      memory_class BasicMemory

      on :start, then: {
        case: CondCGreater42,
        when: {
          true => { do: Add, then: :exit },
          false => { do: Mul, then: :exit }
        }
      }
    end

    it 'executes the anonymous state' do
      mem = BasicMemory.new
      mem.c = 100
      ValidAnonState.new(mem).call
      expect(mem.c).to eq 42
    end
  end

  context 'with an invalid anonymous state' do
    class InvalidAnonState < LifecycleVM::VM
      memory_class BasicMemory

      on :start, do: Add, then: {
        case: CondCGreater42,
        when: {
          true => { do: Mul, then: :exit },
          false => { do: Mul, then: :exit }
        }
      }
    end

    it 'raises invalid state' do
      expect { InvalidAnonState.new.call }.to raise_error(LifecycleVM::VM::InvalidState)
    end
  end

  context 'with nested conditionals' do
    class NestedCond < LifecycleVM::VM
      memory_class BasicMemory

      on :start, then: {
        case: CondCGreater42,
        when: {
          true => {
            case: CondCGreater42,
            when: {
              true => { do: Add, then: :exit },
              false => { do: Mul, then: :exit }
            }
          },
          false => :exit
        }
      }
    end

    it 'supports them' do
      mem = BasicMemory.new
      mem.c = 100
      NestedCond.new(mem).call
      expect(mem.c).to eq 42
    end
  end

  context 'with an invalid then branch' do
    it 'raises an error' do
      expect {
        class InvalidThen < LifecycleVM::VM
          on :start, then: {
            case: CondCGreater42,
            when: {
              true => 42
            }
          }
        end
      }.to raise_error(LifecycleVM::Then::InvalidBranch)
    end
  end

  context 'with an invalid hash then branch' do
    it 'raises an error' do
      expect {
        class InvalidThen < LifecycleVM::VM
          on :start, then: {
            case: CondCGreater42,
            when: {
              true => { something: :else }
            }
          }
        end
      }.to raise_error(LifecycleVM::Then::InvalidBranch)
    end
  end

  context 'with an invalid then' do
    it 'raises an error' do
      expect {
        class InvalidThen < LifecycleVM::VM
          on :start, then: 42
        end
      }.to raise_error(LifecycleVM::Then::InvalidThen)
    end
  end

  context 'when an op errors' do
    class AlwaysErrorOp < LifecycleVM::OpBase
      def call
        error(:base, 'I always fail')
      end
    end

    context 'with no error recovery' do
      class ErrorVm < LifecycleVM::VM
        on :start, do: AlwaysErrorOp, then: :add
        on :add, do: Add, then: :exit
      end

      subject(:vm) { ErrorVm.new.call }

      it 'errors? is true' do
        expect(vm.errors?).to be true
      end

      it 'provides the errors' do
        expect(vm.errors).to eq({ base: ['I always fail'] })
      end

      it 'recovery_errors? is false' do
        expect(vm.recovery_errors?).to be false
      end

      it 'has no recovery errors' do
        expect(vm.recovery_errors).to be nil
      end
    end

    context 'with error recovery' do
      class RecoveryVm < LifecycleVM::VM
        memory_class BasicMemory
        on_op_failure :recovery

        on :start, do: AlwaysErrorOp, then: :add
        on :add, do: Add, then: :exit

        on :recovery, do: Mul, then: :exit
      end

      it 'recovers from the error' do
        # Little tricky, we're checking that it ran Mul.
        expect(RecoveryVm.new.call.memory.d).to eq 80
      end

      it 'does not report the error' do
        expect(RecoveryVm.new.call).to have_attributes(
          errors?: false,
          errors: nil,
          recovery_errors?: false,
          recovery_errors: nil
        )
      end

      context 'when the recovery errors' do
        class RecoveryFail < LifecycleVM::OpBase
          def call
            error(:other, 'I too fail')
          end
        end

        class TrulyBorked < LifecycleVM::VM
          memory_class BasicMemory
          on_op_failure :recovery

          on :start, do: AlwaysErrorOp, then: :add
          on :add, do: Add, then: :exit

          on :recovery, do: RecoveryFail, then: :add
        end

        it 'reports the errors and recovery_errors' do
          expect(TrulyBorked.new.call).to have_attributes(
            errors?: true,
            errors: { base: ['I always fail'] },
            recovery_errors?: true,
            recovery_errors: { other: ['I too fail'] }
          )
        end
      end
    end
  end

  describe 'initial state' do
    class CustomInitialState < LifecycleVM::VM
      memory_class BasicMemory

      initial :test_thing
      on :start, do: Mul, then: :exit
      on :test_thing, do: Add, then: :exit
    end

    it 'starts at the custom initial state' do
      # This is testing that we called add instead of mul
      expect(CustomInitialState.new.call.memory.c).to eq 42
    end
  end

  describe 'terminal states' do
    class CustomTerminalState < LifecycleVM::VM
      memory_class BasicMemory
      terminal :other_exit

      on :start, then: {
        case: CondCGreater42,
        when: {
          true => :exit,
          false => :other_exit
        }
      }

      # Testing that we don't execute an op on a terminal state
      on :other_exit, do: Mul, then: :exit
    end

    it 'halts at the terminal state' do
      mem = BasicMemory.new
      mem.c = 43
      CustomTerminalState.new(mem).call
      expect(mem).to have_attributes(c: 43, d: nil)
    end
  end

  describe 'logging' do
    let(:logger) { StubLogger.new }
    let(:memory) { BasicMemory.new.tap { |m| m.logger = logger } }

    it 'logs on state entry' do
      BasicVM.new(memory).call
      expect(logger.messages).to include([:enter, a_hash_including(state: :start, ctx: anything)])
    end

    it 'logs on error' do
      ErrorVm.new(memory).call

      expect(logger.messages).to include([
        :op_errors,
        a_hash_including(state_name: :start, op_name: 'AlwaysErrorOp',
        errors: { base: ['I always fail'] }, ctx: anything)
      ])
    end
  end
end
