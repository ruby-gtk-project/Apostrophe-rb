# Test parity — Apostrophe (round 3)

Method: the `test-parity` skill, reverified independently this session
(not carried over from round 2 — the central finding is unchanged, but
reproduced directly rather than cited).

## Upstream test inventory (`origin/main`)

- `tests/test_regex_commonmark.py` — unit tests of the regex grammar now
  ported to `lib/apostrophe/markup_regex.rb`.
- `tests/test_lint.py` — shells out to a markdown linter over
  `tests/markdown_test.md`, exercising formatting/table-fixing indirectly.
- `tests/markdown_test.md` — fixture for the above.

## Ported status: 0 of 2 upstream test files ported, confirmed again

```
find . -iname '*_spec.rb'   →  nothing
git log --oneline -- 'spec/*_spec.rb'  →  no commit has ever added one
```

`spec/` holds exactly `spec_helper.rb` and `README.md` — zero example files,
on every commit in this branch's history, not just the current one.
`markup_regex.rb` is exercised only indirectly (through the drive script's
markup-highlighting checks), never through dedicated grammar/edge-case
assertions mirroring upstream's CommonMark test cases.

## Does the suite even run? No — reconfirmed by direct reproduction this session

```
$ nix develop --command ruby -e 'require "rspec/core"; require "./spec/spec_helper"'
cannot load such file -- kettle/test/rspec (LoadError)
	from spec/spec_helper.rb:23:in '<top (required)>'
```

`spec/spec_helper.rb` requires `kettle/test/rspec` and `kettle-soup-cover`,
declared in the root `Gemfile` (the kettle-jem scaffold) but not vendored
into `flake.nix`'s devShell (only bare `rubyPackages_3_4.rspec` is present).
This was reproduced fresh in this audit, independent of
`.reports/drive-run.md`'s own note of the same failure — both agree.

**This is the central finding: the RSpec suite has never successfully
loaded, let alone run, on this branch, at any commit, and it holds no
examples even if it did load.**

## What the drive scripts cover instead, and what they don't

`test/drive_apostrophe.rb` (91 checks), `test/drive_editor.rb` (16 checks)
and `test/drive_chrome.rb` are real, hand-rolled integration assertions
against a live, on-screen app under Xvfb — reverified by rerunning
`drive_apostrophe.rb` in this audit: 91/91, DRIVE OK. They are good coverage
for what they touch, but they are not a substitute for upstream's unit
tests, and — checked directly against the class names, not inferred —
**several ported classes are never referenced by name in any drive script**:
`Inhibitor`, `PreviewConverter`, `LatexToPng`, `TexliveWarning`, and
`MarkupRegex` itself (the regex grammar is only exercised through the editor
surface, not asserted against upstream's own CommonMark edge cases, which is
exactly what `test_regex_commonmark.py` existed to do and is exactly the
test that was never ported). `ExportFormat` *is* directly asserted
(`drive_editor.rb:88-90`, checking its 17-entry table and per-format
capability flags) — the one class in this list with real, if incomplete,
coverage.

## Verdict

Test parity: **failing on two independent axes.** Upstream's own test files
were never ported (0 of 2), and the port's own test harness cannot load at
all in this environment, holds zero examples regardless, and this has been
true on every commit of this branch. The drive scripts are real and do run,
but per this task's framing — a component no check exercises is unverified,
not done — five named classes above have no dedicated check at all, and the
regex grammar specifically lacks the exact kind of edge-case coverage
upstream wrote `test_regex_commonmark.py` to provide. Calling this suite
"passing" or "green" without naming that it has never executed a single
RSpec example would itself be the kind of false-green claim
`accountability-ensurance.md` looks for — which is why it is stated plainly
here instead.
