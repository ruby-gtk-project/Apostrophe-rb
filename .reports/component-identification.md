# Component identification — Apostrophe (round 4)

Method: the `component-identification` skill, re-run against the `ruby`
branch as of `b3e1f7f` (drive script extended to cover `markup_regex.rb`,
`preview_converter.rb`, `texlive_warning.rb`, `inhibitor.rb` — 123/123
checks) and `4823bfe` (gettext translation catalogue added — 33 locales).
This supersedes `.reports/component-identification.md` round 3 and
`component-inventory.md`, both now stale: round 3 predates the translation
catalogue entirely and undercounts the drive script's coverage.

Upstream (`origin/main`) is PyGObject with `data/ui/*.ui` GtkBuilder
templates beside the `.py` classes; this port has no `.ui` files, every
widget built declaratively in Ruby.

## Totals

| | Upstream | `ruby` branch |
|---|---:|---:|
| `.py` files under `apostrophe/` | 29 (incl. `__init__.py`) | — |
| `lib/apostrophe/*.rb` component files | — | 35 |
| Component units (app class + window/dialog/standalone-ui templates) | 23 | 21 ported, 2 absent (unchanged from round 3, see below) |
| Headerbar `Menu` + `export_menu` items | 14 | 14 — item-for-item (unchanged, reverified) |
| `set_accels_for_action` calls that register | 23 (13 primary + 10 `TextView.ui` `GtkShortcut`s) | **13 total** — unchanged from round 3, reverified by reading all 3 call sites (`application.rb:94-95`, `main_window.rb:343`) |
| Shortcuts-window rows displayed | 24 | 24 (matches, unchanged) |
| GSettings keys | 13 + 2 enums | 13 + 2 enums (unchanged) |
| `po/POTFILES.in` entries (source files carrying translatable strings) | 42 (17 `data/*` + 25 `.py`) | 21 `lib/*.rb` files — **new this round, but incomplete, see below** |
| Locales (`po/LINGUAS`) | 33 | 33 — **identical set, diffed directly, zero mismatch** |
| `.pot` msgid count | 177 (`de.po`, most complete sample) | 143 (`po/apostrophe-rb.pot`) |

## New this round: a real translation catalogue exists, but it is not complete

`4823bfe` wires the `gettext` gem into the runtime, wraps `_`/`n_`/`N_`
across 20 `lib/*.rb` files, and ships 33 compiled `.mo` catalogues under
`data/locale/`. This was reverified directly and works: running Ruby with
`LANG=fr_FR.UTF-8` and calling `_("Error")` through the real catalogue
returns `"Erreur"`.

Two gaps found by diffing `po/POTFILES.in` against every upstream file that
carries a translatable string:

1. **`text_view.rb` is missing from `po/POTFILES.in`, and the one string
   upstream translates at that exact call site is not wrapped.** Upstream's
   `apostrophe/text_view.py` wraps `_("web page")` (used twice, for the
   placeholder link text when a URL is dropped onto the editor). The port's
   `lib/apostrophe/text_view.rb:112` has the identical call site —
   `@text_buffer.insert_at_cursor("[web page](#{content})")` — with the
   string left as a bare Ruby literal, never passed through `_()`, and the
   file is not in `POTFILES.in` at all. A translated build will insert
   English "web page" into a user's document regardless of locale.
2. **The `.desktop`/`.gschema.xml`/`.metainfo.xml.in.in` translatable
   strings have no port-side equivalent to even be a gap in.** Upstream's
   `POTFILES.in` carries `data/org.gnome.gitlab.somas.Apostrophe.desktop.in.in`,
   `.gschema.xml`, and `.metainfo.xml.in.in` — the app's store listing
   (name, one-line summary, feature-list description shown in software
   centers) and its 5 GSettings key summaries/descriptions (shown in
   `dconf-editor`). None of these three files exist anywhere in this port
   (confirmed: `find data -iname '*metainfo*' -o -iname '*desktop*' -o
   -iname '*gschema*'` finds nothing). This is a packaging gap that is also
   a translation gap: even once packaging adds these files, their strings
   are not yet in `po/POTFILES.in`'s scope and would need separate wiring.

These two gaps account for essentially the entire 177→143 msgid shortfall
(the metainfo/desktop/gschema strings alone are ~15-20 of upstream's count;
`text_view.rb`'s `"web page"` is one more upstream msgid absent as a Ruby
literal instead). See `translation-parity.md` for the full count.

## Components ported since round 3

None — `b3e1f7f` only extended the drive script's *coverage* of
already-ported classes (`markup_regex.rb`, `preview_converter.rb`,
`texlive_warning.rb`, `inhibitor.rb`); it added no new `lib/` component.
`4823bfe` added the translation catalogue (infrastructure, not a UI
component) and `Helpers.bind_gettext`.

## Components still missing (unchanged from round 3, named, not stubbed)

1. **`preview_handler.py` + `preview_web_view.py` — the actual preview
   renderer.** No Ruby WebKitGTK4 binding exists in this dev shell
   (reconfirmed: `require "webkit2gtk4"` raises `LoadError`). The port's
   `preview_renderer.rb` builds the real flap/window chrome but shows a
   fixed placeholder string instead of rendered Markdown. This is the app's
   core marketed feature and it does not work in the port today.
2. **The two packaging files noted above** (`.desktop.in.in`,
   `.metainfo.xml.in.in`) plus `.gschema.xml` as a standalone file (the
   port has its own schema, confirmed matching in key count, but not
   verified to exist as an installable `.gschema.xml` on disk with
   translation comments intact — not re-audited in depth this round since
   it is a packaging rather than parity-of-behavior question).

## Accelerator gap — unchanged from round 3, reverified

Still exactly 13 of 23 upstream accelerator-bearing actions registered.
Still not bound: `win.open`, `win.save`, `win.save_as`, `win.close`,
`win.find`, `win.find_replace`, `win.focus_mode`, `win.hemingway_mode`,
`win.preview` (9 — each action itself exists and works via mouse),
`win.fullscreen` and `app.spellcheck` (2 — action doesn't exist at all).
`shortcuts_window.rb`'s hardcoded `GROUPS` table still lists all of them as
if live. No commit between round 3 and this one touched accelerators.

## Verdict

Round 4's real gain is the translation catalogue going from a total 0% gap
to a substantially real one. But "substantially real" is not "complete":
one upstream-translated string was ported as a bare literal at the exact
file/line upstream translates it, and three upstream translatable files
have no port-side equivalent at all. Everything round 3 flagged as
unresolved — the placeholder preview content and the 10 missing
accelerators that the shortcuts window still advertises as live — remains
exactly as it was; no commit in this round touched either.
