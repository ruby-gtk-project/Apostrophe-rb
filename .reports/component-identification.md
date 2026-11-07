# Component identification — Apostrophe (round 3)

Method: the `component-identification` skill, re-run against the `ruby`
branch as it stands after `b13564f` (preview chain, preferences dialog,
advanced export dialog, texlive warning, inline preview, and the drive
script extended to cover them — 91/91 checks). This supersedes
`.reports/component-inventory.md`, which documents round 2 (40/40, no
preview/preferences/advanced-export) and is now stale.

Upstream (`origin/main`) has no `.blp`; it is PyGObject with `data/ui/*.ui`
GtkBuilder templates beside the `.py` classes — read first, per the skill.

## Totals

| | Upstream | `ruby` branch |
|---|---:|---:|
| `.py` files under `apostrophe/` | 29 (incl. `__init__.py`) | — |
| `.ui` files under `data/ui/` | 14 | — |
| `lib/apostrophe/*.rb` component files | — | 35 |
| Component units (app class + window/dialog/standalone-ui templates) | 23 | 21 ported, 2 absent (see below) |
| Headerbar `Menu` + `export_menu` items (`data/ui/Headerbar.ui`) | 14 | 14 — verified item-for-item in `headerbar.rb`, see component-parity |
| `set_accels_for_action` calls that actually register | 13 primary + 10 `TextView.ui` `GtkShortcut`s = 23 | **13 total** (2 `app.*`, 11 `win.*` markdown-insertion/table/unindent) |
| Shortcuts-window rows displayed (`Shortcuts.ui` / `shortcuts_window.rb`) | 24 | 24 (counted from `GROUPS`, matches) |
| GSettings keys | 13 + 2 enums | 13 + 2 enums, own schema — confirmed matching |
| Translated catalogues | 33 locales, 43 `POTFILES.in` entries, 177 msgids (counted from `po/de.po`) | 0 — no `po/` directory at all |

## Components ported since round 2

- `main_window.rb` (← `apostrophe/main_window.py` + `data/ui/Window.ui`) —
  real file lifecycle: new/open/open_file/save/save_as/export/advanced_export/
  copy_html/close, discard infobar, save progress bar, unsaved-changes prompt.
- `headerbar.rb` (← `headerbars.py` + `Headerbar.ui`) — both GMenu models
  built item-for-item (14/14 items; see component-parity.md).
- `open_popover.rb` (← `open_popover.py` + `Recents.ui`) — recents list,
  search, per-item delete.
- `export_dialog.rb` (← `export_dialog.py`'s quick-export path) — PDF/HTML/ODT
  via Pandoc.
- `preview_layout_switcher.rb` + `preview_layout_switcher_item.rb` (←
  `preview_layout_switcher.py` + its two `.ui` files) — the layout popover.
- `preview_window.rb`, `preview_renderer.rb` (← `preview_window.py`,
  `preview_renderer.py`) — the flap/windowed-preview state machine. **The
  rendered content itself is a static placeholder label**, not real Pandoc
  → HTML → WebKit output (see below — this is the single largest remaining
  functional gap, not a cosmetic one).
- `preferences_dialog.rb` (← `preferences_dialog.py` + `Preferences.ui`) —
  autohide-headerbar switch, bigger-text switch, input-format combo row +
  help button. Upstream's `spellcheck`/`session-restore` rows are
  `visible=False` in its own `.ui` (verified: `Preferences.ui` lines 14 and
  55) — correctly left out, not a gap.
- `advanced_export_dialog.rb` + `texlive_warning.rb` (←
  `export_dialog.py`'s `AdvancedExportDialog`/`TexliveWarning`) — leaflet
  flow between the formats list and per-format options, PDF page-size group,
  HTML options group.
- `inline_preview.rb` (← `inline_preview.py`) — Ctrl+click popover for
  maths/images/footnotes/dictionary lookup.

## Components still missing (named, not stubbed)

1. **`preview_handler.py` + `preview_web_view.py` — the actual preview
   renderer.** No Ruby WebKitGTK4 binding exists in this dev shell
   (reconfirmed: `require "webkit2gtk4"` raises `LoadError`, no such gem
   ships for ruby-gnome's GTK4 stack). The port's `preview_renderer.rb`
   builds the real flap/window chrome but shows a fixed placeholder string
   instead of rendered Markdown. **This is the app's core user-facing
   feature** (Apostrophe markets itself on live Markdown preview) and it does
   not work in the port today, independent of how honestly the gap is
   documented.
2. **The `po/` translation catalogue** — see `translation-parity.md`: a
   total, not partial, gap.

## New finding this round: the accelerator table is a bigger gap than round 2's report caught

Round 2's `component-parity.md` found 6 missing accelerators (the
file-lifecycle ones) and said the rest — the markdown-insertion ones — were
closer to parity than the stale inventory claimed. Re-checking directly
against `lib/apostrophe/main_window.rb` (`install_markdown_shortcuts`, the
only place `set_accels_for_action` is called besides two lines in
`application.rb`):

Only **13 of upstream's 23 accelerator-bearing actions** are ever passed to
`set_accels_for_action` in the `ruby` branch:

- `app.new_window` (`<Ctl>n`), `app.quit` (`<Ctl>q`) — bound in `application.rb`.
- `win.insert-*` ×5, `win.insert-header-{1..4}`, `win.unindent`,
  `win.fix-table` — bound via the `SHORTCUTS` hash in `main_window.rb`.

**Not bound anywhere**, though the actions themselves exist and work via
mouse (menu item or button): `win.open` (`<Ctl>o`), `win.save` (`<Ctl>s`),
`win.save_as` (`<Ctl><Shift>s`), `win.close` (`<Ctl>w`), `win.find`
(`<Ctl>f`), `win.find_replace` (`<Ctl>h`), `win.focus_mode` (`<Ctl>d`),
`win.hemingway_mode` (`<Ctl>t`), `win.preview` (`<Ctl>p`), `win.fullscreen`
(`F11`), `app.spellcheck` (`F7`, moot — spellcheck is unported). That is 10
real keyboard shortcuts upstream users rely on that do nothing in the port
when typed, even though the feature behind each one otherwise works.

**Compounding this: `shortcuts_window.rb` displays all of them anyway.** Its
`GROUPS` table (hardcoded, not read from the live action map) lists "Open —
Ctrl+O", "Save — Ctrl+S", "Find — Ctrl+F", "Hemingway mode — Ctrl+T", etc. as
if they are live bindings. A user who opens Keyboard Shortcuts and tries any
of those 10 keys gets nothing. This is carried into `component-parity.md`
and flagged again in `accountability-ensurance.md` as a shortcuts window that
documents behavior the app does not have.

## Verdict

Round 3 closes the biggest structural gaps (real window, real menus, real
preview chrome, preferences, advanced export). What remains, precisely:

1. The preview pane never renders real content — core feature, non-functional.
2. 10 of 23 upstream keyboard accelerators are not wired, while the
   shortcuts-window UI claims they are.
3. The translation system is a 0% total gap (own report).
4. The test suite is a 0% total gap and does not even load (own report).
