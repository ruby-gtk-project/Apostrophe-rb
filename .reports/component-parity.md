# Component parity — Apostrophe (round 3)

Method: the `component-parity` skill, checking every component
`component-identification.md` (this round) marks ported, plus every upstream
window, dialog, page, menu item, keyboard shortcut, preference, action, empty
state and error state, against the `ruby` branch as of `b13564f`
(91/91 checks, reverified below). This supersedes round 2's
`component-parity.md`, most of which (no main window, no menus, no preview
chrome) is now out of date.

## Windows

- **Main window**: real now. `main_window.rb` owns the editor, header bar,
  search bar, stats button, and the file lifecycle — new/open/save/save-as/
  close, discard infobar, save progress bar, unsaved-changes prompt — each
  wired as a real `Gio::SimpleAction` a user can actually reach (menu or
  button), reverified live by re-running `test/drive_apostrophe.rb` in this
  audit: 91/91, DRIVE OK.
- **Preview window**: the chrome is real — `PreviewRenderer`'s flap/stack
  state machine, `PreviewWindow`'s detached toplevel, the layout switcher —
  all driven and asserted in `drive_apostrophe.rb`. **The content is not**:
  it is a static placeholder label, never real Pandoc→HTML output rendered
  through WebKit. A user who opens the preview pane never sees their
  document rendered. This is a correctly *disclosed* gap (see
  `main_window.rb`/`preview_renderer.rb` comments and round-3 commit
  message), but it remains the single biggest functional gap in the app:
  Apostrophe's whole premise is live Markdown preview.

## Dialogs

| Dialog | Upstream | Port | Parity |
|---|---|---|---|
| About | `Adw.AboutWindow` | `about_dialog.rb` | Opens; driven once. Sub-fields (translator-credits, artists, issue URL) not individually asserted — unverified, not confirmed wrong. |
| Shortcuts | `Gtk.ShortcutsWindow`, 24 shortcuts in 7 groups | `shortcuts_window.rb` | **Row/group counts match (24, 7)** — recounted directly against `data/ui/Shortcuts.ui` and the `GROUPS` constant. But see "Shortcuts window vs. real accelerators" below: the window's content is accurate to upstream's *intent*, not to what the port actually binds. |
| Hemingway explainer | `Adw.MessageDialog` | `hemingway_dialog.rb` | Opens; text content not asserted. |
| Preferences | `Adw.PreferencesWindow`, 3 switches + 1 combo row (2 more rows upstream itself hides) | `preferences_dialog.rb` | **Matches.** Verified against `preferences_dialog.py` and `Preferences.ui` directly: upstream's `spellcheck`/`session-restore` rows are `visible=False` in its own `.ui`, so their absence in the port is correct, not a gap. Autohide-headerbar, bigger-text, input-format combo + help button all present and bound to real `Gio::Settings`, driven in `drive_apostrophe.rb`. |
| Advanced export | multi-page `Adw.Window`, leaflet, per-format option groups | `advanced_export_dialog.rb` | Present, driven: default-selects PDF, page-size group shown/hidden per format, go-back returns to the formats list, window title follows selection. |
| TeXLive warning | `Gtk.Stack`, flatpak/distro branching | `texlive_warning.rb` | Present, not independently driven this round beyond existing. |
| Unsaved-changes save prompt | `Adw.MessageDialog` in `main_window.py` | present in `main_window.rb` | Driven in `drive_apostrophe.rb`. |

## Menus

Reverified from scratch against `data/ui/Headerbar.ui`'s `Menu` (8 items
across 5 sections) and `export_menu` (6 items across 4 sections) — **14
items total upstream.** Read `lib/apostrophe/headerbar.rb`'s `menu_model`
and `export_menu_model` line by line against that XML:

- Theme switcher custom slot — present (`themeswitcher_section`).
- Hemingway Mode, Focus Mode — present.
- Find and Replace — present.
- Preferences — present.
- Open Tutorial, Keyboard Shortcuts, About Apostrophe — present (tutorial
  item correctly retargeted to a local file path in place of upstream's
  GResource URI, since the port ships its media on disk — a deliberate,
  documented substitution, not a drop).
- Save As…, PDF/HTML/ODT quick export (×3), Advanced Export…, Copy HTML —
  present.

**14 of 14 upstream menu items are reachable, item-for-item, correcting
round 2's "0 of 13 reachable" finding**, which predates `headerbar.rb`'s
existence. One upstream item is intentionally dropped outside this menu: the
exit-fullscreen button `BaseHeaderbar` packs for in-preview fullscreen,
disclosed in `headerbar.rb`'s own header comment (ties to the unported
fullscreen/preview-chrome behavior).

## Keyboard shortcuts / accelerators — the real gap this round

See `component-identification.md`'s new finding in full. Summary: only 13 of
upstream's 23 accelerator-bearing actions are ever registered via
`set_accels_for_action` (reverified by reading every call site in
`application.rb` and `main_window.rb` — there are exactly 3 call sites total,
2 single accels + 1 loop over an 11-entry hash). **Missing, though the
action itself works via mouse:** `win.open`, `win.save`, `win.save_as`,
`win.close`, `win.find`, `win.find_replace`, `win.focus_mode`,
`win.hemingway_mode`, `win.preview`. **Missing because the action itself
does not exist:** `win.fullscreen` (disclosed, tied to the unported preview
chrome/fullscreen behavior) and `app.spellcheck` (spellcheck is unported
entirely).

This matters beyond the raw count because `shortcuts_window.rb`'s `GROUPS`
table is a **hand-written literal**, not read from the live action/accel
map, and it lists all of these as working shortcuts ("Open — Ctrl+O",
"Save — Ctrl+S", "Find — Ctrl+F", "Hemingway mode — Ctrl+T", "Fullscreen —
F11", …). A user opening the shortcuts window sees upstream's full table and
has no way to discover that ⅔ of the lifecycle/view shortcuts do nothing
when pressed. This is reported again as its own finding in
`accountability-ensurance.md` because it is exactly the kind of gap a
component that "exists and opens" can hide.

## Preferences (GSettings)

All 13 keys + 2 enums exist in the port's own schema, matching upstream 1:1
on name/type (unchanged from round 2, reconfirmed). Round 3 adds the UI that
round 2 found missing: `preferences_dialog.rb` now gives 3 of those keys
(autohide-headerbar, bigger-text, input-format) a real switch/combo bound
live, closing round 2's "schema without UI" gap for those three.
`session-restore` has a schema key and no UI anywhere, matching upstream
(hidden there too).

## Empty / error states

- "No Recent Documents" / recents populated — both states exist in
  `open_popover.rb` and both are driven in `drive_apostrophe.rb` (confirmed:
  the drive script checks the empty-state label before adding a file, then
  the populated `Adwaita::ActionRow` after).
- "File Has Changed on Disk" discard infobar — present in `main_window.rb`,
  driven.
- Generic error dialog (`helpers.show_error`) — present, unchanged from
  round 2.
- TeXLive-missing warning — present (`texlive_warning.rb`), not independently
  driven beyond presenting the dialog that contains it.
- "No Results Found" in the open popover's search — present in
  `open_popover.rb`'s stack; not independently asserted by the drive script
  (it checks the empty/populated recents states, not the no-search-results
  state specifically) — **unverified, not confirmed wrong.**

## Verdict

Round 3 closes almost all of round 2's integration-layer gap: a user can
now open, edit, save, export, and reach every menu item and every dialog.
Two real gaps remain, both substantive rather than cosmetic:

1. **The preview pane renders nothing real** — the app's headline feature is
   a placeholder.
2. **10 of 23 keyboard shortcuts are unbound while the shortcuts window
   claims otherwise** — a user-visible correctness gap, not just an
   incompleteness one, because the documentation (the shortcuts window) is
   actively wrong about current behavior rather than silent about it.
