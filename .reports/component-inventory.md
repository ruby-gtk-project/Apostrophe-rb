# Apostrophe component inventory

Survey of upstream `origin/main` (Python/GTK4, GtkBuilder `.ui` templates)
against the `ruby` branch's `lib/apostrophe/`. No app code was written for
this survey; it is the map for the parity work that follows.

Upstream source: `apostrophe/*.py` (classes), `data/ui/*.ui` and
`data/ui/About.ui.in` (templates), `data/org.gnome.gitlab.somas.Apostrophe.gschema.xml`
(settings), `data/apostrophe.gresource.xml` (resource manifest), `po/` (34
`LINGUAS` catalogues).

Legend for **Status**: ✅ ported · ⚠️ ported but incomplete/placeholder ·
❌ missing.

## Window and chrome

| Upstream | → lib/apostrophe/ | Kind | Status |
|---|---|---|---|
| `apostrophe/main_window.py` (`MainWindow`) + `data/ui/Window.ui` | `main_window.rb` | window | ✅ |
| `apostrophe/headerbars.py` (`BaseHeaderbar`) + `data/ui/Headerbar.ui` | `headerbar.rb` | header bar | ✅ |
| `apostrophe/open_popover.py` (`ApostropheOpenPopover`, `RecentItem`) + `data/ui/Recents.ui` | `open_popover.rb` | popover (recent files) | ✅ (RecentItem GObject deliberately collapsed — see file comment) |
| `apostrophe/search_and_replace.py` (`ApostropheSearchBar`) + `data/ui/SearchBar.ui` | `search_bar.rb` | search/replace bar | ✅ |
| `apostrophe/theme_switcher.py` (`Theme`, `ThemeSwitcher`) + `data/ui/ThemeSwitcher.ui` | `theme.rb`, `theme_switcher.rb` | theme model + switcher widget | ✅ (split into two files) |
| `apostrophe/inhibitor.py` (`Inhibitor`) | `inhibitor.rb` | session-inhibit helper | ✅ |
| `apostrophe/stats_counter.py` (`StatsCounter`) | `stats_counter.rb` | stats label widget | ✅ |
| `apostrophe/stats_handler.py` (`StatsHandler`) | `stats_handler.rb` | stats computation | ✅ |

## Editor

| Upstream | → lib/apostrophe/ | Kind | Status |
|---|---|---|---|
| `apostrophe/text_view.py` (`ApostropheTextView`) + `data/ui/TextView.ui` | `text_view.rb` | text editor widget | ✅ |
| `apostrophe/text_buffer.py` (`ApostropheBuffer`) | `text_buffer.rb` | text buffer | ✅ |
| `apostrophe/text_view_markup_handler.py` (`MarkupHandler`) + `apostrophe/markup_regex.py` | `markup_handler.rb`, `markup_regex.rb` | markdown syntax highlighting | ✅ |
| `apostrophe/text_view_format_inserter.py` (`FormatInserter`) | `format_inserter.rb` | bold/italic/link insertion | ✅ |
| `apostrophe/text_view_scroller.py` (`TextViewScroller`) | `text_view_scroller.rb` | scroll-into-view helper | ✅ |
| `apostrophe/fix_table.py` (`fix_table`) | `fix_table.rb` | markdown table auto-align | ✅ |

## Preview

| Upstream | → lib/apostrophe/ | Kind | Status |
|---|---|---|---|
| `apostrophe/preview_renderer.py` (`PreviewRenderer`) | `preview_renderer.rb` | flap/window layout chrome | ✅ |
| `apostrophe/preview_window.py` (`PreviewWindow`) + `data/ui/PreviewWindow.ui` | `preview_window.rb` | detached "windowed" preview | ✅ |
| `apostrophe/preview_layout_switcher.py` + `data/ui/PreviewLayoutSwitcher.ui` | `preview_layout_switcher.rb` | layout picker popover | ✅ |
| `data/ui/PreviewLayoutSwitcherItem.ui` | `preview_layout_switcher_item.rb` | one layout option | ✅ |
| `apostrophe/preview_converter.py` (`PreviewConverter`) | `preview_converter.rb` | markdown→HTML via Pandoc | ✅ |
| `apostrophe/inline_preview.py` (`InlinePreviewHandler`?) | `inline_preview.rb` | inline (LaTeX/image) preview | ✅ |
| `apostrophe/latex_to_PNG.py` | `latex_to_png.rb` | LaTeX snippet → PNG | ✅ |
| `apostrophe/preview_handler.py` (`PreviewHandler`) | — (referenced, not built) | preview pipeline glue | ❌ **blocker**: needs a WebKit GTK4 binding; see `main_window.rb` comment at `preview_placeholder` |
| `apostrophe/preview_web_view.py` (`PreviewWebView`) | — (referenced, not built) | WebKit scroll-sync WebView subclass | ❌ **blocker**: same WebKit dependency |

`main_window.rb#preview_placeholder` stands in for the two missing pieces: the
flap/window chrome, layout switching and resize animation all work; only the
actual rendered-HTML content is a placeholder label, because this dev shell
has no WebKit2/WebKit GTK4 Ruby binding.

## Dialogs

| Upstream | → lib/apostrophe/ | Kind | Status |
|---|---|---|---|
| `apostrophe/export_dialog.py` (`ExportDialog`) + `data/ui/Export.ui` | `export_dialog.rb` | simple export | ✅ |
| `apostrophe/export_dialog.py` (`AdvancedExportDialog`) + `data/ui/Export.ui` | `advanced_export_dialog.rb` | advanced export window | ✅ |
| `apostrophe/export_dialog.py` (`Format`) | `export_format.rb` | export format descriptor | ✅ |
| `apostrophe/export_dialog.py` (`TexliveWarning`) + part of `data/ui/TexliveWarning.ui` | `texlive_warning.rb` | TeX-missing empty state | ✅ |
| `apostrophe/preferences_dialog.py` (`ApostrophePreferencesDialog`, `InputFormat`) + `data/ui/Preferences.ui` | `preferences_dialog.rb` | preferences window | ✅ |
| `data/ui/AboutHemingway.ui` | `hemingway_dialog.rb` | Hemingway-mode explainer | ✅ |
| `data/ui/About.ui.in` | `about_dialog.rb` | About window | ✅ |
| `data/ui/Shortcuts.ui` | `shortcuts_window.rb` | keyboard shortcuts window | ✅ |

## Application / settings / support

| Upstream | → lib/apostrophe/ | Kind | Status |
|---|---|---|---|
| `apostrophe/application.py` (`Application`) | `application.rb` | `Adw.Application` subclass, actions, accelerators | ✅ |
| `apostrophe/settings.py` (`Settings`) + `data/org.gnome.gitlab.somas.Apostrophe.gschema.xml` | `settings.rb` | GSettings wrapper | ✅ — verify every gschema key (`color-scheme`, `spellcheck`, `sync-scroll`, `input-format`, `autohide-headerbar`, `open-file-path`, `stat-default`, `characters-per-line`, `hemingway-mode`, `hemingway-toast-count`, `preview-mode`, plus window-state keys further down the schema) has a `settings.rb` accessor |
| `apostrophe/helpers.py` | `helpers.rb` | shared helpers (undo wrapper, error dialog, Pandoc call, debug info) | ✅ |
| `data/media/css/gtk/*.css`, `data/media/css/web/*.css` | `resources/css/gtk/*.css`, `resources/css/web/*.css` | stylesheets | ✅ copied; loader is `style.rb` (ported from the same CSS, no single upstream `.py`) |
| `data/lua/*.lua`, `data/media/apostrophe_markdown.md`, `data/media/icons/*.svg`, `data/reference_files/*` | `resources/lua/*`, `resources/apostrophe_markdown.md`, `resources/icons/*.svg`, `resources/reference_files/*` | bundled resources | ✅ copied |
| `data/apostrophe.gresource.xml` | — | GResource manifest | N/A — Ruby port loads files straight off disk (`resources/`), no `.gresource` bundle is built. Confirm every file the manifest lists has a copy under `lib/apostrophe/resources/` (spot-checked: icons, CSS, lua, markdown sample, reference docs all present; `markdown-mark.svg`, `raw_icons.svg` and `data/icons/*` app-icon assets were not checked here) |
| `data/org.gnome.gitlab.somas.Apostrophe.desktop.in.in`, `*.metainfo.xml.in(.in)` | — | desktop entry / AppStream metadata | not surveyed (packaging, not a UI component) |
| `po/*.po` (34 languages in `LINGUAS`) | — | translation catalogue | ❌ not present on `ruby` — no `po/` directory and no gettext wiring found in `lib/`; this is the `translation-parity` skill's job, flagged here as a gap |

`document.rb` has no upstream file of its own — it is the `File` dataclass
lifted out of the foot of `apostrophe/main_window.py` into its own file
(renamed because `File` collides with Ruby's own class).

## Summary

- Upstream Python modules: 29 (`apostrophe/*.py`, excluding `__init__.py`).
- Upstream `.ui` templates: 15, plus `About.ui.in`.
- `lib/apostrophe/`: 34 Ruby files map to upstream components (several
  upstream files split 1→2 for house-style reasons: `headerbars.py`'s
  `BaseHeaderbar`, `theme_switcher.py`'s two classes, `export_dialog.py`'s
  four classes).
- Only one real component gap: **the preview's HTML rendering pipeline**
  (`preview_handler.py` + `preview_web_view.py`), blocked on the lack of a
  WebKit GTK4 Ruby binding in this dev shell. Everything around it (layout,
  flap, resize, detached window, Pandoc conversion, LaTeX-to-PNG) is ported.
- Translation catalogue (`po/`) has not been started.
- Not yet checked in this survey (left for `component-parity`): CSS classes,
  signal names and action names per widget; GSettings key-by-key coverage;
  the full `data/apostrophe.gresource.xml` file list against
  `lib/apostrophe/resources/`.

## Blockers

- No Ruby WebKit GTK4 binding is available in the dev shell, so
  `preview_handler.rb` and `preview_web_view.rb` cannot be written; the
  preview pane is a placeholder label. Needs either a `webkit2gtk4`-style gem
  or an alternative HTML renderer before those two files can be ported.
