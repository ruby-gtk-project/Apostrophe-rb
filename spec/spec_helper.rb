# frozen_string_literal: true

# Config for development dependencies of this library
# i.e., not configured by this library
#
# SimpleCov & related config (must run BEFORE any other requires)
# NOTE: Gemfiles for non-coverage appraisals may not have kettle-soup-cover.
#       The rescue LoadError handles that scenario.
begin
  require "kettle-soup-cover"
  if Kettle::Soup::Cover::DO_COV
    # Requiring simplecov loads the project-local `.simplecov`.
    require "simplecov"
    require "kettle/soup/cover/config"
    SimpleCov.start
  end
rescue LoadError => error
  # check the error message and re-raise when unexpected
  raise error unless error.message.include?("kettle")
end

# External RSpec & related config
require "kettle/test/rspec"
# `kettle/test/rspec` installs harness helpers documented in spec/README.md.

# This library
require "apostrophe/rb"

# Plain RSpec config. The kettle-jem scaffold this file started from required
# `kettle/test/rspec` and `kettle-soup-cover`, neither of which is vendored
# into flake.nix's devShell (that devShell carries plain
# `pkgs.rubyPackages_3_4.rspec`, nothing from the kettle-dev stack), so the
# suite never actually loaded. This drops that scaffold rather than growing
# the devShell with a gem family whose only consumer here is the harness
# itself — see spec/README.md for what plain RSpec gives up by not using it.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'apostrophe/rb/version'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
