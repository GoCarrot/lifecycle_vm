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
  class OpBase
    class InvalidAttr < ::LifecycleVM::Error
      attr_reader :op_class, :attribute

      def initialize(op_class, attribute)
        @op_class = op_class
        @attribute = attribute
        super("Invalid attribute #{attribute} access by #{op_class.name}")
      end
    end

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

      obj.send(:initialize, memory.logger)
      obj.send(:call)
      obj.send(:validate)

      unless obj.errors?
        @writes.each do |(attribute, setter)|
          memory.send(setter, obj.send(attribute))
        end
      end

      obj
    end

    def initialize(logger)
      @errors = nil
      @logger = logger
    end

    def call; end
    def validate; end

    attr_reader :errors, :logger

    def error(field, message)
      @errors ||= {}
      @errors[field] ||= []
      @errors[field] << message
    end

    def errors?
      !(@errors.nil? || @errors.empty?)
    end
  end
end
