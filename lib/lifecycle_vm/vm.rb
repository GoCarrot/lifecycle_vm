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

require 'forwardable'

require 'lifecycle_vm/state'
require 'lifecycle_vm/memory'

module LifecycleVM
  class VM
    extend Forwardable

    # By default the lifecycle state machine starts at :start, ends at :exit,
    # and immediately termiantes on op failure.
    DEFAULT_START = :start
    DEFAULT_TERMINALS = [:exit].freeze
    DEFAULT_ON_OP_FAILURE = :exit

    # Stores state machine configuration.
    class Config
      # @return [Symbol, nil] the state to transition to when an op fails
      attr_accessor :on_op_failure

      # @return [Hash<Symbol, LifecycleVM::State>] a mapping of state names to state structures
      attr_accessor :states

      # @return [Symbol] the state to start at
      attr_accessor :initial_state

      # @return [Array<Symbol>] a list of state names which the machine will stop at
      attr_accessor :terminal_states

      # @return [LifecycleVM::Memory] not an instance of but the class of the memory for this
      #   particular machine
      attr_accessor :memory_class

      # Creates a new Config with default settings
      def initialize
        @states = {}
        @on_op_failure = DEFAULT_ON_OP_FAILURE
        @initial_state = DEFAULT_START
        @terminal_states = DEFAULT_TERMINALS
        @memory_class = LifecycleVM::Memory
        @terminal_states.each do |state|
          @states[state] ||= State.new(state, {})
        end
      end
    end

    # Error raised if the machine attempts to enter a state not declared with .on
    class InvalidState < ::LifecycleVM::Error
      # @return [Symbol] the name of the state that was attempted
      attr_reader :state

      # @return [LifecycleVM::VM] the state machine being executed
      attr_reader :vm

      # @param state [Symbol] the name of the state that does not exist
      # @param vm [LifecycleVM::VM] the vm raising the error
      def initialize(state, vm)
        @state = state
        @vm = vm
        super("Invalid state transition to #{@state}. Current context #{@vm}")
      end
    end

    class << self
      # Set the state to transition to if an op fails
      # @param state [Symbol] the state to transition to when any op fails.
      #   There may only be one declared failure handler for any VM.
      def on_op_failure(state)
        @config ||= Config.new
        @config.on_op_failure = state
      end

      # Declare a state with an optional op and conditional transitions
      # @param state [Symbol] the name of the state
      # @param opts [Hash]
      # @option opts [LifecycleVM::OpBase] :do (nil) the op to execute upon entering this state
      # @option opts [Symbol, Hash] :then (nil) either the name of the state to transition do
      #   after executing :do, or a hash of the form
      #   { case: LifecycleVM::CondBase, when: Hash<_, [Symbol, Hash]> }
      def on(state, opts)
        @config ||= Config.new
        @config.states[state] = State.new(state, opts)
      end

      # Set the state to start execution at
      def initial(state)
        @config ||= Config.new
        @config.initial_state = state
      end

      # Set one or more states as states to halt execution at
      def terminal(*states)
        @config ||= Config.new
        @config.terminal_states += states
        states.each do |state|
          @config.states[state] ||= State.new(state, {})
        end
      end

      # Set the class to be instantiated to store VM memory
      def memory_class(klass)
        @config ||= Config.new
        @config.memory_class = klass
      end

      # @return [Config] the machine configuration
      attr_reader :config
    end

    # The current VM memory
    # @return [LifecycleVM::Memory] the current VM memory
    attr_reader :memory

    # (see LifecycleVM::VM.config)
    def config
      self.class.config
    end

    def_delegators :@memory, *(LifecycleVM::Memory::BUILTINS)
    def_delegators :@memory, *(LifecycleVM::Memory::BUILTINS).map { |field| :"#{field}=" }

    def initialize(memory = nil)
      @memory = memory || config.memory_class.new
    end

    # Executes the VM until a terminal state is reached.
    # @note May never terminate!
    def call
      next_state = config.initial_state
      loop do
        next_state = do_state(next_state)
        break unless next_state
      end
      self
    end

    # Did this vm exit with an errored op?
    # @return [Boolean] true if the vm exited with an errored op
    def errors?
      !!error_op&.errors?
    end

    # @return [Hash<Symbol, Array<String>>] errors from the errored op
    def errors
      error_op&.errors
    end

    # Did this vm encounter an error trying to recover from an errored op?
    # @return [Boolean] true if an op associated with the op failure state errored
    def recovery_errors?
      !!current_op&.errors?
    end

    # @return [Hash<Symbol, Array<String>>] errors from the op failure op
    def recovery_errors
      current_op&.errors
    end

    # @private
    def do_anonymous_op(op, following)
      raise InvalidState.new(current_state.name, self) if op && current_op.executed?

      do_op(op, following)
    end

  private

    def do_state(next_state)
      logger&.debug(:enter, state: next_state, ctx: self)
      self.last_state = current_state

      state = config.states[next_state]
      raise InvalidState.new(next_state, self) unless state

      self.current_state = state

      return nil if config.terminal_states.include?(current_state.name)

      do_op(state.op, state.then)
    end

    OpEntry = Struct.new(:state_name, :op, :errors) do
      def executed?
        !op.nil?
      end

      def errors?
        !(errors.nil? || errors.empty?)
      end
    end

    def do_op(op, following)
      # If we're running under systemd, as determined by the presence of the SdNotify gem,
      # notify the watchdog each time we run an op. This gets us more or less free
      # watchdog monitoring for long running services.
      SdNotify.watchdog if defined?(SdNotify)

      op_result = op&.call(memory)
      self.current_op = OpEntry.new(current_state.name, op, op_result&.errors)

      if current_op.errors?
        logger&.error(:op_errors, state_name: current_op.state_name, op_name: current_op.op.name,
                                  errors: current_op.errors, ctx: self)
        on_op_failure = config.on_op_failure

        # If we're here, then first an op failed, and then an op executed by our
        # on_op_failure state also failed. In this case, both error_op and
        # current_op should be set, and both should #errors? => true
        return DEFAULT_TERMINALS.first if current_state.name == on_op_failure

        self.error_op = current_op

        # We unset current op here so that if there is no failure handler and we're
        # directly transitioning to a terminal state we do not indicate that there
        # were recovery errors (as there was no recovery)
        self.current_op = nil

        return on_op_failure
      # Only clear our error op if we have successfully executed another op
      elsif op
        self.error_op = nil
      end

      following.call(self)
    end
  end
end
