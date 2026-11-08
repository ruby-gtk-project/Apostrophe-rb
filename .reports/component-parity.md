# Component parity — Apostrophe (round 4)

Method: the `component-parity` skill, checking every upstream window,
dialog, page, menu item, keyboard shortcut, preference, action, empty state
and error state against the `ruby` branch at `b3e1f7f` (latest commit),
with the runtime gate (`test/drive_apostrophe.rb`) rerun fresh in this
audit rather than trusted from the commit message.

```
$ nix develop --command xvfb-run -a ruby test/drive_apostrophe.rb
123 of 123 checks passed
DRIVE OK
```

Reproduced, matches the task's stated gate exactly.

## Windows

- **Main window**: real. File lifecycle (new/open/save/save-as/close,
  discard infobar, save progress bar, unsaved-changes prompt) all wired as
  real `Gio::SimpleAction`s, driven in `drive_apostrophe.rb`. Unchanged
  from round 3.
- **Preview window**: chrome is real and now more thoroughly driven
  (`PreviewRenderer`'s flap/stack state machine, `PreviewWindow`'s detached
  toplevel, the layout switcher). **The content is still not real**: a
  static placeholder label, never Pandoc→HTML rendered through WebKit — no
  Ruby WebKitGTK4 binding exists in this dev shell. This is Apostrophe's
  core marketed feature and remains non-functional in the port, disclosed
  honestly in `main_window.rb`/`preview_renderer.rb` comments and in every
  round's report.

## Dialogs

| Dialog | Upstream | Port | Parity |
|---|---|---|---|
| About | `Adw.AboutWindow` | `about_dialog.rb` | Opens; driven once. Sub-fields not individually asserted. |
| Shortcuts | `Gtk.ShortcutsWindow`, 24 shortcuts / 7 groups | `shortcuts_window.rb` | Row/group counts match (24, 7). But see accelerator section below — the window's content describes bindings that do not all exist. |
| Hemingway explainer | `Adw.MessageDialog` | `hemingway_dialog.rb` | Opens; text content not asserted. |
| Preferences | `Adw.PreferencesWindow` | `preferences_dialog.rb` | Matches upstream exactly, including upstream's own hidden rows (`spellcheck`/`session-restore`, `visible=False` in upstream's `.ui`). Driven. |
| Advanced export | multi-page `Adw.Window`, leaflet | `advanced_export_dialog.rb` + `texlive_warning.rb` | Present, now driven through **both** branches: PDF default-select, page-size group show/hide per format, go-back, **and** the TeX Live warning page — selecting PDF with no `pdftex` on `PATH` genuinely flips to the warning page and disables Export; switching to HTML and back confirms both directions. New this round vs. round 3, where TeXLive warning was "present, not independently driven." |
| Unsaved-changes prompt | `Adw.MessageDialog` | present | Driven. |

## Menus

14 of 14 upstream `Headerbar.ui` menu items reachable item-for-item.
Unchanged from round 3, reverified by re-reading `headerbar.rb`'s
`menu_model`/`export_menu_model` against the upstream XML.

## Keyboard shortcuts / accelerators — still the largest live gap, unchanged

Only **13 of 23** upstream accelerator-bearing actions are registered via
`set_accels_for_action`, reverified by reading all three call sites
(`application.rb:94-95`, `main_window.rb:343`'s loop over an 11-entry
`SHORTCUTS` hash — 2 + 11 = 13). No commit since round 3 touched this.

**Missing, though the action itself works via mouse:** `win.open`,
`win.save`, `win.save_as`, `win.close`, `win.find`, `win.find_replace`,
`win.focus_mode`, `win.hemingway_mode`, `win.preview` (9 real keys that do
nothing when typed). **Missing because the action doesn't exist:**
`win.fullscreen`, `app.spellcheck` (2, tied to unported features).

`shortcuts_window.rb`'s hardcoded `GROUPS` table still lists all of these as
if live — a user opening Keyboard Shortcuts and pressing Ctrl+O or Ctrl+F
gets nothing, with no indication in the UI that the shortcut doesn't work.

## Classes with no dedicated drive-script coverage — narrowed this round

Round 3 named five: `Inhibitor`, `PreviewConverter`, `LatexToPng`,
`TexliveWarning`, `MarkupRegex`. This round's `b3e1f7f` added direct
coverage for four of them:

- `markup_regex.rb` — 16 checks against the compiled `Regexp` constants
  directly (bold, italic ×2, bold+italic, strikethrough, code, links,
  images, headers, fenced code, lists ×2, block quotes, math, hr,
  footnotes). Real, not indirect.
- `preview_converter.rb` — `PreviewConverter.args` asserted directly
  (standalone, mathjax, theme CSS path, both Lua filters). `#convert`
  itself (the worker-thread Pandoc call) is **not** exercised — `pandoc` is
  absent from `PATH` in this dev shell (reconfirmed: `which pandoc` finds
  nothing). Named as unexercised, not faked.
- `texlive_warning.rb` — now driven through the real advanced-export
  leaflet, both directions (see Dialogs table above).
- `inhibitor.rb` — `Gtk::Application#inhibit` returns cookie `0` under this
  headless Xvfb session (no logind/portal), so the end-to-end path cannot
  be verified here; `Inhibitor`'s own cookie bookkeeping (no double-inhibit,
  correct uninhibit, idempotent re-uninhibit) is instead verified in
  isolation against a fake `Helpers.app`. The real-session path is named as
  genuinely unverifiable in this environment, not silently dropped.

**`LatexToPng` remains the one class with zero coverage, direct or
indirect**, of any kind: `latex` and `dvipng` are both absent from `PATH`
(reconfirmed), and `LatexToPng#generate_png` has no rescue around the
missing-binary case, so driving it would only prove `Errno::ENOENT` — not
the port's own pipeline logic. Per this task's framing, this is an
unverified component, not a done one.

## Translation — new surface since round 3, see `translation-parity.md`

The headerbar menu, preferences dialog, shortcuts window, and export
dialogs all now route their visible strings through `_()`/`n_()` and
resolve correctly under a non-English `LANG` (spot-verified: `_("Error")`
→ `"Erreur"` under `fr_FR.UTF-8`). But `text_view.rb`'s drag-and-drop link
insertion (`"web page"`) is not wrapped and the file is outside
`po/POTFILES.in` — one concrete component-level parity miss, detailed in
`component-identification.md` and `translation-parity.md`.

## Verdict

No regressions found. Real, verified gains since round 3: TeXLive warning
page is now driven both directions, markup_regex/preview_converter/
inhibitor all have direct or honestly-scoped coverage, and a real (if
incomplete) translation layer now exists. Unchanged and still open: the
preview pane renders no real content, 10 of 23 accelerators are unbound
while the shortcuts window claims otherwise, and `LatexToPng` has no
coverage of any kind.
