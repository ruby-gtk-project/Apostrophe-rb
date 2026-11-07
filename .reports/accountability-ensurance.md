# Accountability ensurance — Apostrophe

Method: the `accountability-ensurance` skill. Grepped `lib/`, `exe/`,
`.reports/`, and (would-be) `PORTING.md` for `TODO`, `FIXME`,
`not implemented`, `for now`, `in a future`, and for any green claim resting
on something never executed.

## Grep results

`PORTING.md` does not exist on this branch — no finding to make there.

`lib/` and `exe/`: one hit outside vendored Lua filters —
`lib/apostrophe/text_view.rb:24`, "actions upstream wires onto this widget
stay on Application for now". Read in context (lines 15-25): this is an
honest, specific engineering note — it names exactly which upstream
behaviors are deferred (format-insertion shortcuts, markup highlighting,
window actions) and says precisely where they currently live instead
(`Application`, as plain window actions) and why
(`do_size_allocate` was tested and confirmed unreachable from this binding).
**This is a disclosed limitation, not an excuse** — it says what's missing
and why, rather than asserting the behavior is present. No action required
beyond continuing to track it in `component-identification.md`, which this
audit does.

The other `TODO`/`for now` hits are inside vendored upstream Lua filter
files (`task-list.lua`), not port code — not applicable.

## Checking for false-green claims in `.reports/`

`.reports/drive-run.md` (previous round): makes the "40 of 40 / DRIVE OK"
claim and explicitly scopes it — "This covers every component the `ruby`
branch's `lib/apostrophe/*.rb` actually implements as of this commit... the
port is still missing [list]... this run proves what is ported, not what is
missing." That is the correct framing and was independently reverified in
this audit (rerun `test/drive_apostrophe.rb` this session: 40 of 40, DRIVE
OK, identical to the prior claim). **No false green found in the drive
report** — it does not claim broader coverage than it has.

`.reports/component-inventory.md` (previous round): this is where this
audit found a real accountability gap, though not a dishonest one — the
document's **totals table is stale**. It still reads "18 of 38" rows ported
and marks `search_bar.rb`, `stats_handler.rb`, `theme_switcher.rb`,
`about_dialog.rb`, `hemingway_dialog.rb`, `shortcuts_window.rb` as
"missing" in its per-component sections, when all of those files now exist
on disk (added in commit `b5980e8`, after the inventory's own commit
`7b586c8`). This is a **documentation drift gap, not a code gap**: nothing
in `lib/` is pretending to be done when it isn't; a report about `lib/` is
describing an earlier `lib/`. Flagged here and corrected in
`component-identification.md` in this round — the fix is to regenerate the
inventory after any commit that ports a new file, not to patch the number
in place.

## Checking the runtime gate itself

The task's gate (40/40 passed, 0 failed, 14 components) was treated
skeptically rather than taken at face value: rerun directly in this audit
(see Bash transcript: `nix develop --command xvfb-run -a ruby
test/drive_apostrophe.rb` → "40 of 40 checks passed / DRIVE OK"). The gate
is real, not a stale or fabricated number. But per this task's own framing,
14 components covered out of 38 total upstream components (and 23 "ported"
units per the corrected inventory) means roughly 9 ported units have *no*
drive-script assertion at all — `document.rb`, `format_inserter.rb`'s
remaining shortcuts, `inhibitor.rb`, `settings.rb`'s full key surface,
`style.rb`'s remaining stylesheets, `preview_converter.rb`,
`latex_to_png.rb`, `fix_table.rb` (only exercised via one call), and
`export_format.rb`'s per-format capability matrix beyond the 2 formats
checked. These are not failing, but per the task's instruction they are
**unverified, not done**, and are called out as such rather than folded
into the "40/40 passing" number's implied confidence.

## Verdict

No invented workaround, no silently-dropped requirement, and no fabricated
green status were found. The one real finding is a documentation-staleness
issue in a prior report, now corrected, plus the standing reminder (already
present in `drive-run.md` and reinforced here) that passing checks cover
only the components they name — the other ~24 components, ported or not,
remain to be verified by a future drive round before anyone calls this
clean.
