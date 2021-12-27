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

require 'simplecov'

SimpleCov.start do
  enable_coverage :branch

  add_filter '/spec/'
end

require "lifecycle_vm"

class StubLogger
  attr_reader :messages

  def initialize
    @messages = []
  end

  %i[debug info notice warning error critical alert emergency audit].each do |m|
    define_method m do |event_type, event_data = nil|
      @messages << [event_type, event_data]
    end
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.warnings = true

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
