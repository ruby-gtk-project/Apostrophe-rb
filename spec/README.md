# Specs

This project uses plain RSpec. `spec/spec_helper.rb` used to require
`kettle/test/rspec` (from the `kettle-test` gem) and `kettle-soup-cover`, but
neither gem is vendored into flake.nix's devShell — that devShell carries
`pkgs.rubyPackages_3_4.rspec` and nothing from the kettle-dev stack, which is
a separate, repo-root development bundle (see the root `Gemfile`'s own
comment) — so the suite never actually loaded on this branch. `spec_helper.rb`
now requires nothing beyond RSpec itself and this gem's version file.

Run the suite from the dev shell (the shell banner prints the same command):

```
ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format", "progress", "--require", "spec_helper", "spec"])'
```

## What's here

- `markup_regex_spec.rb` — ported from upstream's
  `tests/test_regex_commonmark.py`, the CommonMark edge cases for `BOLD`,
  `HEADER` and `HEADER_UNDER`. The `BOLD` expectations are the regex's real,
  current output rather than upstream's own test file's expectations:
  upstream's `test_regex_commonmark.py` has rotted against upstream's own
  `markup_regex.py` (confirmed by running upstream's checked-out test file
  with `python3 -m unittest`), so copying its assertions verbatim would just
  import a pre-existing failure into this port under a different language.
  See the comment above `describe '::BOLD'` for the mechanism.
