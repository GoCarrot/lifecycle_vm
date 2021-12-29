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

require 'lifecycle_vm/memory'

module LifecycleVM
  # Base class for all ops in a vm.
  # An op may read and write to vm memory by declaring reads and writes using the
  # DSL. The lifecycle of an op is initialize -> call -> validate, and all three
  # methods will always be called. All reads and logger will be provided before
  # initialize is called.
  #
  # An op may indicate that it encountered an error or otherwise failed by calling
  # #error. If an op has any errors, no writes will be persisted to the vm memory.
  class OpBase
    # Raised if an op attempts to read or write to a memory slot that does not
    # exist, or if an op attempts to write to any slot in LifecycleVM::Memory::PROTECTED.
    class InvalidAttr < ::LifecycleVM::Error
      attr_reader :op_class, :attribute

      def initialize(op_class, attribute)
        @op_class = op_class
        @attribute = attribute
        super("Invalid attribute #{attribute} access by #{op_class.name}")
      end
    end

    # Read one or more values out of vm memory and provide them as readable attributes
    def self.reads(*attrs)
      @reads ||= {}
      @writes ||= {}

      attrs.each do |attribute|
        attribute = attribute.to_sym

        attr_reader attribute unless @writes.key?(attribute)

        @reads[attribute] = :"@#{attribute}"
      end

      @reads
    end

    # Allow writing one or more values to vm memory and provide them as writeable attributes
    # @note You may not write to any slot in LifecycleVM::Memory::PROTECTED
    def self.writes(*attrs)
      @reads ||= {}
      @writes ||= {}

      attrs.each do |attribute|
        attribute = attribute.to_sym
        raise InvalidAttr.new(self, attribute) if LifecycleVM::Memory::PROTECTED.include?(attribute)

        if @reads.key?(attribute)
          attr_writer attribute
        else
          attr_accessor attribute
        end

        @writes[attribute] = :"#{attribute}="
      end

      @writes
    end

    # Execute the current op with the gien vm memory.
    # This will read out all declared reads from memory and if executed without
    # any errors will write all declared writes to memory.
    def self.call(memory)
      obj = allocate

      @reads ||= {}
      @writes ||= {}

      @reads.each do |(attribute, ivar)|
        raise InvalidAttr.new(self, attribute) unless memory.respond_to?(attribute)

        obj.instance_variable_set(ivar, memory.send(attribute).clone)
      end

      @writes.each do |(attribute, setter)|
        raise InvalidAttr.new(self, attribute) unless memory.respond_to?(setter)
      end

      obj.instance_variable_set(:"@logger", memory.logger)
      obj.instance_variable_set(:"@errors", nil)

      obj.send(:initialize)
      obj.send(:call)
      obj.send(:validate)

      unless obj.errors?
        @writes.each do |(attribute, setter)|
          memory.send(setter, obj.send(attribute))
        end
      end

      obj
    end

    def call; end
    def validate; end

    attr_reader :errors, :logger

    # Declare that an error has occurred.
    # @param field [Symbol] the memory field which is in error. The convention is to use :base
    #   for errors not associated with any particular memory field.
    # @param message [Object] a description of the error. Convention is to use a string.
    def error(field, message)
      @errors ||= {}
      @errors[field] ||= []
      @errors[field] << message
    end

    # Did any errors occur in the execution of this op?
    def errors?
      !(@errors.nil? || @errors.empty?)
    end
  end
end
