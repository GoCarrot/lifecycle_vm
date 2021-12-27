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

require 'ostruct'

RSpec.describe LifecycleVM::OpBase do
  class BasicOp < LifecycleVM::OpBase
    reads :a, :b
    writes :c, :d

    def call
      logger&.info(:event, a: a, b: b)
      self.c = a + b
      self.d = a * b
    end
  end

  class ErrorOp < BasicOp
    reads :a, :b
    writes :c, :d

    def call
      super
      error(:a, 'failed for no reason')
    end
  end

  class ValidateOp < BasicOp
    reads :a, :b
    writes :c, :d

    def validate
      super
      error(:b, 'failed for no reason')
    end
  end

  class InvalidReadOp < LifecycleVM::OpBase
    reads :does_not_exist
    writes :c

    def call
      self.c = does_not_exist
    end
  end

  class InvalidWriteOp < LifecycleVM::OpBase
    reads :a, :b
    writes :does_not_exist

    def call
      logger&.info(:event, {a: a, b: b})
      self.does_not_exist = a + b
    end
  end

  class NoReadOp < LifecycleVM::OpBase
    writes :c, :d

    def call
      self.c = self.d = 42
    end
  end

  class NoWriteOp < LifecycleVM::OpBase
    reads :a, :b

    def call
      logger.info(:event, a: a, b: b)
    end
  end

  class NoReadNoWriteOp < LifecycleVM::OpBase
    def call
      logger.info(:event, data: 42)
    end
  end

  let(:a) { rand }
  let(:b) { rand }
  let(:state) { OpenStruct.new(a: a, b: b, c: nil, d: nil, logger: nil) }

  describe '.reads' do
    it 'does not warn if a writer is already declared' do
      # I don't care for testing for warnings by looking for output to
      # stderr, but I do not know of any other way to do this.
      expect {
        class WriteRead < LifecycleVM::OpBase
          writes :a
          reads :a

          def call
            self.a = a * 2
          end
        end
      }.not_to output.to_stderr
    end
  end

  describe '.writes' do
    it 'does not permit writing to a protected memory slot' do
      expect {
        class BadOp < LifecycleVM::OpBase
          reads :a
          writes :current_op

          def call
            self.current_op = a
          end
        end
      }.to raise_error(LifecycleVM::OpBase::InvalidAttr)
    end

    it 'does not warn if a reader is already declared' do
      # I don't care for testing for warnings by looking for output to
      # stderr, but I do not know of any other way to do this.
      expect {
        class ReadWrite < LifecycleVM::OpBase
          reads :a
          writes :a

          def call
            self.a = a * 2
          end
        end
      }.not_to output.to_stderr
    end
  end

  describe '.call' do
    it 'passes reads into the op and persists writes into state' do
      BasicOp.call(state)
      expect(state).to have_attributes(c: a + b, d: a * b)
    end

    it 'passes logger into the op' do
      state.logger = StubLogger.new
      BasicOp.call(state)
      expect(state.logger.messages).to eq [[:event, {a: a, b: b}]]
    end

    it 'does not persist writes into state if there are errors' do
      ErrorOp.call(state)
      expect(state).to have_attributes(c: nil, d: nil)
    end

    it 'calls #validate' do
      ValidateOp.call(state)
      expect(state).to have_attributes(c: nil, d: nil)
    end

    it 'raises InvalidAttr if the state does not provide all reads' do
      expect { InvalidReadOp.call(state) }.to raise_error(LifecycleVM::OpBase::InvalidAttr)
    end

    it 'raises InvalidAttr if the state does not provide all writes' do
      expect { InvalidWriteOp.call(state) }.to raise_error(LifecycleVM::OpBase::InvalidAttr)
    end

    it 'does not execute an op if the state does not provide all writes' do
      state.logger = StubLogger.new
      InvalidWriteOp.call(state) rescue nil
      expect(state.logger.messages).to eq []
    end

    it 'allows an op with no reads' do
      NoReadOp.call(state)
      expect(state).to have_attributes(c: 42, d: 42)
    end

    it 'allows an op with no writes' do
      state.logger = StubLogger.new
      NoWriteOp.call(state)
      expect(state.logger.messages).to eq [[:event, {a: a, b: b}]]
    end

    it 'allows an op with no reads and no writes' do
      state.logger = StubLogger.new
      NoReadNoWriteOp.call(state)
      expect(state.logger.messages).to eq [[:event, {data: 42}]]
    end
  end

  describe '#errors?' do
    it 'is true if there are errors' do
      ret = ErrorOp.call(state)
      expect(ret.errors?).to be true
    end

    it 'is false if there are not errors' do
      ret = BasicOp.call(state)
      expect(ret.errors?).to be false
    end
  end
end
