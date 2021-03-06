# frozen_string_literal: true

require_relative "lib/lifecycle_vm/version"

Gem::Specification.new do |spec|
  spec.name          = "lifecycle_vm"
  spec.version       = LifecycleVM::VERSION
  spec.authors       = ["Alex Scarborough"]
  spec.email         = ["alex@teak.io"]

  spec.summary       = "Lifecycle VM is a minimal vm to support long running ruby processes."
  spec.description   = "Lifecycle VM provides basic lifecycle management following the idea of only executing a single significant operation per program state."
  spec.homepage      = "https://github.com/GoCarrot/lifecycle_vm"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.4.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/GoCarrot/lifecycle_vm"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features|script)/}) }
  end

  spec.require_paths = ["lib"]

  spec.add_development_dependency('simplecov', '~> 0.21.2')
  spec.add_development_dependency('rspec', '~> 3.10')
end
