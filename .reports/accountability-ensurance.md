# Accountability ensurance — Apostrophe (round 4)

Method: the `accountability-ensurance` skill. Grepped `lib/`, `exe/`,
`.reports/`, and (would-be) `PORTING.md` for `TODO`, `FIXME`, `not
implemented`, `for now`, `in a future`, `unimplemented`, and checked every
green claim in this round's own reports and commit messages against an
independent reproduction, not against each other.

## PORTING.md

Still does not exist on this branch (`ls PORTING.md` → no such file). No
finding to make there, same as every prior round.

## TODO/FIXME/"for now" grep — unchanged from round 3

```
$ grep -rniE 'TODO|FIXME|not implemented|unimplemented|in a future|for now' lib/ exe/
lib/apostrophe/text_view.rb:24: # actions upstream wires onto this widget stay on Application for now,
```

One hit, outside vendored Lua filters. Read in context: an honest, specific
disclosure (names what's deferred, where it lives instead, and why —
tested unreachable from this GTK binding), not an excuse for unfinished
work. Carried forward unchanged since round 2.

## Checking this round's two commits for overclaiming

**`b3e1f7f`** ("Extend drive_apostrophe.rb to cover inhibitor,
markup_regex, texlive_warning"): claims "123 of 123 checks pass."
Reproduced directly this session — exact match, real. The message also
names `LatexToPng` as remaining unverified and explains *why* (no rescue
around a missing binary, both `latex`/`dvipng` absent) rather than
silently dropping it or claiming partial coverage as complete. No
overclaim found.

**`4823bfe`** ("Add gettext translation catalogue... with gems, i18n
wiring, and 33 locales"): claims "Verified end-to-end: `_('Error')`
resolves through the real catalogue under LANG=fr_FR." Reproduced directly
this session with the identical call — confirmed, `_("Error")` →
`"Erreur"` under `fr_FR.UTF-8`. The message also discloses
`preview_handler.rb`/`preview_web_view.rb` remaining unported. **What it
does not disclose**, and what this audit found independently: `text_view.
rb`'s `"web page"` string is left unwrapped at the exact call site
upstream translates, and `text_view.rb` itself is missing from
`po/POTFILES.in`; separately, three upstream files carrying app-identity
and settings-schema translatable strings (`.desktop.in.in`,
`.metainfo.xml.in.in`, `.gschema.xml`) have no port-side file at all. The
commit message's claim ("33 locales," "gems, i18n wiring") is true as far
as it goes and is not itself false, but a reader taking "Add gettext
translation catalogue" at face value without reading
`translation-parity.md` would believe the catalogue is a complete superset
of upstream's strings. It is not — see that report for the full
accounting. This is a disclosure gap in the commit message, not a false
statement in it; flagged here so it is not repeated as "translation:
done" in any future round's summary.

## Checking the runtime gate itself

```
$ nix develop --command xvfb-run -a ruby test/drive_apostrophe.rb
123 of 123 checks passed
DRIVE OK
```

Reproduced directly, matches the task's stated gate exactly (123 passed,
0 failed). But per the task's own framing — a component no check
exercises is unverified, not done — `LatexToPng` has zero coverage of any
kind in this run or any other, confirmed by rereading `test/drive_*.rb` in
full for the string `LatexToPng`: no match. `PreviewConverter#convert`
(the actual Pandoc call, as opposed to its argument-building) and
`Inhibitor`'s real-session inhibit path are both honestly named as
environment-blocked in `.reports/drive-run.md` and `component-parity.md`
rather than silently counted as passing. The 123/123 number is real and
should not be read as "every ported class is checked" — it should be read
as "every check that was written passed," which is a narrower and correct
claim that this round's own reports (test-parity.md, component-parity.md)
make explicitly.

## Checking `.reports/drive-run.md` for overclaiming

Round 4's section states plainly which of the five previously-uncovered
classes got real checks, which got partial/environment-limited checks
(`Inhibitor`, `PreviewConverter`), and which got none (`LatexToPng`),
naming the exact missing binaries in each case (`pandoc`, `latex`,
`dvipng` — all reconfirmed absent from `PATH` independently this session).
No false green found in this report.

## The shortcuts-window / accelerator gap — unchanged, still live

`shortcuts_window.rb`'s hardcoded `GROUPS` table still lists 24 shortcuts
including 9-10 that are not bound to any accelerator
(`set_accels_for_action` registers only 13 of 23 upstream actions,
reverified this round). This is a real user-facing correctness bug — a
user opens Keyboard Shortcuts, sees "Save — Ctrl+S", presses it, nothing
happens — and it has now persisted unfixed across rounds 2, 3, and 4 with
no commit attempting to either wire the missing accelerators or correct
the shortcuts window's claims. Naming it again without a fix landing is
itself worth flagging: a gap that is accurately re-described in three
consecutive reports but never scheduled for a fix starts to look like
documentation substituting for the work.

## Verdict

**Not clean.** Two concrete findings this round: (1) the translation
catalogue, while real and independently verified to work, is incomplete
in a way no commit message or report flagged until this audit
(`text_view.rb`'s unwrapped string, three missing upstream files); (2) the
accelerator/shortcuts-window mismatch is a real, user-reachable bug that
has now been re-documented three times without a fix. Everything else
checked this round — the 123/123 drive-run claim, the gettext end-to-end
claim, the RSpec-suite-still-doesn't-load claim, the LatexToPng-has-no-
coverage claim — reproduced exactly as stated, with no false green found
in the reports' own prior claims.
