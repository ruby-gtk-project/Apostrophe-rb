# Translation parity — Apostrophe (round 3)

Method: the `translation-parity` skill, reverified independently against
`origin/main` rather than carried over from round 2's report (the
conclusion is unchanged, but every number below was recounted directly in
this audit).

## Upstream catalogue

```
git show origin/main:po/LINGUAS   → 33 locales
git ls-tree -r --name-only origin/main | grep '^po/'  → po/POTFILES.in lists 42 source files
git show origin/main:po/de.po     → 177 msgid lines (176 real strings + the header)
git show origin/main:po/en_GB.po  → 153 active msgid lines + 8 obsolete (#~) entries
```

The exact count differs slightly between locale files because they were
regenerated at different points against a moving `POTFILES.in` (no checked-in
`.pot` exists — it is Meson-generated) — `de.po` is the more complete/recent
catalogue of the two sampled. The precise number is not the point; both
samples are in the 150-180 range and **both are totally absent from the
port**, which is the finding.

## Port status

```
find . -iname '*.po' -o -iname '*.pot'  →  nothing (checked this session, excluding .git)
grep -rn 'gettext\|GLib\._(\|_("\|N_(' lib/ exe/  →  no matches anywhere
```

The `ruby` branch has:
- no `po/` directory,
- no `LINGUAS`, no `POTFILES.in`, no `.pot`, no `.po` files,
- no translation function call anywhere in `lib/` or `exe/` — every
  user-facing string identified across `component-identification.md` and
  `component-parity.md` (menu item labels, dialog titles and bodies, button
  tooltips, the shortcuts-window table, empty-state text, error messages) is
  a hardcoded English string literal in Ruby source.

## Is extraction tooling at least present for later?

The dev shell carries `rxgettext` (confirmed: `flake.nix`'s devShell
comments reference it as what a future `rake pot` task would drive), but
this is inert — there is a tool on `PATH` and zero strings in the codebase
marked for it to find. A `rake pot` task does not exist in this fork's
`Rakefile` either (checked: no `pot`/`gettext`/`i18n` task is defined).
Having the extractor available is not translation infrastructure if nothing
in the source is wrapped in a translation call for it to extract.

## Verdict

**0% translation parity. Total gap, not partial.** No msgid, no locale, no
extraction call, and no infrastructure to generate one exists anywhere on
the `ruby` branch. Every prior round's report and this round's reach the
same number for the same reason — this has not regressed or improved across
three porting rounds, because no commit on this branch has touched
internationalization at all. This is the cleanest possible example of "a
component no check exercises is unverified, not done": the drive script
never touches a locale, and nothing in `.reports/` or any commit message
claims otherwise.
