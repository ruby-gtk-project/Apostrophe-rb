# Accountability ensurance — Apostrophe (round 3)

Method: the `accountability-ensurance` skill. Grepped `lib/`, `exe/`,
`.reports/`, commit messages, and (would-be) `PORTING.md` for `TODO`,
`FIXME`, `not implemented`, `for now`, `in a future`, `unimplemented`,
`stub`, and for any green claim resting on something never executed.

## Finding 1 (serious): a commit message asserts a false green

Commit `31e830e` ("Port the preview layout chain, preferences and advanced
export dialogs") ends:

> Drive scripts and the rspec suite still pass; flaky worker-thread timing
> checks were independently reproduced as pre-existing flakes, not
> regressions.

This is false. Reproduced directly in this audit:

```
$ nix develop --command ruby -e 'require "rspec/core"; require "./spec/spec_helper"'
cannot load such file -- kettle/test/rspec (LoadError)
```

The RSpec suite does not "pass" — it cannot even load `spec_helper.rb`,
and has never been able to on any commit of this branch (`spec/` has held
zero `*_spec.rb` files at every point in `git log`). This is not a timing
flake or an environment nuance the commit is hedging about; it is a
specific, false claim of a green test run that never happened, written into
permanent project history. The *next* commit's own report
(`.reports/drive-run.md`, this round, written correctly) states the true
situation — "the RSpec suite still does not run in this environment" — so
the contradiction sits one commit apart in the same branch. **This is
exactly the false-green pattern this skill exists to catch**, and it is the
most serious finding in this audit: a claim of passing tests that cannot be
true, now permanent in git history and not correctable by rewriting it.
It is flagged here because the commit itself cannot be un-said; future
commits should not repeat "the rspec suite passes" language until `spec/`
holds actual examples and a devShell that can load them.

## Finding 2: a UI component actively asserts behavior the app does not have

`lib/apostrophe/shortcuts_window.rb`'s `GROUPS` table lists 24 shortcuts as
if all are live keyboard bindings — "Open — Ctrl+O", "Save — Ctrl+S",
"Find — Ctrl+F", "Hemingway mode — Ctrl+T", "Fullscreen — F11", etc. Reading
every `set_accels_for_action` call site in `application.rb` and
`main_window.rb` (there are exactly three, covering 13 of the 24 listed
shortcuts) shows 10 of those 24 rows describe a binding that does not exist
— the action is reachable by mouse but the key does nothing. This is not a
disclosed limitation anywhere in the source (no comment on
`shortcuts_window.rb` notes that its table has drifted from the real accel
map), and it is not caught by any drive-script assertion, because
`drive_apostrophe.rb` never simulates a keypress and checks the resulting
action fires — it only checks that the shortcuts window *opens*. A
shortcuts window that is wrong about what the keyboard does is a worse
failure mode than one that is merely incomplete, because a user trusts it.
Reported in full in `component-identification.md` and
`component-parity.md`; flagged here as the clearest example this round of
a green surface (the dialog opens, the drive script passes) hiding a real
behavioral gap.

## Finding 3: a stale comment that could mislead whoever reads it next

`lib/apostrophe/main_window.rb`'s class comment still reads (as of this
commit): "Left out: the preview flap/stack (the preview pipeline needs a
WebKit binding this dev shell does not have)". The preview flap/stack was
ported in commit `31e830e`, two commits before this comment's current
state — only the *rendered content* is still a placeholder, not the
flap/stack itself. The comment is not a false claim about test results, but
it is exactly the kind of documentation drift `accountability-ensurance`
looks for: a reader trusting this comment would believe less is ported than
actually is. Low severity (it under-claims, not over-claims, so it cannot
produce a false green on its own) but worth fixing alongside the next touch
of that file.

## TODO/FIXME/"for now" grep — the rest

`PORTING.md` does not exist on this branch — no finding to make there.

`lib/` and `exe/`, outside vendored upstream Lua filters (`task-list.lua`,
not port code): one hit, `lib/apostrophe/text_view.rb:24` — "actions
upstream wires onto this widget stay on Application for now". Read in
context: an honest, specific note (names what's deferred, where it actually
lives instead, and why — `do_size_allocate` tested unreachable from this
binding). Disclosed limitation, not an excuse; carried forward unchanged
from round 2's finding, still correct.

## Checking the runtime gate itself

The task's gate (91 checks passed, 0 failed, 22 components) was rerun
directly rather than taken on faith:

```
$ nix develop --command xvfb-run -a ruby test/drive_apostrophe.rb
91 of 91 checks passed
DRIVE OK
```

Real, reproduced. But per this task's own framing, a component the drive
script never names is unverified, not done. Checked directly against class
names (not inferred from the inventory): `Inhibitor`, `PreviewConverter`,
`LatexToPng`, `TexliveWarning`, and `MarkupRegex` are never referenced by
name in any `test/drive_*.rb` script — see `test-parity.md`. These are not
failing; they are simply never checked, and the 91/91 number should not be
read as covering them.

## Checking `.reports/drive-run.md` (this round, already present before this
audit) for overclaiming

It states plainly that the RSpec suite does not run and that `spec/` holds
no examples — this matches Finding 1's independent reproduction exactly and
does not overclaim. It also correctly scopes the preview gap ("documented,
intentional gap, not something this run could drive") rather than hiding it
inside the 91/91 number. No false green found in this specific report.

## Verdict

**Not clean.** One serious finding (a commit message's false claim that the
RSpec suite passes, when it has never been able to load) and one real
user-facing correctness gap presented by a component that opens
successfully and is driven successfully (the shortcuts window listing
non-functional accelerators) — both are exactly the "false green" and
"gap excused rather than built" patterns this skill exists to catch. The
translation and test gaps are honestly a total, undisguised 0% in every
report that touches them (good); the accelerator gap and the one false
commit-message claim are the two places this round's own documentation
needed correcting rather than trusting.
