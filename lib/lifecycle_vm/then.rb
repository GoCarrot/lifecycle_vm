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

require 'lifecycle_vm/error'
require 'lifecycle_vm/vm'

module LifecycleVM
  class Then
    class Simple
      def initialize(state)
        @state = state
      end

      def call(_vm)
        @state
      end
    end

    class AnonymousState
      attr_reader :op, :then

      def initialize(options)
        @op = options[:do]
        @then = Then.new(options[:then])
      end

      def call(vm)
        vm.do_anonymous_op(@op, @then)
      end
    end

    def self.new(options)
      if options.kind_of?(Symbol)
        return Simple.new(options)
      else
        super
      end
    end

    def initialize(options)
      if !(options.kind_of?(Hash) && options.key?(:case) && options.key?(:when))
        raise InvalidThen.new(options)
      end

      @cond = options[:case]
      @branches = options[:when].transform_values do |value|
        case value
        when Hash
          if value.key?(:case)
            Then.new(value)
          elsif value.key?(:then)
            AnonymousState.new(value)
          else
            raise InvalidBranch.new(value, options)
          end
        when Symbol
          Simple.new(value)
        else
          raise InvalidBranch.new(value, options)
        end
      end
    end

    class InvalidThen < ::LifecycleVM::Error
      attr_reader :options

      def initialize(options)
        @options = options

        super("Invalid then configuration #{options}")
      end
    end

    class InvalidBranch < ::LifecycleVM::Error
      attr_reader :value, :options

      def initialize(value, options)
        @value = value
        @options = options

        super("Invalid then option value #{value.inspect} in #{options}")
      end
    end

    class InvalidCond < ::LifecycleVM::Error
      attr_reader :value, :cond, :branches, :vm

      def initialize(value, cond, branches, vm)
        @value = value
        @cond = cond
        @branches = branches
        @vm = vm

        super("Unhandled condition result #{value.inspect} returned by #{cond} in #{branches}. Current context #{@vm}")
      end
    end

    def call(vm)
      state_name = vm.current_state.name
      conditional_name = @cond.name
      logger = vm.logger

      logger&.debug(:conditional_check, state: state_name, ctx: vm, conditional: conditional_name)
      value = @cond.call(vm.memory)
      logger&.debug(:conditional_result, state: state_name, ctx: vm, conditional: conditional_name, result: value)

      branch = @branches[value]
      raise InvalidCond.new(value, @cond, @branches, vm) unless branch.respond_to?(:call)

      branch.call(vm)
    end
  end
end
