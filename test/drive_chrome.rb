# frozen_string_literal: true

# Drives the editor's chrome headlessly: the statistics button's popover and
# label, the search-and-replace bar's find/replace behaviour, and that the
# shortcuts, about and Hemingway Mode dialogs all build and present.
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'apostrophe'

failures = []

def check(failures, name)
  result = yield
  if result
    puts "ok   #{name}"
  else
    puts "FAIL #{name}"
    failures << name
  end
rescue StandardError => e
  puts "FAIL #{name}: #{e.class}: #{e.message}"
  failures << name
end

application = Apostrophe::Application.new
application.build

application.app.signal_connect('activate') do
  buffer = application.text_buffer

  check(failures, 'stats button got a popover') { !application.stats_button.popover.nil? }
  check(failures, 'stats button shows a default stat') { application.stats_button.label.include?('Words') }

  check(failures, 'search bar toggles on') do
    application.send(:toggle_search)
    application.search_bar.search_mode_enabled == true
  end

  buffer.text = 'foo bar foo baz foo'
  check(failures, 'search bar finds matches') do
    application.search_bar.send(:search_entry).text = 'foo'
    application.search_bar.send(:search)
    application.search_bar.instance_variable_get(:@matches).length == 3
  end

  check(failures, 'search bar replace-all works') do
    application.search_bar.instance_variable_set(:@active, 0)
    application.search_bar.send(:replace_entry).text = 'qux'
    application.search_bar.send(:replace_all)
    buffer.text == 'qux bar qux baz qux'
  end

  check(failures, 'search bar toggles off and clears highlight') do
    application.send(:toggle_search)
    application.search_bar.search_mode_enabled == false
  end

  check(failures, 'shortcuts window builds') do
    application.shortcuts_window.present(application.window)
    true
  end

  check(failures, 'about dialog builds') do
    application.about_dialog.present(application.window)
    true
  end

  check(failures, 'hemingway dialog builds') do
    application.hemingway_dialog.present(application.window)
    true
  end

  buffer.text = 'one two three four'
  GLib::Timeout.add(800) do
    check(failures, 'stats button label updates') { application.stats_button.label.include?('4') }
    application.app.quit
    false
  end
end

application.run([])

puts(failures.empty? ? "\nall checks passed" : "\n#{failures.length} failed: #{failures.join(', ')}")
exit(failures.empty? ? 0 : 1)
