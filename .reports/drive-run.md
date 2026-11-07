# Driving the port — result

Ran `nix develop --command xvfb-run -a ruby test/drive_apostrophe.rb` (and the
two existing ad hoc scripts, `test/drive_chrome.rb` and `test/drive_editor.rb`)
on 2026-11-07, against the `ruby` branch as of this commit (which adds
`main_window.rb`, `headerbar.rb`, `open_popover.rb`, `export_dialog.rb`'s quick
export, the preview chain — `preview_renderer.rb`, `preview_layout_switcher.rb`
+ item, `preview_window.rb`, `inline_preview.rb` — `preferences_dialog.rb` and
`advanced_export_dialog.rb` on top of the previous round's editor backbone).

The previous round's `drive_apostrophe.rb` (18 steps / 40 checks) proved the
editor backbone but never exercised any of the components that round's commits
had just added — the preview chain, the preferences dialog and the advanced
export dialog were ported with zero lines of driving code behind them. This
round extends the same script in place to cover them.

## Result

`test/drive_apostrophe.rb`: **91 of 91 checks passed — DRIVE OK.**
`test/drive_editor.rb`: all 16 checks pass unchanged.
`test/drive_chrome.rb`: passes; one check (`stats button label updates`) is a
pre-existing timing race against a fixed 800ms `GLib::Timeout` waiting on the
stats worker thread — it failed once and passed on two immediate reruns with
no code change. Not touched, since it predates this round and loosening it
would hide the real race rather than fix it.

Components now exercised by `drive_apostrophe.rb` (36 steps, 19 screenshots
under `tmp/shots/`, not committed per `.gitignore`):

Everything the previous round's report already listed, plus, newly covered
this round:

- **the preview renderer and layout switcher** (`preview_renderer.rb`,
  `preview_layout_switcher.rb` + its item row, `preview_window.rb`): turning
  `win.preview` on shows the full-width placeholder in the real `Adwaita::Flap`
  (`reveal_flap?`, the stack's visible child, `PreviewLayout::FULL_WIDTH`);
  opening the layout popover and clicking its half-width row actually resizes
  the flap (`fold_policy`, the `half-width` css class); clicking the windowed
  row detaches the preview into a second real toplevel (`Gtk::Window.
  list_toplevels` goes from one to two) holding a real `Apostrophe::
  PreviewWindow`; closing that window's `close-request` turns the toggle
  button back off and drops the toplevel count back down — all through
  `PreviewRenderer`'s real `show`/`hide` state machine, not called directly.
- **the open popover's recents list** (`open_popover.rb`): popping it open
  after the earlier file-lifecycle steps had already added a file to
  `Gtk::RecentManager`, and confirming the stack shows the populated list
  (not the empty-state label) with a real `Adwaita::ActionRow` for that file.
- **the preferences dialog** (`preferences_dialog.rb`): `app.preferences`
  presents a real `Adwaita::PreferencesWindow`; flipping the autohide switch
  round-trips through the live `Gio::Settings` binding, not just the widget.
- **the advanced export dialog** (`advanced_export_dialog.rb`): presenting it
  auto-selects PDF (matching upstream's own constructor behaviour) and shows
  PDF's page-size group; the go-back button returns the leaflet to the
  formats list; selecting HTML swaps in the HTML options group and hides the
  page-size group, with the window title following the selection; selecting
  PDF again brings the page-size group back. All through the dialog's own
  `Gtk::ListBox` row-selection signal, not by calling its private handler.

This covers every component the `ruby` branch's `lib/apostrophe/*.rb`
implements as of this commit, per `.reports/component-inventory.md`. The one
upstream piece still genuinely unported — the WebKit-backed preview content
itself (`preview_handler.py`/`preview_web_view.py`, replaced here by a plain
label — see `main_window.rb`'s own comment on why) — is a documented,
intentional gap, not something this run could drive.

## Known gaps, not invented around

- **Screenshot-only Overlay compositing quirk** (carried over from the
  previous round, unchanged): `05-search-bar.png` renders the editor pane
  blank once a second child sits in the `Gtk::Overlay` under the search bar —
  a `Gsk::CairoRenderer`/`GtkWidgetPaintable` limitation under Xvfb's software
  rendering, not a port defect. Every assertion about the search bar's actual
  behaviour passes.

- **The RSpec suite still does not run in this environment.** `ruby -e
  'require "rspec/core"; ...'` (the exact command the dev-shell banner names)
  fails immediately with `LoadError: cannot load such file --
  kettle/test/rspec`, because `spec/spec_helper.rb` requires `kettle/test/rspec`
  and `kettle-soup-cover`, development dependencies declared in the root
  Gemfile (kettle-jem's scaffold bundle) that are not vendored into this
  fork's `flake.nix` devShell — only `rubyPackages_3_4.rspec` itself is. `spec/`
  holds no example files either way (only `spec_helper.rb` and `README.md`),
  so there is nothing to assert even once that load succeeds. This is an
  environment/packaging gap in the dev shell, not a port bug in `lib/`, exactly
  as the previous round found it — reported again rather than patched over by
  stubbing the require or deleting the spec_helper config.
