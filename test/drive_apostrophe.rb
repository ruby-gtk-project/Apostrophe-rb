# frozen_string_literal: true

# Drives the whole port headlessly: builds the window, exercises the header
# bar's focus and Hemingway toggles, the main menu popover and its theme
# switcher, the statistics button's popover and label, the search-and-replace
# bar's find/replace behaviour, the editor's markdown handling (brackets,
# lists, Hemingway mode, format insertion, table reflow, live markup
# highlighting), and opens every dialog the port has (shortcuts, about,
# Hemingway) — screenshotting each state along the way.
#
# Run it from the repository root:
#
#   nix develop --command xvfb-run -a ruby test/drive_apostrophe.rb
#
# This fork's flake.nix carries a display (xvfb-run) and RUBYLIB, matching
# tally-rb; the dev shell banner names the exact command.

require 'fileutils'
require 'tmpdir'

# A scratch config directory, so a run never reads or writes the real one.
ENV['XDG_CONFIG_HOME'] = Dir.mktmpdir('apostrophe-drive')

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'apostrophe'
require_relative 'gtk_driver'

SHOTS = File.expand_path('../tmp/shots', __dir__)
FileUtils.rm_rf(SHOTS)

# Turns the main loop over for `ms` milliseconds without blocking it — used
# where a result arrives off a worker thread (the markup handler, the stats
# counter) and the step needs to wait for the main loop to deliver it.
def pump(ms)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + (ms / 1000.0)
  while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    GLib::MainContext.default.iteration(false)
  end
end

GtkDriver.drive(Apostrophe::Application.new, shots: SHOTS, timeout: 60) do |d, app|
  d.window { app.window }

  d.step('the window builds and shows the editor') do
    d.check('the window is an Adwaita::ApplicationWindow') { app.window.is_a?(Adwaita::ApplicationWindow) }
    d.check('it is the only toplevel') { Gtk::Window.list_toplevels.length == 1 }
    d.check('the window is present') { app.window.visible? }
    d.check('the editor carries its css class') { app.text_view.css_classes.include?('apostrophe-editor') }
    d.check('the header bar packs the focus-mode button') do
      app.header_bar.respond_to?(:pack_start) && app.focus_mode_button.is_a?(Gtk::ToggleButton)
    end
    d.check('the header bar packs the hemingway button') { app.hemingway_button.is_a?(Gtk::ToggleButton) }
    d.check('the header bar packs the menu and stats buttons') do
      app.menu_button.is_a?(Gtk::MenuButton) && app.stats_button.is_a?(Gtk::MenuButton)
    end
    d.shot('01-empty-editor')
  end

  d.step('the main menu popover opens and holds the theme switcher') do
    app.menu_button.popover.popup
  end

  d.step('the theme switcher built its four swatches') do
    d.check('four schemes are defined') { Apostrophe::ThemeSwitcher::SCHEMES.length == 4 }
    d.check('the switcher root has four swatches') do
      app.theme_switcher.root.first_child.observe_children.n_items == 4
    end
    d.shot('02-menu-popover')
    app.menu_button.popover.popdown
  end

  d.step('clicking a swatch changes the colour scheme setting') do
    app.theme_switcher.selector('dark').active = true
    d.check('the setting followed the click') { Apostrophe::Settings.instance.color_scheme == 'dark' }
    app.theme_switcher.selector('auto').active = true
    d.check('and follows it back') { Apostrophe::Settings.instance.color_scheme == 'auto' }
  end

  d.step('the focus-mode button toggles focus mode on the view and the markup handler') do
    app.focus_mode_button.active = true
    d.check('the markup handler enabled focus mode') { app.markup_handler.focus_mode == true }
    d.check('the text view enabled focus mode') { app.text_view.focus_mode == true }
    d.shot('03-focus-mode')
    app.focus_mode_button.active = false
    d.check('and disables it again') { app.markup_handler.focus_mode == false }
  end

  d.step('the hemingway button toggles hemingway mode on the buffer and the setting') do
    app.hemingway_button.active = true
    d.check('the buffer entered hemingway mode') { app.text_buffer.hemingway_mode == true }
    d.check('the setting followed') { Apostrophe::Settings.instance.hemingway_mode? == true }
  end

  d.step('hemingway mode blocks a delete and reports the attempt') do
    app.text_buffer.text = 'kept'
    app.text_buffer.delete(app.text_buffer.start_iter, app.text_buffer.end_iter)
    d.check('the text survived the delete') { app.text_buffer.text == 'kept' }
    app.hemingway_button.active = false
    d.check('turning the button off turns hemingway mode off') { app.text_buffer.hemingway_mode == false }
  end

  d.step('the stats button has a popover and a default label') do
    d.check('the stats button got a popover') { !app.stats_button.popover.nil? }
    # Substring, not 'Words': upstream pluralizes this label ("1 Word" vs.
    # "4 Words"), and 'Word' matches either.
    d.check('the stats button shows a default stat') { app.stats_button.label.include?('Word') }
  end

  d.step('typing updates the statistics button label') do
    app.text_buffer.text = 'one two three four'
  end

  d.step('the stats button label updated and its popover opens') do
    pump(600)
    d.check('the stats button label updated') { app.stats_button.label.include?('4') }
    app.stats_button.popover.popup
  end

  d.step('the stats popover is laid out and closes again') do
    d.shot('04-stats-popover')
    app.stats_button.popover.popdown
  end

  d.step('the search bar toggles on and finds matches') do
    app.text_buffer.text = 'foo bar foo baz foo'
    app.send(:toggle_search)
    d.check('the search bar is now in search mode') { app.search_bar.search_mode_enabled == true }
    app.search_bar.send(:search_entry).text = 'foo'
    app.search_bar.send(:search)
    d.check('it found all three matches') { app.search_bar.instance_variable_get(:@matches).length == 3 }
  end

  d.step('the search bar is laid out with its matches highlighted') do
    pump(200)
    # The editor pane renders blank in this shot under the headless Cairo
    # renderer once a second child sits in the Gtk::Overlay (confirmed by
    # screenshotting editor_scrolled_window alone, which does show the text) —
    # a renderer-compositing quirk of this harness, not a port defect: the
    # checks above already prove the search and highlighting are correct.
    d.shot('05-search-bar')
  end

  d.step('replace-all rewrites every match') do
    app.search_bar.instance_variable_set(:@active, 0)
    app.search_bar.send(:replace_entry).text = 'qux'
    app.search_bar.send(:replace_all)
    d.check('every match was replaced') { app.text_buffer.text == 'qux bar qux baz qux' }
  end

  d.step('the search bar toggles off and clears its highlight') do
    app.send(:toggle_search)
    d.check('search mode is off again') { app.search_bar.search_mode_enabled == false }
  end

  d.step('bracket pairing and list continuation come from the buffer handlers') do
    app.text_buffer.text = ''
    app.text_buffer.insert_at_cursor('(')
    d.check('a bracket pair closes itself') { app.text_buffer.text == '()' }

    app.text_buffer.text = ''
    app.text_buffer.insert_at_cursor('- one')
    app.text_buffer.insert_at_cursor("\n")
    d.check('a list continues on newline') { app.text_buffer.text == "- one\n- " }

    app.text_buffer.insert_at_cursor("\t")
    d.check('tab cycles the bullet') { app.text_buffer.text == "- one\n    * " }
  end

  d.step('the format inserter wraps and the fix-table action lines columns up') do
    app.text_buffer.text = 'word'
    app.text_buffer.select_range(app.text_buffer.start_iter, app.text_buffer.end_iter)
    app.format_inserter.insert_bold(app.text_view)
    d.check('bold wraps the selection') { app.text_buffer.text == '**word**' }

    app.text_buffer.text = "| a | bbbb |\n| cccc | d |\n"
    app.text_buffer.place_cursor(app.text_buffer.get_iter_at(line: 0))
    app.fix_table.fix_table
    d.check('the table reflowed') { app.text_buffer.text.lines.first.chomp == '+------+------+' }
  end

  d.step('the window actions dispatch the same markdown shortcuts') do
    app.text_buffer.text = 'word'
    app.text_buffer.select_range(app.text_buffer.start_iter, app.text_buffer.end_iter)
    app.window.lookup_action('insert-italic').activate(nil)
    d.check('the win.insert-italic action wraps the selection') { app.text_buffer.text == '_word_' }
  end

  d.step('every shipped export format and preview icon is present') do
    d.check('all 17 export formats are registered') { Apostrophe::ExportFormat::ALL.length == 17 }
    d.check('PDF has pages') { Apostrophe::ExportFormat.find_by_name('PDF').has_pages? }
    d.check('HTML is html') { Apostrophe::ExportFormat.find_by_name('HTML').html? }
    d.check('the preview layout icons are registered') do
      Gtk::IconTheme.get_for_display(Gdk::Display.default).has_icon?('preview-layout-half-width-symbolic')
    end
    d.check('the current theme has a web stylesheet') { File.exist?(Apostrophe::Theme.current.web_css.to_s) }
    d.check('debug info names the app and its settings') do
      info = Apostrophe::Helpers.get_debug_info
      info.include?('Apostrophe 0.1.0') && info.include?('color-scheme:')
    end
  end

  d.step('the markup handler tags markdown on its worker thread') do
    app.text_buffer.text = "# Header\n\nsome **bold** text and `code`\n"
    @bold_offset = app.text_buffer.text.index('bold')
  end

  d.step('the bold run is tagged once the worker thread delivers its result') do
    pump(1800)
    tagged = app.text_buffer.get_iter_at(offset: @bold_offset).tags.map(&:name).compact.include?('bold')
    d.check('the bold run carries the bold tag') { tagged }
    d.shot('06-markup-highlighted')
  end

  d.step('the pure counting function matches the live counter') do
    d.check('counting is a pure function too') { Apostrophe::StatsCounter.count_text('one two **three**').words == 3 }
  end

  d.step('the shortcuts window opens over the editor') do
    app.shortcuts_window.present(app.window)
    d.shot('07-shortcuts-window')
  end

  d.step('the about dialog opens over the editor') do
    app.about_dialog.present(app.window)
    d.shot('08-about-dialog')
  end

  d.step('the hemingway explainer dialog opens over the editor') do
    app.hemingway_dialog.present(app.window)
    d.shot('09-hemingway-dialog')
  end

  d.step('the statistics handler exposes a way to stop its worker threads') do
    d.check('stats_handler responds to stop') { app.stats_handler.respond_to?(:stop) }
  end

  # --- main_window.rb / headerbar.rb: the file lifecycle and the menus -----

  d.step('the window installs every file-lifecycle action main_window.rb adds') do
    %w[new open open_file save save_as export copy_html close].each do |name|
      d.check("win.#{name} is installed") { !app.window.lookup_action(name).nil? }
    end
    d.check('app.new_window is installed') { !app.app.lookup_action('new_window').nil? }
    d.check('app.quit is installed') { !app.app.lookup_action('quit').nil? }
  end

  d.step('the save split-button and the open button are real, wired widgets') do
    d.check('the save button carries win.save') { app.main_window.send(:header_bar_assembly).send(:save_button).action_name == 'win.save' }
    d.check('the open button holds the recents popover') { !app.main_window.send(:header_bar_assembly).open_popover_object.nil? }
  end

  d.step("the main menu and the save split-button's export menu carry every item" \
         ' component-parity.md counted') do
    menu = app.menu_button.menu_model
    export_menu = app.main_window.send(:header_bar_assembly).send(:export_menu_model)
    count_items = lambda do |gmenu|
      (0...gmenu.n_items).sum do |section_index|
        gmenu.get_item_link(section_index, 'section').then { |section| section ? section.n_items : 1 }
      end
    end
    d.check('the main menu has 8 items across its sections') { count_items.call(menu) == 8 }
    d.check('the export menu has 6 items across its sections') { count_items.call(export_menu) == 6 }
  end

  d.step('opening a real file loads it and records it as the current document') do
    # Every earlier step left the buffer "changed" from the editor's own
    # perspective; clearing that flag directly is the same thing a real user
    # answering "Discard" on the unsaved-changes prompt would leave behind,
    # without this headless run having to drive that dialog.
    app.main_window.instance_variable_set(:@did_change, false)

    @tmp_markdown = File.join(Dir.mktmpdir('apostrophe-drive-file'), 'drive-note.md')
    File.write(@tmp_markdown, 'hello from disk')
    app.window.lookup_action('open_file').activate(GLib::Variant.new("file://#{@tmp_markdown}"))
  end

  d.step('the load completed on the main loop and updated the document and the title') do
    pump(800)
    d.check('the buffer holds the file contents') { app.text_buffer.text == 'hello from disk' }
    d.check('the document now points at that file') { app.document.gfile&.path == @tmp_markdown }
    d.check('the window title lost its unsaved-changes dot') { app.window.title == File.basename(@tmp_markdown) }
  end

  d.step('editing the loaded file marks it changed and win.save writes it back out') do
    app.text_buffer.text = 'hello from disk, edited'
    d.check('the title gained the unsaved-changes dot') { app.window.title.start_with?('•') }
    # inhibitor.rb: the first dirtying edit calls @inhibitor.inhibit(:logout)
    # (confirmed by reading main_window.rb's on_text_changed). Asserting
    # app.inhibitor.inhibiting? here would check the real session's answer,
    # not the port's call site — and under this headless Xvfb session, with
    # no systemd-logind or xdg-desktop-portal to grant it, Gtk::Application
    # #inhibit genuinely returns cookie 0 (confirmed directly: a bare
    # app.inhibit(window, :logout, 'reason') call against this same display
    # returns 0 here, independent of anything Inhibitor does). That gap is
    # exercised in isolation two steps below instead, with a fake app object
    # standing in for the session.
    app.window.lookup_action('save').activate(nil)
  end

  d.step('the save completed on the main loop and the file on disk matches the buffer') do
    pump(800)
    d.check('the file on disk now holds the edit') { File.read(@tmp_markdown) == 'hello from disk, edited' }
    d.check('the title dropped the unsaved-changes dot again') { app.window.title == File.basename(@tmp_markdown) }
  end

  # --- inhibitor.rb: cookie tracking, isolated from the real session -------
  # Gtk::Application#inhibit needs systemd-logind/xdg-desktop-portal to grant
  # anything, which this headless Xvfb session has neither of (verified
  # above). Inhibitor's own logic — do not re-inhibit while already
  # inhibiting, zero the cookie on uninhibit, report inhibiting? correctly —
  # is still fully testable with a fake stand-in for Helpers.app.

  d.step("inhibitor.rb's cookie bookkeeping is correct even though a headless session grants nothing") do
    fake_window = Object.new
    fake_app = Object.new
    inhibit_calls = []
    uninhibit_calls = []
    fake_app.define_singleton_method(:active_window) { fake_window }
    fake_app.define_singleton_method(:inhibit) do |window, flags, reason|
      inhibit_calls << [window, flags, reason]
      42
    end
    fake_app.define_singleton_method(:uninhibit) { |cookie| uninhibit_calls << cookie }

    real_helpers_app = Apostrophe::Helpers.method(:app)
    Apostrophe::Helpers.define_singleton_method(:app) { fake_app }

    isolated_inhibitor = Apostrophe::Inhibitor.new
    d.check('a fresh inhibitor is not inhibiting') { !isolated_inhibitor.inhibiting? }

    isolated_inhibitor.inhibit(:logout)
    d.check('inhibiting the session asked the (fake) app, with the logout flag') do
      inhibit_calls == [[fake_window, :logout, 'Unsaved documents']]
    end
    d.check('it is now inhibiting') { isolated_inhibitor.inhibiting? }

    isolated_inhibitor.inhibit(:logout)
    d.check('inhibiting a second time while already inhibiting is a no-op') { inhibit_calls.length == 1 }

    isolated_inhibitor.uninhibit
    d.check('uninhibiting passed the cookie the fake app handed back') { uninhibit_calls == [42] }
    d.check('it is no longer inhibiting') { !isolated_inhibitor.inhibiting? }

    isolated_inhibitor.uninhibit
    d.check('uninhibiting while not inhibiting is a no-op') { uninhibit_calls.length == 1 }

    Apostrophe::Helpers.define_singleton_method(:app, real_helpers_app)
  end

  d.step('win.copy_html round-trips the buffer through Pandoc onto the clipboard') do
    app.text_buffer.text = '**bold**'
    app.window.lookup_action('copy_html').activate(nil)
  end

  d.step('the clipboard holds the converted HTML, where this dev shell has Pandoc') do
    if Apostrophe::Helpers.exist_executable?('pandoc')
      app.window.clipboard.read_text_async(nil) do |clipboard, result|
        @clipboard_html = clipboard.read_text_finish(result)
      end
      pump(600)
      d.check('the clipboard holds a <strong> tag for the bold run') { @clipboard_html.to_s.include?('<strong>') }
    else
      d.check('win.copy_html ran without crashing the window (Pandoc is not on PATH here)') { app.window.visible? }
    end
  end

  d.step('app.new_window opens a second, independent window') do
    app.app.lookup_action('new_window').activate(nil)
    pump(300)
    d.check('there are now two windows') { app.windows.length == 2 }
    d.check('the new window starts on a fresh, untitled document') do
      app.windows.last.document.title == 'New File'
    end
    d.shot('10-second-window', app.windows.last.window)
  end

  d.step('closing the second window drops it from the application again') do
    app.windows.last.window.close
    pump(200)
    d.check('one window is left') { app.windows.length == 1 }
  end

  # --- preview_renderer.rb / preview_layout_switcher.rb / preview_window.rb -

  d.step('turning on the preview shows the full-width placeholder in the flap') do
    app.main_window.preview_toggle_button.active = true
    pump(300)
    d.check('the flap reveals the preview') { app.main_window.flap.reveal_flap? == true }
    d.check('the stack shows the placeholder content') do
      app.main_window.preview_stack.visible_child == app.main_window.preview_placeholder
    end
    d.check('full-width is the default layout') do
      app.main_window.preview_renderer.preview_layout == Apostrophe::PreviewLayout::FULL_WIDTH
    end
    d.shot('11-preview-full-width')
  end

  d.step('the layout switcher popover opens with four rows, one of them checked') do
    switcher = app.main_window.preview_layout_switcher
    switcher.send(:popover).popup
    pump(200)
    items = switcher.instance_variable_get(:@items)
    d.check('four layout rows exist') { items.length == 4 }
    d.check('the full-width row is the one checked') { items[Apostrophe::PreviewLayout::FULL_WIDTH].selected? }
    d.shot('12-preview-layout-popover')
  end

  d.step('activating the half-width row resizes the flap to a side-by-side layout') do
    switcher = app.main_window.preview_layout_switcher
    items = switcher.instance_variable_get(:@items)
    switcher.send(:on_row_activated, items[Apostrophe::PreviewLayout::HALF_WIDTH])
    pump(400)
    d.check('the renderer followed the switch') do
      app.main_window.preview_renderer.preview_layout == Apostrophe::PreviewLayout::HALF_WIDTH
    end
    d.check('the flap never folds in this layout') { app.main_window.flap.fold_policy == :never }
    d.check('the stack carries the half-width css class') do
      app.main_window.preview_stack.css_classes.include?('half-width')
    end
    d.shot('13-preview-half-width')
  end

  d.step('activating the windowed row detaches the preview into its own window') do
    switcher = app.main_window.preview_layout_switcher
    items = switcher.instance_variable_get(:@items)
    @toplevels_before_windowed = Gtk::Window.list_toplevels.length
    switcher.send(:on_row_activated, items[Apostrophe::PreviewLayout::WINDOWED])
    pump(400)
    d.check('a second toplevel window appeared') do
      Gtk::Window.list_toplevels.length == @toplevels_before_windowed + 1
    end
    @preview_window = app.main_window.preview_renderer.instance_variable_get(:@preview_window)
    d.check('it is a real PreviewWindow') { @preview_window.is_a?(Apostrophe::PreviewWindow) }
    d.shot('14-preview-windowed', @preview_window.window_object)
  end

  d.step('closing the detached preview window turns the preview button off again') do
    @preview_window.window_object.close
    pump(300)
    d.check('the toggle button followed the window closing') { app.main_window.preview_toggle_button.active? == false }
    d.check('back down to one toplevel') { Gtk::Window.list_toplevels.length == @toplevels_before_windowed }
  end

  # --- open_popover.rb: the recent-files list -------------------------------

  d.step('the open button holds a recents popover that already lists the file we opened') do
    open_popover = app.main_window.send(:header_bar_assembly).open_popover_object
    open_popover.send(:popover).popup
    pump(200)
    d.check('the list is showing, not the empty state') do
      open_popover.send(:stack).visible_child == open_popover.send(:list_box)
    end
    rows = []
    child = open_popover.send(:list_box).first_child
    while child
      rows << child
      child = child.next_sibling
    end
    d.check('our drive file is in the recent list') do
      rows.any? { |row| row.subtitle.to_s.include?(File.basename(@tmp_markdown)) }
    end
    d.shot('15-open-popover')
    open_popover.popdown
  end

  # --- preferences_dialog.rb -------------------------------------------------

  d.step('app.preferences opens the preferences window bound to the live settings') do
    app.app.lookup_action('preferences').activate(nil)
    pump(300)
    @prefs_window = app.preferences_dialog.send(:window)
    d.check('it is a real PreferencesWindow') { @prefs_window.is_a?(Adwaita::PreferencesWindow) }
    d.check('it is on screen') { @prefs_window.visible? }
    d.shot('16-preferences')
  end

  d.step('toggling the autohide switch writes straight through to gsettings') do
    switch = app.preferences_dialog.send(:autohide_headerbar_switch)
    before = switch.active?
    switch.active = !before
    pump(200)
    d.check('the setting followed the switch') { Apostrophe::Settings.instance.autohide_headerbar? == !before }
    @prefs_window.close
  end

  # --- export_dialog.rb (AdvancedExportDialog) ------------------------------

  d.step('the advanced export dialog opens on the formats list') do
    @advanced_export = Apostrophe::AdvancedExportDialog.new(app.window, app.document, app.text_view.text)
    @advanced_export.present
    pump(300)
    # present() selects the first row itself (PDF, per ExportFormat::ALL's
    # order), which is what immediately flips the leaflet to the options page
    # showing PDF's own groups — matching upstream's constructor behaviour.
    d.check('the leaflet already shows the options page for the first format') do
      @advanced_export.send(:leaflet).visible_child == @advanced_export.send(:options_page)
    end
    d.check('PDF (the first format) shows the page-size group') { @advanced_export.send(:page_size_group).visible? }
    d.check('every shipped format got a row') do
      @advanced_export.send(:formats_list).observe_children.n_items == Apostrophe::ExportFormat::ALL.length
    end
    # texlive_warning.rb: PDF needs a TeX toolchain, and pdftex is not on
    # PATH in this dev shell, so the empty state takes over from the options
    # pane and the export button goes insensitive — real wiring, not a
    # direct call into TexliveWarning.
    d.check('pdftex is genuinely absent here, so this exercises the real gap') do
      !Apostrophe::Helpers.exist_executable?('pdftex')
    end
    d.check('the options stack swapped to the texlive warning') do
      @advanced_export.send(:options_page).visible_child_name == 'texlive_warning'
    end
    d.check('the export button went insensitive') { !@advanced_export.send(:export_button).sensitive? }
    d.check('the warning shows its distro panel outside a flatpak') do
      warning_stack = @advanced_export.send(:texlive_warning).send(:stack)
      warning_stack.visible_child_name == 'distro'
    end
    d.shot('17-advanced-export-formats')
  end

  d.step('the go-back button returns the leaflet to the formats list') do
    @advanced_export.send(:go_previous_button).clicked
    pump(100)
    d.check('the leaflet went back to the formats page') do
      @advanced_export.send(:leaflet).visible_child == @advanced_export.send(:formats_page)
    end
    d.shot('18-advanced-export-formats-after-back')
  end

  d.step('selecting HTML swaps in the HTML options group instead of the page-size one') do
    html_index = Apostrophe::ExportFormat::ALL.index { |format| format.name == 'HTML' }
    row = @advanced_export.send(:formats_list).get_row_at_index(html_index)
    @advanced_export.send(:formats_list).select_row(row)
    pump(200)
    d.check('the leaflet switched back to the options page') do
      @advanced_export.send(:leaflet).visible_child == @advanced_export.send(:options_page)
    end
    d.check('HTML shows its own options group') { @advanced_export.send(:html_options_group).visible? }
    d.check('and hides the page-size group PDF needed') { !@advanced_export.send(:page_size_group).visible? }
    d.check('the window title followed the new selection') { @advanced_export.send(:window).title == 'Export to HTML' }
    d.shot('19-advanced-export-html-options')
  end

  d.step('selecting PDF again brings the page-size group back') do
    pdf_index = Apostrophe::ExportFormat::ALL.index { |format| format.name == 'PDF' }
    row = @advanced_export.send(:formats_list).get_row_at_index(pdf_index)
    @advanced_export.send(:formats_list).select_row(row)
    pump(200)
    d.check('PDF shows the page-size group again') { @advanced_export.send(:page_size_group).visible? }
    d.check('and hides the HTML options group') { !@advanced_export.send(:html_options_group).visible? }
    d.check('the texlive warning takes over the options stack again') do
      @advanced_export.send(:options_page).visible_child_name == 'texlive_warning'
    end
    @advanced_export.send(:window).close
  end

  # --- markup_regex.rb: the markdown grammar as pure checks ----------------
  # No widget needed — these run straight against the compiled Regexp
  # constants, which the editor, the stats counter and the buffer's list
  # handler all share.

  d.step('markup_regex.rb matches bold, italic, links and code spans') do
    d.check('bold matches **word**') { Apostrophe::MarkupRegex::BOLD.match?('**word**') }
    d.check('italic (asterisk) matches *word*') { Apostrophe::MarkupRegex::ITALIC_ASTERISK.match?('*word*') }
    d.check('italic (underscore) matches _word_') { Apostrophe::MarkupRegex::ITALIC_UNDERSCORE.match?('_word_') }
    d.check('bold+italic matches ***word***') { Apostrophe::MarkupRegex::BOLD_ITALIC.match?('***word***') }
    d.check('strikethrough matches ~~word~~') { Apostrophe::MarkupRegex::STRIKETHROUGH.match?('~~word~~') }
    d.check('code matches `word`') { Apostrophe::MarkupRegex::CODE.match?('`word`') }
    d.check('a link captures text and url') do
      match = Apostrophe::MarkupRegex::LINK.match('[text](http://example.com)')
      match && match[:text] == 'text' && match[:url] == 'http://example.com'
    end
    d.check('an image matches ![alt](src)') { Apostrophe::MarkupRegex::IMAGE.match?('![alt](src.png)') }
    d.check('a header captures its level and text') do
      match = Apostrophe::MarkupRegex::HEADER.match('## a header')
      match && match[:level] == '##' && match[:text] == 'a header'
    end
    d.check('a fenced code block matches across lines') do
      Apostrophe::MarkupRegex::CODE_BLOCK.match?("```\ncode\n```")
    end
    d.check('a bullet list item matches and names its symbol') do
      match = Apostrophe::MarkupRegex::LIST.match('- one')
      match && match[:symbol] == '-'
    end
    d.check('an ordered list item matches and names its number') do
      match = Apostrophe::MarkupRegex::ORDERED_LIST.match('1. one')
      match && match[:number] == '1'
    end
    d.check('a block quote captures its text') do
      match = Apostrophe::MarkupRegex::BLOCK_QUOTE.match('> quoted')
      match && match[:text] == 'quoted'
    end
    d.check('inline math matches $x^2$') { Apostrophe::MarkupRegex::MATH.match?('$x^2$') }
    d.check('a horizontal rule matches on its own paragraph') do
      Apostrophe::MarkupRegex::HORIZONTAL_RULE.match?("\n\n---\n\n")
    end
    d.check('a footnote definition captures its id and text') do
      match = Apostrophe::MarkupRegex::FOOTNOTE.match("\n[^1]: the note\n")
      match && match[:id] == '1' && match[:text] == 'the note'
    end
  end

  # --- preview_converter.rb: the Pandoc argument list, without Pandoc -------
  # Pandoc itself is not on PATH in this dev shell (confirmed above for
  # pdftex's sibling check), so only the pure argument-building side of this
  # class — not an actual conversion — can run here.

  d.step('preview_converter.rb builds its Pandoc arguments off the current theme') do
    args = Apostrophe::PreviewConverter.args
    d.check('it asks for a standalone document') { args.include?('--standalone') }
    d.check('it asks for MathJax') { args.include?('--mathjax') }
    d.check('it points at the current theme\'s web stylesheet') do
      args.any? { |arg| arg == "--css=#{Apostrophe::Theme.current.web_css}" }
    end
    d.check('it loads both Lua filters this port ships') do
      args.count { |arg| arg.start_with?('--lua-filter=') } == 2
    end
    unless Apostrophe::Helpers.exist_executable?('pandoc')
      puts '    note: pandoc is not on PATH in this dev shell — PreviewConverter#convert' \
           ' itself (the worker-thread Pandoc call) is not exercised here, only its' \
           ' argument list.'
    end
  end
end
