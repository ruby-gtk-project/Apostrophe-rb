# frozen_string_literal: true

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
