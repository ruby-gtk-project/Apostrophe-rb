# Component parity — Apostrophe

Method: the `component-parity` skill, checking behavior of each component
`component-identification.md` marks "ported", plus every upstream surface
(window, dialog, page, menu item, keyboard shortcut, preference, action,
empty state, error state) against the port.

## Windows

- **Main window**: no parity possible — `main_window.rb` does not exist.
  No `scrolled` / `no-headerbar` / `devel` dynamic CSS classes, no
  `Gio::FileMonitor` discard-infobar error state, no save progress bar, no
  unsaved-changes confirmation dialog, no save/open `FileChooserNative`.
  **The port currently cannot open, save, or reload a real file at all** —
  there is no code path that does so outside the drive script's direct
  object construction.
- **Preview window**: missing entirely (depends on the preview pipeline,
  which depends on WebKit, which is not in the dev shell).

## Dialogs

| Dialog | Upstream | Port | Parity |
|---|---|---|---|
| About | `Adw.AboutWindow`, debug info, Donate/Translations links | `about_dialog.rb` exists | Driven once in `drive_apostrophe.rb`; not checked against every upstream field (translator-credits, artists, designers, issue URL, the two extra links) — **unverified sub-fields**, not confirmed absent |
| Shortcuts | `Gtk.ShortcutsWindow`, 23 shortcuts in 8 groups | `shortcuts_window.rb` exists | Opened in the drive run but the run asserts only that it opens, not that all 23 shortcuts are present — **content parity unverified** |
| Hemingway explainer | `Adw.MessageDialog`, 2-paragraph body, one "Close" response | `hemingway_dialog.rb` exists | Opened in drive run; text content not asserted |
| Preferences | `Adw.PreferencesWindow`, 4 switches (2 hidden upstream), combo row, help button | missing | No parity |
| Advanced export | multi-page `Adw.Window`, leaflet, 5 preference groups | missing | No parity |
| TeXLive warning | `Gtk.Stack`, flatpak/distro branching | missing | No parity |
| Unsaved-changes save prompt | `Adw.MessageDialog` built in `main_window.py` | missing (no `main_window.rb`) | No parity |

## Menus

Upstream's `Menu` (7 items incl. the theme-switcher custom slot) and
`export_menu` (6 items) live in `headerbars.py`/`Headerbar.ui`. Neither menu
model exists in the port — `theme_switcher.rb` exists as a standalone widget
but nothing attaches it to a real headerbar menu button a user would open.
**0 of 13 upstream menu items are reachable in the running port.**

## Keyboard shortcuts / accelerators

Inventory counted 11 accelerators set in `application.rb` against upstream's
22 (12 in `application.py` + 10 `GtkShortcut`s in `TextView.ui`). Re-checking
`lib/apostrophe/application.rb`'s `SHORTCUTS` table and `text_view.rb`'s own
comment (which explicitly defers the 10 `GtkShortcut` format-insertion
accelerators to `Application`, "for now") — the markdown-insertion shortcuts
(`<Control>i/b/r/u`, header 1-4, strikethrough) do exist as `win.*` actions
with accels, so the ported *count* is closer than the stale inventory states.
Missing accelerators, confirmed by absence of their action: `app.new_window`
(`<Ctl>n`), `win.open` (`<Ctl>o`), `win.save` (`<Ctl>s`), `win.save_as`
(`<Ctl><Shift>s`), `app.quit` (`<Ctl>q`), `win.close` (`<Ctl>w`) — i.e. every
file-lifecycle shortcut, because file lifecycle itself is unported.

## Preferences (GSettings)

All 13 keys + 2 enums exist in the port's own schema
(`data/schemas/org.rubygtkproject.Apostrophe.gschema.xml`), matching upstream
1:1 on name/type. **Settings schema parity: confirmed.** But several keys
have no UI to set them (`autohide-headerbar`, `bigger-text`,
`session-restore` all need `preferences_dialog.rb`, which is missing) — the
schema existing is necessary, not sufficient, for user-facing parity.

## Empty / error states

- "No Recent Documents", "No Results Found" (open popover) — missing
  component, missing states.
- "File Has Changed on Disk" discard infobar — missing component, missing
  state.
- Generic error dialog (`helpers.show_error`, "Error" / "Close") — **exists**
  in `helpers.rb`; this is the one error state confirmed ported.
- TeXLive-missing warning — missing component, missing state.

## Verdict

No component currently claimed "ported" in isolation (text view, search bar,
stats handler, buffer, markup handler) was found behaviorally wrong in this
pass — the drive run's assertions on them hold. The parity gap is almost
entirely at the **integration layer**: the pieces that exist are not wired
into a real window, so a user cannot open a file, save a file, use any menu,
or see any dialog except through code the drive script calls directly.
Component-level parity for the ported units: good. Application-level parity:
not close — most upstream user journeys (open → edit → save, open → preview,
open → export) have no working path in the `ruby` branch today.
