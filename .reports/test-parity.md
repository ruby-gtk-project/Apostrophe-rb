# Test parity — Apostrophe (round 4)

Method: the `test-parity` skill, every claim reproduced directly this
session rather than carried over.

## Upstream test inventory (`origin/main`), unchanged from round 3

- `tests/test_regex_commonmark.py` — unit tests of the regex grammar, now
  ported to `lib/apostrophe/markup_regex.rb`.
- `tests/test_lint.py` + `tests/markdown_test.md` — shells out to a
  markdown linter, exercising formatting/table-fixing indirectly.

## Ported status: still 0 of 2 upstream test files ported

```
$ find . -iname '*_spec.rb'
(nothing)
$ git log --oneline -- 'spec/*_spec.rb'
(no commit has ever added one, including this round's two new commits)
```

`spec/` still holds only `spec_helper.rb` and `README.md` — zero examples,
unchanged across every commit on this branch.

## Does the suite run? No — reconfirmed fresh this session

```
$ nix develop --command ruby -e 'require "rspec/core"; require "./spec/spec_helper"'
cannot load such file -- kettle/test/rspec (LoadError)
	from spec/spec_helper.rb:23:in '<top (required)>'
```

Identical failure to round 3, reproduced again this session, with no
intervening commit touching `flake.nix`'s devShell or `spec/spec_helper.rb`.
The RSpec suite has never successfully loaded, let alone run, at any commit
on this branch, and holds no examples even if it did load.

## What the drive scripts cover — grown this round, reconfirmed by rerun

```
$ nix develop --command xvfb-run -a ruby test/drive_apostrophe.rb
123 of 123 checks passed
DRIVE OK
```

Up from round 3's 91 (the task's stated gate of "123 checks, 0 failed,
30 components" matches this run exactly). `test/drive_editor.rb` (16
checks) and `test/drive_chrome.rb` are unchanged.

The 32 new checks in this round close most — not all — of round 3's named
coverage gaps (five classes never referenced by name in any drive script:
`Inhibitor`, `PreviewConverter`, `LatexToPng`, `TexliveWarning`,
`MarkupRegex`):

- **`markup_regex.rb`**: now has 16 direct checks against the compiled
  `Regexp` constants. Closed.
- **`texlive_warning.rb`**: now driven through the real advanced-export
  leaflet both directions. Closed.
- **`inhibitor.rb`**: the real `Gtk::Application#inhibit` end-to-end path
  is still unverifiable in this headless Xvfb session (cookie `0`, no
  logind/portal — confirmed directly with a standalone script this
  session), but `Inhibitor`'s own cookie bookkeeping is now verified in
  isolation against a fake `Helpers.app`. Partially closed — the unit-level
  logic is checked; the integration path is named as environment-blocked,
  not silently skipped.
- **`preview_converter.rb`**: `PreviewConverter.args` is now checked
  directly, but `#convert` — the actual Pandoc worker-thread call — is
  still never exercised (`pandoc` absent from `PATH`, reconfirmed: `which
  pandoc` finds nothing). Partially closed.
- **`latex_to_png.rb` — still zero coverage of any kind.** `latex` and
  `dvipng` are both absent from `PATH` (reconfirmed: `which latex dvipng`
  finds neither), and `LatexToPng#generate_png` has no rescue around the
  missing-binary case — driving it here would only prove `Errno::ENOENT`.
  **Not closed.** Per this task's framing, this component remains
  unverified, not done, by any check in the 123.

The regex grammar still lacks upstream's own CommonMark edge-case
corpus (`test_regex_commonmark.py` was never ported as a dedicated file);
the 16 new checks assert the Ruby port's own compiled patterns against
hand-picked examples, which is real coverage but not the same test as
upstream's, and is not a substitute for porting that file.

## Verdict

Test parity is still failing on the same two independent axes as round 3:
upstream's own test files were never ported (0 of 2), and the port's own
RSpec harness cannot load in this environment and holds zero examples
regardless — unchanged by either of this round's two commits. The drive
scripts are real, do run, and grew from 91 to 123 checks, closing coverage
for `markup_regex`, `texlive_warning`, and (partially, with the
environment limit honestly named) `inhibitor` and `preview_converter`.
**`LatexToPng` is the one class that still has no check of any kind in
this branch's history, direct or indirect.** Calling the suite "passing"
without naming that RSpec itself has never executed a single example, and
that one class has no coverage at all, would be the false-green pattern
`accountability-ensurance.md` exists to catch.
