# Test parity — Apostrophe

Method: the `test-parity` skill. Upstream's only tests are
`tests/test_lint.py` (shells out to a Python markdown-lint over
`tests/markdown_test.md`) and `tests/test_regex_commonmark.py` (asserts
`markup_regex`'s patterns against CommonMark cases) — both read from
`origin/main` directly.

## Upstream test inventory

- `tests/test_regex_commonmark.py` — unit tests over the regex grammar now
  ported to `lib/apostrophe/markup_regex.rb`.
- `tests/test_lint.py` — shells to a markdown linter over
  `tests/markdown_test.md`, exercising `fix_table`/formatting indirectly.
- `tests/markdown_test.md` — fixture for the above.

## Ported status: 0 of 2 test files ported

- No `spec/` file corresponds to `test_regex_commonmark.py`. `markup_regex.rb`
  exists and is exercised only indirectly, through the drive script's markup
  highlighting checks — not through dedicated regex-grammar assertions
  mirroring upstream's cases (anchors, nesting, edge cases).
- No equivalent of `test_lint.py` / `markdown_test.md` exists.
- `spec/` contains exactly `spec_helper.rb` and `README.md` — **zero example
  files**. `git log` shows no commit has ever added a `spec/*_spec.rb` file
  on this branch.

## Does the suite even run?

No. `spec/spec_helper.rb` requires `kettle/test/rspec` and
`kettle-soup-cover`. These are declared in the *root* `Gemfile`
(kettle-jem's scaffold) but are **not** present in `flake.nix`'s devShell
(only bare `rubyPackages_3_4.rspec`). Confirmed by direct reproduction:

```
nix develop --command xvfb-run -a ruby -e 'require "rspec/core"; require_relative "spec/spec_helper"'
```

fails with `LoadError: cannot load such file -- kettle/test/rspec` before any
example loads — and there are no examples to load regardless. This matches
`.reports/drive-run.md`'s own note, confirmed independently in this audit
rather than taken on faith.

**This is the test-parity report's central finding: the RSpec suite has
never been executed, successfully or otherwise, on this branch, and holds no
tests.** The 40 checks in `test/drive_apostrophe.rb` are real, hand-rolled
integration assertions and did run (reverified in this audit, see
`.reports/drive-run.md` and this session's own rerun), but they are not a
substitute for upstream's regex/lint unit tests, and they only cover the 14
components listed in `drive-run.md` — 14 of the roughly 23 "ported" units
and well under half of upstream's 38 total components (see
`component-identification.md`).

## Verdict

Test parity: **failing**, on two independent axes — upstream's actual test
files are not ported, and the port's own test harness (`spec/`) cannot run
at all in this environment. The drive scripts are good coverage for what
they cover, but a component the drive script doesn't touch (the 24 missing
or `app.*`-action-less components) is unverified by any test, ported or
otherwise.
