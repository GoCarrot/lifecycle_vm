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
  class CondBase
    class InvalidAttr < ::LifecycleVM::Error
      attr_reader :cond_class, :attribute

      def initialize(cond_class, attribute)
        @cond_class = cond_class
        @attribute = attribute
        super("Invalid attribute #{attribute} access by #{cond_class.name}")
      end
    end

    def self.reads(*attrs)
      @reads ||= {}
      @reads.merge!(Hash[attrs.map { |attribute| [attribute, :"@#{attribute}"] }])
      attr_reader(*attrs)
    end

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
