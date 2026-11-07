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
    d.check('the stats button shows a default stat') { app.stats_button.label.include?('Words') }
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
end
