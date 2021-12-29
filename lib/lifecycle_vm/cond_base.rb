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

module LifecycleVM
  # Base class for all conditionals in a vm.
  # A conditional may read from vm emory by declare reads using the DSL. The
  # lifecycle of a conditional is initialize -> call, and both methods will
  # always be called. All reads and logger will be provided before initialize
  # is called.
  #
  # A conditional may not write to vm memory, and must not error.
  class CondBase
    # Raised if a conditional attempts to read from a memory slot that does not exist.
    class InvalidAttr < ::LifecycleVM::Error
      attr_reader :cond_class, :attribute

      def initialize(cond_class, attribute)
        @cond_class = cond_class
        @attribute = attribute
        super("Invalid attribute #{attribute} access by #{cond_class.name}")
      end
    end

    # Read one or more values out of vm memory and provide them as readable attributes
    def self.reads(*attrs)
      @reads ||= {}
      @reads.merge!(Hash[attrs.map { |attribute| [attribute, :"@#{attribute}"] }])
      attr_reader(*attrs)
    end

    # Execute the current op with the gien vm memory.
    # This will read out all declared reads from memory and return the result of #call.
    def self.call(memory)
      obj = allocate

      @reads ||= {}

      @reads.each do |(attribute, ivar)|
        raise InvalidAttr.new(self, attribute) unless memory.respond_to?(attribute)

        obj.instance_variable_set(ivar, memory.send(attribute).clone)
      end

      obj.instance_variable_set(:"@logger", memory.logger)

      obj.send(:initialize)
      obj.send(:call)
    end

    attr_reader :logger

    def call; end
  end
end
