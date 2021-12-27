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

RSpec.describe LifecycleVM::CondBase do
  describe '.call' do
    class BasicCond < LifecycleVM::CondBase
      reads :a, :b, :logger

      def call
        logger&.info(:event, a: a, b: b)
        a + b
      end
    end

    class NoReadCond < LifecycleVM::CondBase
      def call
        42
      end
    end

    class InvalidReadCond < LifecycleVM::CondBase
      reads :does_not_exist

      def call
        does_not_exist
      end
    end

    let(:a) { rand }
    let(:b) { rand }
    let(:state) { OpenStruct.new(a: a, b: b, logger: nil) }

    it 'passes reads into the conditional' do
      expect(BasicCond.call(state)).to eq a + b
    end

    it 'passes logger into the conditional' do
      state.logger = StubLogger.new
      BasicCond.call(state)
      expect(state.logger.messages).to eq [[:event, {a: a, b: b}]]
    end

    it 'raises InvalidAttr if the state does not provide all reads' do
      expect { InvalidReadCond.call(state) }.to raise_error(LifecycleVM::CondBase::InvalidAttr)
    end

    it 'allows a conditional with no reads' do
      expect(NoReadCond.call(state)).to eq 42
    end
  end
end
