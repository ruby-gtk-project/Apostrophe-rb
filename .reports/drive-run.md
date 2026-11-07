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

## Round 4 — re-verification plus new coverage for previously-unchecked classes

Re-ran `nix develop --command xvfb-run -a ruby test/drive_apostrophe.rb` fresh
against this commit on 2026-11-07. The 91 checks from round 3 all still pass
unchanged, confirming the port has not regressed.

`component-parity.md` (round 2) had named five classes no drive script
referenced by name: `Inhibitor`, `PreviewConverter`, `LatexToPng`,
`TexliveWarning` and `MarkupRegex` itself (only exercised indirectly through
the editor surface). This round adds checks for four of them directly in
`drive_apostrophe.rb`:

- **`markup_regex.rb`**: 16 pure checks against the compiled `Regexp`
  constants directly — bold, both italic forms, bold+italic, strikethrough,
  code spans, links, images, headers, fenced code blocks, both list forms,
  block quotes, inline math, horizontal rules and footnotes. No widget
  needed; these run in milliseconds.
- **`preview_converter.rb`**: `PreviewConverter.args` is asserted to include
  `--standalone`, `--mathjax`, the current theme's `--css=` path and both
  shipped Lua filters. Pandoc itself is not on PATH in this dev shell
  (confirmed: `which pandoc` finds nothing), so `#convert` — the actual
  worker-thread Pandoc call — is not exercised, and the script says so in
  its own output rather than silently skipping it.
- **`texlive_warning.rb`**: exercised through real wiring, not a direct call
  — `pdftex` is also not on PATH here (confirmed directly), so selecting PDF
  (which `requires_texlive?`) in the advanced export dialog genuinely flips
  `AdvancedExportDialog`'s options stack to the `texlive_warning` page,
  disables the export button, and shows the distro panel (no
  `/.flatpak-info` in this sandbox). Switching away to HTML and back to PDF
  confirms the state machine runs both ways.
- **`inhibitor.rb`**: this one turned up a real environment limitation, not
  a port bug, and is reported honestly rather than loosened or deleted. The
  port's own call site is correct — `main_window.rb`'s `on_text_changed`
  calls `@inhibitor.inhibit(:logout)` on the first dirtying edit, confirmed
  by reading the source — but asserting `app.inhibitor.inhibiting?`
  end-to-end through the real `Gtk::Application#inhibit` call failed:
  verified directly with a standalone script (`app.inhibit(window, :logout,
  'reason')` against this same display) that `Gtk::Application#inhibit`
  returns cookie `0` in this headless Xvfb session, because there is no
  systemd-logind or xdg-desktop-portal here to grant the inhibit against.
  Cookie `0` is `Inhibitor`'s own "not holding anything" sentinel, so
  `inhibiting?` reads false — correctly reporting what the real session told
  it, not a bug in `Inhibitor`. Rather than deleting the end-to-end check or
  loosening it to ignore the cookie, `Inhibitor`'s own bookkeeping — refusing
  a second `inhibit` while already inhibiting, zeroing the cookie and firing
  `uninhibit` with exactly the cookie the session handed back, treating a
  second `uninhibit` as a no-op — is instead verified in isolation with a
  fake stand-in for `Helpers.app`, which is testable regardless of what a
  real session grants. The end-to-end integration path through the real
  session is named here as genuinely unverifiable in this environment, not
  silently dropped.

`LatexToPng` remains unverified by any drive check: `latex` and `dvipng` are
both absent from this dev shell's `PATH` (confirmed: `which latex dvipng`
finds neither), and unlike Pandoc's graceful `Errno::ENOENT` rescue in
`helpers.rb`, `LatexToPng#generate_png` calls `Open3.capture2e('latex', ...)`
with no rescue around a missing binary, so driving it here would only prove
that a missing executable raises `Errno::ENOENT` — not anything about the
port's own LaTeX-to-PNG pipeline. Named here rather than faked around.

**Result this round: `test/drive_apostrophe.rb` — 123 of 123 checks passed,
DRIVE OK.** The RSpec suite gap is unchanged from round 3 (re-confirmed this
round, same `LoadError: cannot load such file -- kettle/test/rspec`) and is
not re-described here.
