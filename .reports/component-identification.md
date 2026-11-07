# Component identification — Apostrophe (`ruby` vs `origin/main`)

Method: the `component-identification` skill, cross-checked against the
existing `.reports/component-inventory.md` (written at commit `7b586c8`,
before `b5980e8` "Port the editor widget, search bar, stats button and three
dialogs"). That document is therefore **stale**: it still lists several files
as "missing" that now exist on disk. This report re-checks `lib/apostrophe/`
as of commit `a56b121` against `git ls-tree -r --name-only origin/main` and
the `.py` / `.ui` pairs read from `origin/main`.

## Corrected status of upstream's 29 `.py` + 15 `.ui` components

Ported (file exists in `lib/apostrophe/`, confirmed non-stub):
application.rb (partial), document.rb, export_format.rb, fix_table.rb,
format_inserter.rb, helpers.rb, inhibitor.rb, latex_to_png.rb,
markup_handler.rb, markup_regex.rb, preview_converter.rb, search_bar.rb,
settings.rb, stats_counter.rb, stats_handler.rb, style.rb, text_buffer.rb,
text_view.rb, text_view_scroller.rb, theme.rb, theme_switcher.rb,
about_dialog.rb, hemingway_dialog.rb, shortcuts_window.rb.

That is 23 of the 38 units the inventory enumerates — more than the
inventory's own "18 of 38" headline, which was not updated after the three
dialogs and the search/stats/text_view trio landed. **Finding: the inventory
table's totals row is out of date and should not be read as current.**

Still genuinely missing from `lib/apostrophe/` (confirmed absent by file
listing, not just by the stale doc):

1. `main_window.rb` — the real `Adw.ApplicationWindow` chrome: the flap, the
   overlay stack, the discard-infobar error state, the save progress bar,
   the file-chooser save/open flows, the unsaved-changes `MessageDialog`.
   `application.rb` currently assembles a placeholder window inline instead.
2. `headerbar.rb` — the headerbar widget and its two menu models (`Menu`,
   `export_menu`); the 7 menu items and 6 export-menu items described in
   §3 of the inventory do not exist anywhere in `lib/`.
3. `open_popover.rb` — open/recents popover, including both empty states
   ("No Recent Documents", "No Results Found").
4. `preview_layout_switcher.rb` + `preview_layout_switcher_item.rb`.
5. `preview_handler.rb`, `preview_renderer.rb`, `preview_web_view.rb`,
   `preview_window.rb` — the entire preview pipeline. No WebKit binding is
   present in `flake.nix`/`nix/Gemfile`, so this is not just unported but
   currently unportable without new dependencies.
6. `preferences_dialog.rb`.
7. `advanced_export_dialog.rb`, `texlive_warning.rb`, and the quick-export
   `export_dialog.rb` (only the `Format` model, `export_format.rb`, exists).
8. `inline_preview.rb` (upstream itself has this disabled — lowest priority,
   correctly deprioritized, not a gap against upstream's *shipped* behavior).

## GActions — re-verified against `application.rb`

`grep` of `lib/apostrophe/application.rb` shows `install_action` /
`install_app_action`-style helpers producing **0 `app.*` actions** and
11 `win.*` actions. Upstream installs 7 `app.*` actions
(`color_scheme`, `new_window`, `preferences`, `shortcuts`, `about`, `quit`,
`stat_default`) and 16 `win.*` actions. None of the 7 `app.*` actions exist
in the port — `app.preferences`, `app.shortcuts`, and `app.about` are
reachable only because the drive script calls the dialog classes directly,
not through any installed action a real user's menu click would hit, since
the menu itself (`headerbar.rb`'s `Menu` model) does not exist either.

## Verdict

Component identification confirms the inventory's own "Blockers" section is
still fully open (WebKit absent, pandoc/TeX absent, Flap-vs-OverlaySplitView
undecided, no `po/`). Roughly 40% of upstream's user-facing surface — the
whole window chrome, every menu, the open/recents popover, the entire
preview feature, and 3 of 4 dialogs — has no `lib/` file at all. This is a
**mid-port snapshot, not a parity claim**.
