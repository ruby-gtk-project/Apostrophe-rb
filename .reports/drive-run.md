# Driving the port — result

Ran `nix develop --command xvfb-run -a ruby test/drive_apostrophe.rb` (and the
two existing ad hoc scripts, `test/drive_chrome.rb` and `test/drive_editor.rb`)
on 2026-11-07. All three built the real `Apostrophe::Application`, presented
the real window and drove it through the main loop.

## Result

`test/drive_apostrophe.rb`: **40 of 40 checks passed — DRIVE OK.**
`test/drive_chrome.rb` and `test/drive_editor.rb`: all checks passed
unchanged (both predate this round).

Components exercised by `drive_apostrophe.rb` (18 steps, 9 screenshots under
`tmp/shots/`, not committed per `.gitignore`):

- the window (`Adwaita::ApplicationWindow`, sole toplevel, visible, css class)
- the header bar's focus-mode and Hemingway-mode toggle buttons (both their
  widget state and the markup handler / buffer / setting they drive)
- the main menu popover and the theme switcher inside it (opened for real,
  clicked for real, round-tripped through the `color-scheme` setting)
- the statistics button: its popover, its default label, and the live label
  update once the buffer changes
- the search-and-replace bar: toggling on, finding matches, replace-all,
  toggling off and clearing the highlight
- bracket pairing and list continuation (`TextBuffer`'s own handlers)
- Hemingway mode blocking a delete and the attempted-delete callback
- the format inserter (bold) and the fix-table action, both called directly
  and through the real `win.insert-italic` `Gio::SimpleAction`
- the live markdown highlighter (`MarkupHandler`, worker-thread result)
- the pure `StatsCounter` text-counting function
- export formats (all 17) and their capability flags
- the preview-layout icon set, registered in the icon theme
- the current theme's web stylesheet
- `Helpers.get_debug_info`
- the shortcuts window, the about dialog and the Hemingway explainer dialog,
  each presented over the real window

This covers every component the `ruby` branch's `lib/apostrophe/*.rb` actually
implements as of this commit. Per `.reports/component-inventory.md`, the port
is still missing the real `MainWindow` chrome, the headerbar's own file
(`headerbar.rb`), the open/recents popover, the preview pane (handler,
renderer, web view, window, layout switcher) and the preferences/export/
TeXLive-warning dialogs — none of that exists yet, so none of it could be
driven; this run proves what is ported, not what is missing.

## Known gaps, not invented around

- **Screenshot-only Overlay compositing quirk.** The `05-search-bar.png`
  shot renders the search bar correctly but the editor pane blank once a
  second child sits in the `Gtk::Overlay` under the search bar. Isolated by
  screenshotting `editor_scrolled_window` alone at the same point in the run
  (shows the text fine) versus `editor_overlay` as a whole (blank below the
  search bar) — a compositing limitation of this harness's
  `Gsk::CairoRenderer`-based `GtkWidgetPaintable` screenshot technique under
  Xvfb's software rendering, not a defect in the port: every assertion about
  the search bar's actual behaviour (`search_mode_enabled`, `@matches`,
  `replace_all`) passes. The check it would have corroborated is already
  covered by assertions, so this was left as a screenshot caveat rather than
  a workaround or a loosened check.

- **The RSpec suite does not run in this environment.** The dev-shell banner
  names `ruby -e 'require "rspec/core"; ...'`; `spec/spec_helper.rb` requires
  `kettle/test/rspec` and `kettle-soup-cover`, which are development
  dependencies declared in the *root* `Gemfile` (kettle-jem's scaffold
  bundle) and are not vendored into this fork's `flake.nix` devShell (only
  `rubyPackages_3_4.rspec` itself is). Running it fails immediately with
  `LoadError: cannot load such file -- kettle/test/rspec`, before any example
  runs — and `spec/` currently holds no example files at all (only
  `spec_helper.rb` and `README.md`), so there is nothing to assert even once
  that load succeeds. This is an environment/packaging gap in the dev shell,
  not a port bug in `lib/`, and is reported here rather than patched over by,
  e.g., stubbing the require or deleting the `spec_helper` config.
