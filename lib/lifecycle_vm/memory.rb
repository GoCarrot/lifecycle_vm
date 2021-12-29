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
  # Base class for VM memory.
  # Any slots that you want to make readable must have a getter method defined.
  # Any slots that you want to make writeable must have a setter method defined.
  class Memory
    PROTECTED = %i[current_state last_state current_op error_op].freeze
    BUILTINS = (PROTECTED + %i[logger]).freeze

    attr_accessor(*BUILTINS)
  end
end
