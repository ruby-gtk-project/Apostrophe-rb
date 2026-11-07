# Apostrophe — upstream component inventory

Survey step for the full-parity Ruby GTK4 / Libadwaita port. Upstream is the
PyGObject implementation on `origin/main` (`apostrophe/*.py` plus
`data/ui/*.ui`); the port is the `ruby` branch.

Method: the `component-identification` skill. Upstream has declarative UI
(`data/ui/*.ui`, GtkBuilder XML), so those were read first and are the
authoritative widget trees; the `.py` files beside them supply the callbacks,
the actions, the runtime-built widgets and the repeaters. Each row below unions
the `.ui` half and the `.py` half, because the component is the set of files,
not the file.

## Totals

| | Upstream | `ruby` branch |
|---|---:|---:|
| Source files contributing UI | 29 `.py` + 15 `.ui` | 28 `.rb` |
| Component units (templates, named roots, standalone `.ui`, app class) | 23 | 22 of the 38 rows below |
| Distinct CSS classes applied | 32 (11 app-defined in `data/media/css/gtk/style.css`) | all 8 stylesheets vendored |
| GActions installed | 7 `app.*` + 16 `win.*` | 4 `app.*` + 23 `win.*` |
| Accelerators declared | 12 in `application.py`, 10 more as `GtkShortcut` in `TextView.ui` | 13 |
| GSettings keys | 13 (+2 enums) | 13 (+2 enums), own schema |
| Translated catalogues | 33 locales in `po/`, 42 files in `POTFILES.in` | none |

Status as of round 2 (this commit): round 1 shipped the editor backbone —
buffer, markdown highlighter, insertion helpers, grammar, statistics counter,
smooth scroller, settings/schema, themes, stylesheets, icons, document model
and the shell-out workers. Round 2 adds the real `MainWindow` (file lifecycle
— new/open/save/save-as/close, the discard infobar, the save progress bar,
the unsaved-changes prompt), `HeaderBar` (both GMenu models, the save
split-button, the open button), the open/recents popover and the quick
`export_dialog.rb`. Every file-lifecycle action and every reachable menu item
now has a real action installed on `win.*`/`app.*` and is driven end-to-end by
`test/drive_apostrophe.rb`. Still missing: the preview pipeline (handler,
renderer, web view, window, layout switcher — blocked on no WebKit binding in
this dev shell), `preferences_dialog.rb`, `advanced_export_dialog.rb`,
`texlive_warning.rb`, `inline_preview.rb`, and the `po/` translation
catalogue.

## File-naming decision

The pilot port (`gnome-contacts-rb`) is flat: `lib/<thing>.rb` with top-level
classes. This repo is packaged as the `apostrophe-rb` gem, whose entry point
`exe/apostrophe` does `require "apostrophe"` → `lib/apostrophe.rb` →
`require_relative "apostrophe/application"`, and whose only existing component
already lives at `lib/apostrophe/application.rb` under `module Apostrophe`.
Targets below therefore keep that namespace directory — one upstream source
file to one `lib/apostrophe/<thing>.rb`, `require_relative` for siblings — and
otherwise follow the pilot's shape exactly (`# frozen_string_literal: true`,
`require 'adwaita'`, a comment naming the upstream file, memoized accessors,
`.tap` assembly in `build`).

## Components, in the order a user meets them

### 1. `apostrophe/application.py` — the application: actions, accels, theming

Target `lib/apostrophe/application.rb` · kind **application** · **exists
(partial)** — ported (round 2, after the window chrome moved out to
`main_window.rb`): the `Gtk::Application`, the stylesheet loading, the
icon-theme path, and 4 of 7 `app.*` actions (`new_window`, `quit`,
`shortcuts`, `about`) with accelerators for the first two. Not ported:
`color_scheme`, `preferences`, `stat_default`; the `Gtk::WindowGroup` per
window (the port tracks windows as a plain array instead); the sepia provider
add/remove per display and the `Adwaita::StyleManager` notify handlers. The
window chrome itself (headerbar, editor, menus, file lifecycle) now lives in
`main_window.rb` (§2) and `headerbar.rb` (§3), as upstream splits it

| Item | × | Notes |
|---|---:|---|
| `Adw.Application` subclass | 1 | `HANDLES_OPEN \| NON_UNIQUE`; resource base path `/org/gnome/gitlab/somas/Apostrophe`. Per the `ruby-gtk` skill `Adwaita::Application` is broken in the bindings — the port uses `Gtk::Application`, which the placeholder already does |
| `Gtk.WindowGroup` | n | one per window; `self.windows` is a list of groups. Repeater driven by `do_open` / `app.new_window` |
| `Gtk.CssProvider` | 1 | loads `style-sepia.css`, added/removed per display when the sepia theme is active |
| `Adw.StyleManager` | 1 | `notify::dark`, `notify::high-contrast` → `_set_color_scheme` |
| `Gtk.IconTheme` | 1 | adds the resource icon path |

Actions installed: `app.color_scheme` (stateful, `s`), `app.new_window`,
`app.preferences`, `app.shortcuts`, `app.about`, `app.quit`,
`app.stat_default` (stateful, `s`). Accels set here: `win.focus_mode` `<Ctl>d`,
`win.hemingway_mode` `<Ctl>t`, `win.preview` `<Ctl>p`, `win.fullscreen` `F11`,
`win.find` `<Ctl>f`, `win.find_replace` `<Ctl>h`, `app.spellcheck` `F7`,
`app.new_window` `<Ctl>n`, `win.open` `<Ctl>o`, `win.save` `<Ctl>s`,
`win.save_as` `<Ctl><shift>s`, `app.quit` `<Ctl>q`, `win.close` `<Ctl>w`.
Note `app.spellcheck` has an accel but no action — upstream bug, reproduce or
drop deliberately. `do_open` reuses empty untouched windows before making new
ones; the Devel app id adds the `devel` CSS class to every window.

### 2. `apostrophe/main_window.py` + `data/ui/Window.ui` — the editor window

Target `lib/apostrophe/main_window.rb` · kind **window** · **ported** (round 2: file lifecycle, discard infobar, save progress bar, unsaved-changes prompt; preview flap/stack and fullscreen left out,
no WebKit binding in this dev shell)

| Widget | × | CSS | Signals / behaviour |
|---|---:|---|---|
| `Adw.ApplicationWindow` (`ApostropheWindow`) | 1 | `apostrophe-window`, `scrolled` (dynamic, on vadjustment ≠ 0), `no-headerbar` (dynamic, when the headerbar hides), `devel` (dynamic, Devel build) | `notify::is-fullscreen` → `_on_fullscreen`; `close-request` → `do_close_request`; default 1000×600 |
| `Gtk.Overlay` (`AppOverlay`) | 1 | — | named `FullscreenOverlay`; holds the flap plus the top-bar overlay |
| `Adw.Flap` (`flap`) | 1 | `preview-flap` | flap-position end, fold-policy never, reveal false, swipe off. Driven by `PreviewRenderer` |
| `Gtk.Overlay` (`editor`) | 1 | — | — |
| `Adw.ToastOverlay` (`toast_overlay`) | 1 | — | hosts the Hemingway toast |
| `Gtk.ScrolledWindow` (`editor_scrolledwindow`) | 1 | — | vscrollbar margins 54/48; `vadjustment notify::value` → `_on_scroll` |
| `ApostropheTextView` (`textview`) | 1 | see §9 | app-defined widget, own unit |
| `Gtk.EventControllerFocus` | 1 | — | `leave` → `reveal_headerbar_bottombar` |
| `Gtk.Revealer` (`stats_revealer`) | 1 | — | crossfade 750ms, reveal true, valign/halign end |
| `Gtk.MenuButton` (`stats_button`) | 1 | `stats-button` | label "0 Words"; popover and menu built by `StatsHandler` (§15) |
| `Gtk.EventControllerMotion` | 2 | — | one on `stats_revealer` → `reveal_bottombar`, one on the headerbar → `reveal_headerbar_bottombar` |
| `Gtk.Stack` (`preview_stack`) | 1 | `preview-stack`, plus `half-width` / `full-width` (dynamic, set by `PreviewRenderer`) | crossfade, overflow hidden |
| `Gtk.Spinner` (`preview_spinner`) | 1 | — | spinning; the preview's loading state |
| `BaseHeaderbar` (`headerbar`) | 1 | — | app-defined; §3. Bound `title`, `subtitle`, `is-fullscreen` |
| `Gtk.InfoBar` (`discard_infobar`) | 1 | — | warning, close button, revealed false; `response` → `dismiss_discard_infobar`. **Error state:** "File Has Changed on Disk" / "The file has been changed by another program." |
| `Gtk.Label` | 2 | — | infobar title (bold attr) and subtitle |
| `Gtk.Button` (`discard`) | 1 | — | "_Discard Changes and Reload" → `reload_file` |
| `Gtk.ProgressBar` (`save_progressbar`) | 1 | `osd` | hidden; animated on save |
| `ApostropheSearchBar` (`searchbar`) | 1 | — | app-defined; §8 |
| `Adw.TimedAnimation` | 2 | — | progressbar fraction 0→1 300ms, fade-out 1→0 500ms `EASE_OUT_CUBIC` |
| `Adw.Toast` | 1 | — | "Text can't be deleted while on Hemingway mode", 3s, button "Tell me more" → `win.show_hemingway_help`; shown at most 3× via `hemingway-toast-count` |
| `Gtk.FileChooserNative` | 2 | — | **built in source, not in the `.ui`**: Save ("Save your File", filters `text/x-markdown`, `text/plain`, name defaults to `<title>.md`) and Open ("Open a .md file", Markdown Files + Plain Text Files filters) |
| `Adw.MessageDialog` | 1 | — | **built in source**: "Save changes?" / "“%s” contains unsaved changes…", responses cancel / close ("Discard", destructive) / save ("Save", suggested), default save, close-response cancel |

Actions installed: `win.find`, `win.find_replace`, `win.focus_mode`,
`win.hemingway_mode`, `win.fullscreen`, `win.preview` (all
`Gio.PropertyAction`), `win.show_hemingway_toast`, `win.show_hemingway_help`,
`win.new`, `win.open`, `win.open_file` (`s`), `win.save`, `win.save_as`,
`win.export` (`s`), `win.advanced_export`, `win.copy_html`, `win.close`.
Settings bound: `bigger-text`, `characters-per-line` (GET) to the textview;
`preview-active`, `hemingway-mode`, `preview-mode` read at startup and written
by `save_state`. A `Gio.FileMonitor` on the current file raises the discard
infobar. Note the workaround at the end of `__init__` forcing
`preview_layout = 3` (windowed) regardless of the setting.

### 3. `apostrophe/headerbars.py` + `data/ui/Headerbar.ui` — headerbar and menus

Target `lib/apostrophe/headerbar.rb` · kind **headerbar + menu models** ·
**ported** (round 2: `Menu` and `export_menu` GMenu models, save split-button, open button; preview-layout switcher and the exit-fullscreen button left out)

| Widget | × | CSS | Signals / action |
|---|---:|---|---|
| `Gtk.Revealer` (`BaseHeaderbar` root) | 1 | — | properties `is_fullscreen`, `title`, `subtitle`; `is-fullscreen` bound to the header bar's `show-start/end-title-buttons` |
| `Adw.HeaderBar` (`headerbar`) | 1 | `titlebar` | — |
| `Gtk.Button` | 1 | — | tooltip "New" → `app.new_window`, icon `document-new-symbolic` |
| `Gtk.MenuButton` | 1 | — | label "Open", popover = `ApostropheOpenPopover` (§4) |
| `Adw.SplitButton` | 1 | — | label "Save" → `win.save`, menu `export_menu` |
| `Gtk.Button` (`exit_fs_button`) | 1 | — | → `win.fullscreen`, icon `view-restore-symbolic`, visible only fullscreen |
| `Gtk.MenuButton` (`menu_button`) | 1 | `image-button` | icon `open-menu-symbolic`, tooltip "Menu", menu `Menu` |
| `PreviewLayoutSwitcher` | 1 | — | app-defined; §6 |
| `Gtk.ToggleButton` | 1 | — | tooltip "Find" → `win.find`, icon `system-search-symbolic` |

Menu `Menu` (7 items + 1 custom slot): `custom themeswitcher` (hosts
`ThemeSwitcher`, §5, added in source via `popover.add_child`), `_Hemingway
Mode` → `win.hemingway_mode`, `_Focus Mode` → `win.focus_mode`, `Find and
_Replace` → `win.find_replace`, `_Preferences` → `app.preferences`, `Open
_Tutorial` → `win.open_file` targeting
`resource:///…/media/apostrophe_markdown.md`, `_Keyboard Shortcuts` →
`app.shortcuts`, `_About Apostrophe` → `app.about`.
Menu `export_menu` (6 items): `_Save As...` → `win.save_as`; `_PDF` / `_HTML` /
`_ODT` → `win.export` with targets `pdf` / `html` / `odt`; `Advanced _Export…`
→ `win.advanced_export`; `_Copy HTML` → `win.copy_html`.

### 4. `apostrophe/open_popover.py` + `data/ui/Recents.ui` — open / recents popover

Target `lib/apostrophe/open_popover.rb` · kind **popover + empty states** ·
**ported** (round 2: search entry, recents list, delete-from-recents; rebuilds its rows off `Gtk::RecentManager` directly instead of `bind_model`ing a custom GObject)

| Widget | × | CSS | Signals |
|---|---:|---|---|
| `Gtk.Popover` (`ApostropheOpenPopover`) | 1 | `open-popover` | halign start, valign end, width 350 |
| `Gtk.SearchEntry` (`search_entry`) | 1 | — | `search-changed` → `on_search_entry_changed_cb`, `activate`, `stop-search` |
| `Gtk.Button` | 1 | — | icon `document-open-symbolic` → `win.open` |
| `Gtk.Separator` | 1 | — | — |
| `Gtk.Stack` (`stack`) | 1 | — | switches `empty` ↔ `recent` |
| `Gtk.Label` (`empty`) | 1 | — | **empty state:** "No Recent Documents" |
| `Gtk.ScrolledWindow` (`recent`) | 1 | — | max 600×250, min width 250 |
| `Gtk.ListBox` (`list_box`) | 1 | — | selection none; `bind_model` over a `Gio.ListStore` of `RecentItem` |
| `Gtk.Label` (list-box placeholder) | 1 | `placeholder`, `dim-label` | **empty state:** "No Results Found" |
| `Adw.ActionRow` | n | — | **repeater** over `Gtk.RecentManager.get_items()`; title = display name, subtitle = uri_display, activatable → `win.open_file` with the uri as target |
| `Gtk.Button` (per row) | n | `flat`, `circular` | icon `window-close-symbolic`, valign center, `clicked` → `recents_manager.remove_item` |

`recents_manager` `changed` → `on_manager_changed` rebuilds the model. The
search filter is a plain substring match over display names.

### 5. `apostrophe/theme_switcher.py` + `data/ui/ThemeSwitcher.ui` — colour-scheme selector

Target `lib/apostrophe/theme_switcher.rb` (widget) and
`lib/apostrophe/theme.rb` (the `Theme` value object + `defaultThemes`) ·
kind **menu custom widget** · **exists** (both files ported)

| Widget | × | CSS | Signals |
|---|---:|---|---|
| `Gtk.Box` (`ThemeSwitcher` root) | 1 | `themeswitcher` | property `show_system` bound to `Adw.StyleManager:system-supports-color-schemes` |
| `Gtk.Box` | 1 | — | halign center, spacing 8 |
| `Gtk.CheckButton` | 4 | `system`, `light`, `sepia`, `dark` (one each) | all three non-system grouped to `system_selector`; each `notify::active` → `_on_color_scheme_changed`; tooltips "Use System/Light/Sepia/Dark Colors" |

`selected_color_scheme` is a read-write `GObject.Property` bound to the
`color-scheme` setting; it drives `Adw.ColorScheme.PREFER_LIGHT` /
`FORCE_LIGHT` / `FORCE_DARK`. `Theme` maps each scheme to the web stylesheet
used by preview and export (`adwaita.css`, `adwaita-sepia.css`).

### 6. `apostrophe/preview_layout_switcher.py` + `data/ui/PreviewLayoutSwitcher.ui`

Target `lib/apostrophe/preview_layout_switcher.rb` · kind **headerbar
control + popover** · **missing**

| Widget | × | CSS | Signals |
|---|---:|---|---|
| `Gtk.Box` (`PreviewLayoutSwitcher` root) | 1 | — | property `preview_layout` (int) |
| `Gtk.ToggleButton` (`preview_switcher_toggle`) | 1 | `preview_button_left` | → `win.preview`, icon `view-dual-symbolic`, tooltip "Preview" |
| `Gtk.Revealer` (`preview_switcher_revealer`) | 1 | — | slide-right, revealed while the toggle is active |
| `Gtk.MenuButton` (`preview_switcher_button`) | 1 | `preview_button_right`, `raised` | always-show-arrow, a11y label "Screen Layout" |
| `Gtk.Image` (`layout_image`) | 1 | — | icon follows the current layout |
| `Gtk.Popover` (`layout_popover`) | 1 | `menu` | `show` → `update_ui` |
| `Gtk.ListBox` (`list_box`) | 1 | — | selection none; `row-activated` → `on_row_activated` |

### 7. `data/ui/PreviewLayoutSwitcherItem.ui` (+ the same `.py`) — one layout row

Target `lib/apostrophe/preview_layout_switcher_item.rb` · kind **row** ·
**missing**

| Widget | × | CSS | Notes |
|---|---:|---|---|
| `Gtk.ListBoxRow` (`PreviewLayoutSwitcherItem`) | 1 | — | property `selected`; `notify::selected` → `on_selected` |
| `Gtk.Box` | 2 | — | outer, plus an inner halign-start spacing-12 box |
| `Gtk.Image` (`icon`) | 1 | `list-icon` | `preview-layout-{full-width,half-width,half-height,windowed}-symbolic` |
| `Gtk.Label` (`title`) | 1 | — | "Full-Width" / "Half-Width" / "Half-Height" / "Windowed" |
| `Gtk.Image` (`checkmark`) | 1 | `checkmark` | `emblem-ok-symbolic`, opacity 0/1 by `selected` |

**Repeater:** instantiated once per `PreviewLayout` member — 4 rows on screen
from one textual occurrence.

### 8. `apostrophe/search_and_replace.py` + `data/ui/SearchBar.ui` — find and replace

Target `lib/apostrophe/search_bar.rb` · kind **search bar** · **missing**

| Widget | × | CSS | Signals |
|---|---:|---|---|
| `Adw.Bin` (`ApostropheSearchBar`) | 1 | — | properties `search_mode_enabled`, `replace_mode_enabled` |
| `Gtk.SearchBar` (`searchbar`) | 1 | — | search-mode bound to the property |
| `Gtk.Box` | 6 | `linked` on `searchbox_box`, `searchtools_box`, `replacebox_box`, `replacetools_box` | panel, search row, replace row and the four linked groups |
| `Gtk.SearchEntry` (`search_entry`) | 1 | — | `search-changed` → `search`, `stop-search` → `hide` |
| `Gtk.Button` (`previous_result`) | 1 | — | `go-up-symbolic`, tooltip "Previous Match" → `scrolltoprev` |
| `Gtk.Button` (`next_result`) | 1 | — | `go-down-symbolic`, tooltip "Next Match" → `scrolltonext` |
| `Gtk.ToggleButton` (`case_sensitive`) | 1 | — | label "aA" (translated), tooltip "Case Sensitive" → `search` |
| `Gtk.ToggleButton` (`regex`) | 1 | — | label "(.*)", tooltip "Regular Expression" → `search` |
| `Gtk.ToggleButton` (`replace`) | 1 | — | icon `edit-find-replace-symbolic`, tooltip "Replace", `active` bound bidirectionally to `replace_mode_enabled` |
| `Gtk.Revealer` (`replace_placeholder`) | 1 | — | revealed with replace mode |
| `Gtk.Entry` (`replace_entry`) | 1 | — | primary icon `edit-find-replace-symbolic` |
| `Gtk.Button` (`replace_one`) | 1 | — | "Replace" → `replace_clicked` |
| `Gtk.Button` (`replace_all`) | 1 | — | "Replace All" → `replace_all` |
| `Gtk.WidgetPaintable` | 1 | — | not a widget — `invalidate-size` → `update_textview_margin`, which pushes the bar's height into the text view's top margin |

Behaviour: a `search_highlight` `Gtk.TextTag` (background yellow) is created on
the buffer; matches are collected with a Ruby/Python regex, highlighted, and
cycled with wraparound; replace-all runs inside one user action (undo step).

### 9. `apostrophe/text_view.py` + `data/ui/TextView.ui` — the editor view

Target `lib/apostrophe/text_view.rb` · kind **widget (editor)** · **missing**

| Widget | × | CSS | Signals |
|---|---:|---|---|
| `Gtk.TextView` (`ApostropheTextView`) | 1 | `apostrophe-editor`, plus `size{14,15,16,17,18,20,22,24}` (dynamic, one at a time by width) | `notify::focus-mode` → `_on_focus_mode_update`, `notify::spellcheck` → `_on_spellcheck_update`, `notify::bigger-text` → `_update_horizontal_margin`; wrap word-char, pixels 4/4/8 |
| `ApostropheTextBuffer` (`buffer`) | 1 | — | `mark-set` → `_on_mark_set`, `paste-done` → `_on_paste_done`, `changed` → `_on_text_changed`. Declared as a top-level named object in the `.ui`, not a template child |
| `Gtk.GestureClick` (`gesture_controller`) | 1 | — | controller — `released` → `_on_button_release_event` |
| `Gtk.ShortcutController` + `Gtk.Shortcut` | 1 + 10 | — | controller — `<Shift>ISO_Left_Tab`→`unindent`, `<Control>i`→`insert-italic`, `<Control>b`→`insert-bold`, `<Control>r`→`insert-hrule`, `<Control>u`→`insert-listitem`, `<Control><Shift>d`→`insert-strikethrough`, `<Control>1..4`→`insert-header(n)` |
| `Gtk.DropTarget` | 1 | — | controller, **built in source** — `drop` → `on_drop`, turns dropped files/URLs into `![alt](path)` or `[text](url)` |
| `Adw.SpringAnimation` | 1 | — | not a widget — the left-margin shake when Hemingway mode blocks a delete |

Own signals: `unindent`, `insert-italic`, `insert-bold`, `insert-hrule`,
`insert-listitem`, `insert-header(int)`, `insert-strikethrough`,
`scroll-scale-changed(float)`. Properties: `bigger_text`, `hemingway_mode`,
`focus_mode`, `font_size`, `line_chars`, `spellcheck`, `scroll_scale`. Margins
are computed from a font-size ladder (`[20,18,17,16,15,14]`, prefixed with
`[24,22]` when `bigger-text`); focus mode halves the vertical margins.
Four blocked deletes within 70s re-arm the Hemingway toast.

### 10. `apostrophe/text_buffer.py` — the buffer: Hemingway mode, list indent

Target `lib/apostrophe/text_buffer.rb` · kind **model (GtkTextBuffer
subclass)** · **exists**

Own signal `attempted-hemingway`. Property `hemingway_mode`. `_indent` /
`_unindent` cycle unordered-list markers `- * +` and renumber ordered lists;
when Hemingway mode is on, deletions emit `attempted-hemingway` instead.

### 11. `apostrophe/text_view_markup_handler.py` — live markdown highlighting

Target `lib/apostrophe/markup_handler.rb` · kind **behaviour (TextTag
table)** · **exists**

Creates 10+ `Gtk.TextTag`s: italic, bold, bold-italic, strikethrough, center,
wrap-none, plain-text, gray-text, code-text, code-block, unfocused-text, plus
margin/indent tags made on demand. Re-reads colours from the style context on
`on_style_updated`. Parsing runs in a worker process. **Not a widget, but
dropping it loses the editor's entire visual identity.**

### 12. `apostrophe/text_view_format_inserter.py` — markdown insert helpers

Target `lib/apostrophe/format_inserter.rb` · kind **behaviour** · **exists**

Handlers for the ten `GtkShortcut` signals in §9: italic, bold, strikethrough,
horizontal rule, list item, ordered list item, header levels 1–4. Inserts
placeholder help text and selects it.

### 13. `apostrophe/text_view_scroller.py` — smooth scrolling

Target `lib/apostrophe/text_view_scroller.rb` · kind **behaviour** ·
**exists**

`TextViewScroller` plus `SmoothScroller` (frame-clock tick, ease-out-cubic).
Supplies `scroll_scale` for editor/preview sync.

### 14. `apostrophe/markup_regex.py` — the markdown grammar

Target `lib/apostrophe/markup_regex.rb` · kind **constants** · **exists**

20 named regexes (`ITALIC_ASTERISK`, `BOLD`, `IMAGE`, `LINK`, `TABLE`,
`CODE_BLOCK`, `HEADER`, `FOOTNOTE`, …) shared by the markup handler, the stats
counter, the buffer's list handling and the inline preview.

### 15. `apostrophe/stats_handler.py` — the statistics button and its menu

Target `lib/apostrophe/stats_handler.rb` · kind **popover menu** ·
**missing**

| Widget | × | Notes |
|---|---:|---|
| `Gtk.PopoverMenu` | 1 | halign end, margins 6/6, no arrow, attached to `stats_button`; `closed` → refocus the editor; direction UP; menu rebuilt by `set_create_popup_func` |
| `Gio.MenuItem` | 5 | **repeater** over the `stat-default` enum range — Characters, Words, Sentences, Paragraphs, Read Time — each targeting `app.stat_default` |

Labels are plural-aware (`ngettext`) and switch to "{n} of {n} …" while there
is a selection; read time renders as `H:MM:SS Read Time`.

### 16. `apostrophe/stats_counter.py` — counting worker

Target `lib/apostrophe/stats_counter.rb` · kind **behaviour** · **exists**

Strips markup via the §14 regexes, then counts characters, words, sentences and
paragraphs and derives read time at 200 wpm. Upstream runs it in a
`multiprocessing.Process` behind a pipe watched with `GLib.io_add_watch`.

### 17. `apostrophe/preview_handler.py` — preview orchestration

Target `lib/apostrophe/preview_handler.rb` · kind **behaviour** · **missing**

Three-step pipeline (convert HTML → load webview → render), lazy webview
creation, editor/preview scroll sync gated on `sync-scroll`, external links
opened in the browser, and `reload`/`back`/`forward`/`stop` stripped from the
webview context menu.

### 18. `apostrophe/preview_renderer.py` — the four preview layouts

Target `lib/apostrophe/preview_renderer.rb` · kind **behaviour (layout
state machine)** · **missing**

Drives `Adw.Flap` orientation and fold policy, adds/removes the
`half-width` / `full-width` classes on `preview_stack`, animates the window
width with `Adw.TimedAnimation` when entering/leaving half-width, and moves the
stack into `PreviewWindow` for the windowed layout. Transitions are an explicit
`match (cache, next)` table — port it as a table, not as nested conditionals.

### 19. `apostrophe/preview_web_view.py` — the preview WebView

Target `lib/apostrophe/preview_web_view.rb` · kind **widget** · **missing**

`WebKit2.WebView` subclass with a `scroll-scale-changed` signal, a ~60 Hz
JavaScript state loop that reads and writes `scrollTop`, MathJax-aware
"is rendered" detection, and user-gesture navigation redirected to the browser.

### 20. `apostrophe/preview_converter.py` — markdown → HTML worker

Target `lib/apostrophe/preview_converter.rb` · kind **behaviour** ·
**exists**

Background thread over a queue; calls pandoc with `--standalone --mathjax
--css=<theme web css>` and the two Lua filters.

### 21. `apostrophe/preview_window.py` + `data/ui/PreviewWindow.ui` — windowed preview

Target `lib/apostrophe/preview_window.rb` · kind **window** · **missing**

| Widget | × | CSS |
|---|---:|---|
| `Adw.ApplicationWindow` (`ApostrophePreviewWindow`) | 1 | — |
| `Gtk.Box` (`preview_box`) | 1 | — |
| `Adw.HeaderBar` | 1 | `flat` |

Title tracks the main window's title + " - Preview"; closing it sets
`win.preview` false.

### 22. `apostrophe/preferences_dialog.py` + `data/ui/Preferences.ui` — preferences

Target `lib/apostrophe/preferences_dialog.rb` · kind **dialog
(preferences)** · **missing**

| Widget | × | CSS | Signals / binding |
|---|---:|---|---|
| `Adw.PreferencesWindow` (`ApostrophePreferencesDialog`) | 1 | — | default height 380, search disabled |
| `Adw.PreferencesPage` | 1 | — | — |
| `Adw.PreferencesGroup` | 1 | — | — |
| `Adw.ActionRow` | 4 | — | "Check spelling while typing" (**visible False** upstream), "Autohide headerbar", "Use bigger text", "Restore session" (**visible False**) |
| `Gtk.Switch` | 4 | — | `spellcheck_switch`, `autohide_headerbar_switch`, `bigger_text_switch`, `session_restore_switch`; first three bound to the matching GSettings keys |
| `Adw.ComboRow` (`input_format_comborow`) | 1 | — | "Input format"; `notify::selected` → `on_input_format`; model is a `Gio.ListStore` of `InputFormat` |
| `Gtk.Button` | 1 | `flat`, `circular` | `dialog-information-symbolic`, tooltip "Markdown flavor documentation" → `on_input_format_help`, opens the flavour's URL |

`InputFormat` is a small `GObject` (name/format/help) with five entries:
Pandoc's Markdown, CommonMark, GitHub Flavored Markdown, MultiMarkdown, Plain
Markdown. Two rows are hidden upstream — reproduce them hidden, do not silently
drop them.

### 23. `data/ui/Shortcuts.ui` — keyboard shortcuts window

Target `lib/apostrophe/shortcuts_window.rb` · kind **dialog (shortcuts)** ·
**missing** · no backing source file; built by `app.shortcuts` from the
resource

`Gtk.ShortcutsWindow` → 1 `Gtk.ShortcutsSection` → 8 `Gtk.ShortcutsGroup`
(General, Modes, Find, Markdown, Copy and paste, Undo and redo, Selection) →
23 `Gtk.ShortcutsShortcut`: New `<Primary>n`, Open `<Primary>o`, Save
`<Primary>s`, Save as `<Shift><Primary>s`, Close document `<Primary>w`, Quit
`<Primary>q`; Focus mode `<Primary>d`, Hemingway mode `<Primary>t`, Preview
`<Primary>p`, Fullscreen `F11`; Find `<Primary>f`, Find and replace
`<Primary>h`; Separator `<Primary>r`, Header `<Primary>1 4`, List item
`<Primary>u`, Italic `<Primary>i`, Bold `<Primary>b`, Strikeout
`<Shift><Primary>D`; Copy/Cut/Paste `<Primary>C/X/V`; Undo `<Primary>Z`, Redo
`<Shift><Primary>Z`; Select all `<Primary>A`. The pilot uses
`Adwaita::ShortcutsDialog`, which is the modern equivalent.

### 24. `data/ui/About.ui.in` — about dialog

Target `lib/apostrophe/about_dialog.rb` · kind **dialog (about)** ·
**missing** · no backing source file; populated by `Application.on_about`

`Adw.AboutWindow` with app name, icon, version, copyright, website,
developer-name, developers, translator-credits, artists, designers, issue URL,
`gpl-3-0`, debug-info filename `apostrophe-debug-info.txt`. `on_about` also
sets the debug info from `helpers.get_debug_info()` and adds two links:
"Donate" and "Translations".

### 25. `data/ui/AboutHemingway.ui` — Hemingway mode explainer

Target `lib/apostrophe/hemingway_dialog.rb` · kind **dialog (message)** ·
**missing** · opened by `win.show_hemingway_help`

`Adw.MessageDialog`, heading "Hemingway Mode", a two-paragraph body, one
response `cancel` = "_Close", close-response cancel.

### 26. `apostrophe/export_dialog.py` (`AdvancedExportDialog`) + `data/ui/Export.ui`

Target `lib/apostrophe/advanced_export_dialog.rb` · kind **dialog
(multi-page)** · **missing**

| Widget | × | CSS | Signals / binding |
|---|---:|---|---|
| `Adw.Window` (`AdvancedExportDialog`) | 1 | — | modal, 800×550, destroy-with-parent |
| `Adw.HeaderBar` (`headerbar`) | 1 | — | — |
| `Gtk.Revealer` (`go_previous_revealer`) | 1 | — | slide-right 150ms, bound to `show_go_back_button` |
| `Gtk.Button` (`go_previous_button`) | 1 | — | `go-previous-symbolic` → `go_back` |
| `Gtk.Button` | 1 | `popup` | "Cancel" → `on_destroy` |
| `Gtk.Button` (`export_button`) | 1 | `popup`, `suggested-action` | "Export" → `export`; insensitive while the TexLive warning shows |
| `Adw.Leaflet` (`leaflet`) | 1 | — | `notify::folded` and `notify::visible-child` → `reveal_go_back` |
| `Gtk.ScrolledWindow` (`formats_page`) | 1 | — | min width 300 |
| `Gtk.Viewport` | 3 | — | — |
| `Gtk.ListBox` (`formats_list`) | 1 | — | `row-selected` → `on_format_selected`; `bind_model` over `Format` |
| `Adw.ActionRow` | n | — | **repeater** over `data/media/formats.json` — one row per export format, built by `row_constructor` |
| `Gtk.Separator` | 1 | — | vexpand |
| `Gtk.Stack` (`options_page`) | 1 | — | pages "FALSE" (options) and "TRUE" (`TexliveWarning`) |
| `Gtk.ScrolledWindow` (`options`) | 1 | — | min width 400 |
| `Adw.Clamp` | 1 | — | max 550, tightening 300 |
| `Gtk.Box` | 2 | — | vertical |
| `Adw.PreferencesGroup` | 5 | — | Options (untitled), "Page Size" (`page_options`), "HTML Options" (`html_options`), "Syntax Highlighting" (`syntax_options`), "Presentation" (`beamer_options`) — each `visible` bound to a computed property |
| `Adw.ExpanderRow` | 2 | — | "Options"; "Use Syntax Highlighting" (`sw_syntax_highlighting`, show-enable-switch) |
| `Adw.ActionRow` | 5 | — | Standalone, Table of Contents, Number Sections, Self-contained, Incremental bullets (each with subtitle where upstream has one) |
| `Gtk.Switch` | 5 | — | `sw_standalone` (on), `sw_toc` (sensitive-bound to standalone), `sw_numbers`, `sw_self_contained` (on), `sw_incremental_bullets` (on) |
| `Adw.ComboRow` | 2 | — | `cmb_page_size` (A4, Letter), `cmb_syntax_highlighting` (pygments, kate, monochrome, espresso, zenburn, haddock, tango) |
| `TexliveWarning` (`texlive_warning`) | 1 | — | app-defined; §28 |
| `Gtk.FileChooserNative` | 1 | — | **built in source** — SAVE, or SELECT_FOLDER for reveal.js (which also unzips `reveal.js.zip`) |

Computed properties gate the groups: `show_page_size_options`,
`show_html_options`, `show_syntax_options`, `show_presentation_options`,
`show_texlive_warning`, `show_go_back_button`, `options_page_name`,
`exports_multiple_files`. `retrieve_args` assembles the pandoc argv.

### 27. `apostrophe/export_dialog.py` (`ExportDialog`, `Format`, `export`) — quick export

Targets `lib/apostrophe/export_dialog.rb` (the quick PDF/HTML/ODT path) and
`lib/apostrophe/export_format.rb` (the `Format` model + `formats.json`) ·
kind **dialog (file chooser) + model** · **ported** (round 2: `export_dialog.rb`
now opens the chooser and runs Pandoc; the TeXLive-warning branch for a
PDF export without `pdftex` is left out — a PDF export without TeX simply
surfaces Pandoc's own failure through the same error dialog)

`win.export` with target `pdf` / `html` / `odt` opens a
`Gtk.FileChooserNative` ("Export", "Export to %s", one mime filter, name
`<doc>.<ext>`) — unless the target is PDF and `pdftex` is absent, in which case
it opens an `Adw.MessageDialog` whose extra child is `TexliveWarning` with a
single "Close" response. **Error state:** export failures raise "An error
happened while trying to export:\n\n{err_msg}" through `helpers.show_error`.
`Format` exposes `has_pages`, `is_html`, `has_syntax`, `is_presentation`,
`requires_texlive`.

### 28. `apostrophe/export_dialog.py` (`TexliveWarning`) + `data/ui/TexliveWarning.ui`

Target `lib/apostrophe/texlive_warning.rb` · kind **error / empty state** ·
**missing**

| Widget | × | CSS | Notes |
|---|---:|---|---|
| `Gtk.Stack` (`TexliveWarning`) | 1 | — | page `flatpak` or `distro`, chosen by `/.flatpak-info` |
| `Gtk.Box` | 2 | — | one per page, centred, spacing 16, margins 12 |
| `Gtk.Label` | 4 | `title-2` on the two headings | "TexLive Required" ×2 plus the two bodies |
| `Gtk.Entry` (`command`) | 1 | — | non-editable `flatpak install …Plugin.TexLive`, max 48 chars |
| `Gtk.Button` | 1 | — | "Copy to clipboard" → `copy` |

### 29. `apostrophe/inline_preview.py` — ctrl-click quick preview popover

Target `lib/apostrophe/inline_preview.rb` · kind **popover** · **missing** ·
*currently commented out in upstream's `text_view.py`*

| Widget | × | CSS | Notes |
|---|---:|---|---|
| `Gtk.Popover` | 1 | `quick-preview-popup` | modal, attached to the text view; opened on ctrl+click via the view's `Gtk.GestureClick` |
| `Gtk.Image` | 1 | — | rendered LaTeX (via `LatexToPNG`) or the image under the cursor |
| `Gtk.Label` | 1..n | — | footnote text, or "Formula looks incorrect:", or "No matching footnote found" |
| `Gtk.Grid` | 1 | `lexikon` | dictionary lookup over DICT/WordNet |
| `Gtk.Label` (in the grid) | n | `header`, `first`, `number`, `description` | **repeater** over definitions; word types "noun", "verb", "adjective", "adverb" |

The DICT client (`DictAccessor`) uses `telnetlib`, removed from Python 3.13 and
with no Ruby equivalent in the bundle — expect to reimplement it over a plain
TCP socket, or to port this component last.

### 30. `apostrophe/latex_to_PNG.py` — formula rendering

Target `lib/apostrophe/latex_to_png.rb` · kind **behaviour** · **exists**

Shells out to LaTeX + dvipng into a cache dir; feeds §29's `Gtk.Image`.

### 31. `apostrophe/fix_table.py` — markdown table reflow

Target `lib/apostrophe/fix_table.rb` · kind **behaviour** · **exists**

Pure buffer transformation: finds the table around the cursor and rewrites it
with aligned columns. Listed in `POTFILES.in`; reachable in upstream only
through the table code path, with no menu item.

### 32. `apostrophe/settings.py` + `data/org.gnome.gitlab.somas.Apostrophe.gschema.xml`

Target `lib/apostrophe/settings.rb` · kind **settings** · **exists** —
the port ships its own schema at
`data/schemas/org.rubygtkproject.Apostrophe.gschema.xml`, compiled by the
flake and exported on `GSETTINGS_SCHEMA_DIR` by the dev shell

13 keys — `color-scheme` (auto/light/dark/sepia), `spellcheck`, `sync-scroll`,
`input-format`, `autohide-headerbar`, `open-file-path`, `stat-default` (enum),
`characters-per-line` (66), `hemingway-mode`, `hemingway-toast-count`,
`preview-mode` (enum), `preview-active`, `bigger-text` — and two enums, `Stat`
(characters/words/sentences/paragraphs/read_time) and `PreviewMode`
(full-width/half-width/half-height/windowed). The port needs its own schema
XML, compiled and on `GSETTINGS_SCHEMA_DIR`, before any of this binds.

### 33. `apostrophe/inhibitor.py` — logout inhibitor

Target `lib/apostrophe/inhibitor.rb` · kind **behaviour** · **exists**

Wraps `Gtk.Application.inhibit` with the reason "Unsaved documents"; engaged
whenever the title shows the unsaved bullet.

### 34. `apostrophe/helpers.py` — shared helpers, including the error dialog

Target `lib/apostrophe/helpers.rb` · kind **behaviour + dialog** ·
**exists**

`show_error(parent, message)` builds an `Adw.MessageDialog` headed "Error" with
one "Close" response — **the app's only generic error state**, used by save,
load and export. Also `user_action` (undo grouping), `get_media_path`,
`exist_executable`, `liststore_from_list`, `get_char_width`,
`pandoc_convert`, and `get_debug_info` (the text the About dialog ships).

### 35. `apostrophe/main_window.py` (`File` dataclass) — the open document

Target `lib/apostrophe/document.rb` · kind **model** · **exists**

Tracks the `Gio.File`, encoding, path, title ("New File" when unsaved) and the
`.md`-stripped name; writes `open-file-path` on every change.

### 36. `data/media/css/gtk/style.css`, `style-dark.css`, `style-sepia.css`

Target `lib/apostrophe/style.rb` (a `Gtk::CssProvider` loading a sibling
stylesheet) · kind **stylesheet** · **exists** — all eight upstream
sheets (three GTK, five web) are vendored under
`lib/apostrophe/resources/css/`

App-defined classes the port must keep for the UI to look like Apostrophe:
`apostrophe-editor`, `apostrophe-window`, `lexikon`, `open-popover`,
`preview_button_left`, `preview_button_right`, `preview-flap`, `preview-stack`,
`quick-preview-popup`, `stats-button`, `themeswitcher`. The sepia sheet is
loaded and unloaded per display by the application class.

### 37. `data/media/icons/*.svg` + `data/apostrophe.gresource.xml`

Target: ship the five symbolic icons
(`preview-layout-{full-width,half-width,half-height,windowed}-symbolic`,
`checkmark-symbolic`) plus `apostrophe_markdown.md` (the tutorial document
opened by the Open Tutorial menu item) and register the icon path. kind
**resources** · **exists** — all five icons, the tutorial document and both
Lua filters are vendored under `lib/apostrophe/resources/`, and the
application registers the icon path on the display's icon theme

### 38. `po/` — translations

33 locales, 42 files in `POTFILES.in`. The port has no catalogue. The flake's
dev shell carries `rxgettext` and a `rake pot` task, so the extraction side
exists; the strings and the catalogues do not.

## Not user-facing, listed for completeness

`apostrophe/__init__.py`, `apostrophe.in`, `config.py.in`, `meson.build`,
`build-aux/`, `scripts/`, `subprojects/` (libsass/sassc, used only to compile
the stylesheets), `tests/` (`test_lint.py`, `test_regex_commonmark.py` —
upstream's only tests, both over `markup_regex`).

## Blockers

1. **No WebKit in the Ruby bundle.** `WebKit2::WebView` and `WebKit::WebView`
   are both absent in the dev shell (`gtk4`/`adwaita` 4.3.9, GTK 4.22.4). The
   preview — §17, §18, §19, §21, the `preview_stack`, the layout switcher and
   the `win.preview` action — has no renderer until a `webkit2-gtk` gem (or a
   typelib + `GObjectIntrospection` loader) is added to `nix/Gemfile` and
   `flake.nix`. This is the single largest parity risk.
2. **No pandoc, no TeX.** `pandoc`, `pdftex` and `xelatex` are all missing from
   the dev shell. Preview conversion (§20), every export path (§26, §27),
   `win.copy_html` and formula rendering (§30) all shell out to them. Adding
   `pandoc` to the flake is cheap; TeXLive is large, and upstream already
   treats its absence as a first-class state (§28), so the port can ship the
   warning path and leave TeX out.
3. **`Adw.Flap` and `Adw.Leaflet` are deprecated upstream of libadwaita 1.4.**
   Both constants do resolve in the bindings, so a literal port is possible,
   but the preview layout machine (§18) is written against `Flap`'s
   orientation/fold-policy/reveal-progress API. Decide deliberately between a
   literal `Adwaita::Flap` port and `Adwaita::OverlaySplitView` (also present)
   before writing §2 and §18 — the two choices change both files.
4. ~~**No GSettings schema yet.**~~ *Resolved:* the port ships
   `data/schemas/org.rubygtkproject.Apostrophe.gschema.xml`; the flake
   compiles it into the package and the dev shell exports
   `GSETTINGS_SCHEMA_DIR=$PWD/data/schemas`.
5. **`Adwaita::Application` / `Adwaita::ApplicationWindow` are broken** per the
   `ruby-gtk` skill, while upstream's window *is* an `Adw.ApplicationWindow`
   with `Adw.ToastOverlay` inside. The existing placeholder uses
   `Gtk::Application` + `Adwaita::ApplicationWindow`; confirm that window class
   actually works before §2 is built on it, and fall back to
   `Gtk::ApplicationWindow` if not.
6. **Worker processes.** Both the stats counter (§16) and the markup parser
   (§11) fork a process and talk over a pipe watched by `GLib.io_add_watch`.
   Ruby has no `multiprocessing`; these want threads plus `GLib::Idle`, which
   changes their shape but not their behaviour.
7. **`telnetlib` DICT client** (§29) has no Ruby counterpart in the bundle, and
   the component is already disabled upstream.
8. **Deprecated dialog classes.** Upstream uses `Adw.MessageDialog`,
   `Adw.AboutWindow`, `Adw.PreferencesWindow` and `Gtk.ShortcutsWindow`; the
   bindings also expose `Adwaita::AlertDialog`, `Adwaita::AboutDialog`,
   `Adwaita::PreferencesDialog` and (per the pilot)
   `Adwaita::ShortcutsDialog`. Pick one convention for the whole port — the
   pilot picked the modern ones — and apply it to §22, §23, §24, §25, §27, §34.
9. **Drivers are thin.** `test/drive_editor.rb` now exists and the dev shell
   advertises `xvfb-run ruby test/drive_*.rb`, but `spec/` still holds only
   `spec_helper.rb`. Every component below still needs its own driver before
   it can be claimed working.
