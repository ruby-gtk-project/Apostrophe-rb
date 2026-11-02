# frozen_string_literal: true

# Drives the editor headlessly: types markdown into the buffer, checks that the
# markup handler tags it, that the statistics counter counts it, that the list
# and bracket handlers in the buffer fire, that Hemingway mode blocks a delete
# and that the table reflow lines a table up again.
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
  view = application.text_view

  check(failures, 'window is present') { application.window.visible? }
  check(failures, 'editor carries its css class') { view.css_classes.include?('apostrophe-editor') }
  check(failures, 'theme switcher built four swatches') do
    Apostrophe::ThemeSwitcher::SCHEMES.length == 4 &&
      application.theme_switcher.root.first_child.observe_children.n_items == 4
  end

  # Bracket pairing and list continuation come from the buffer's own handlers.
  buffer.text = ''
  buffer.insert_at_cursor('(')
  check(failures, 'bracket pair closes itself') { buffer.text == '()' }

  buffer.text = ''
  buffer.insert_at_cursor('- one')
  buffer.insert_at_cursor("\n")
  check(failures, 'list continues on newline') { buffer.text == "- one\n- " }

  buffer.insert_at_cursor("\t")
  check(failures, 'tab cycles the bullet') { buffer.text == "- one\n    * " }

  # Hemingway mode blocks deletion and reports the attempt.
  buffer.text = 'kept'
  buffer.hemingway_mode = true
  buffer.delete(buffer.start_iter, buffer.end_iter)
  check(failures, 'hemingway mode keeps the text') { buffer.text == 'kept' }
  buffer.hemingway_mode = false

  # The format inserter wraps and unwraps a selection.
  buffer.text = 'word'
  buffer.select_range(buffer.start_iter, buffer.end_iter)
  Apostrophe::FormatInserter.new.insert_bold(view)
  check(failures, 'bold wraps the selection') { buffer.text == '**word**' }

  # The statistics counter also lands on the main loop.
  counted = nil
  counter = Apostrophe::StatsCounter.new { |result| counted = result }
  counter.count("one two three\n\nfour")

  check(failures, 'counting is a pure function too') do
    Apostrophe::StatsCounter.count_text('one two **three**').words == 3
  end

  check(failures, 'table reflow lines the columns up') do
    buffer.text = "| a | bbbb |\n| cccc | d |\n"
    buffer.place_cursor(buffer.get_iter_at(line: 0))
    Apostrophe::FixTable.new(buffer).fix_table
    buffer.text.lines.first.chomp == '+------+------+'
  end

  check(failures, 'debug info names the app and its settings') do
    info = Apostrophe::Helpers.get_debug_info
    info.include?('Apostrophe 0.1.0') && info.include?('color-scheme:')
  end

  check(failures, 'export formats carry their capabilities') do
    Apostrophe::ExportFormat::ALL.length == 17 &&
      Apostrophe::ExportFormat.find_by_name('PDF').has_pages? &&
      Apostrophe::ExportFormat.find_by_name('HTML').html?
  end

  check(failures, 'the current theme has a web stylesheet') do
    File.exist?(Apostrophe::Theme.current.web_css.to_s)
  end

  # The markup handler parses on a worker thread, so this goes last and the
  # result is read back once the main loop has had time to deliver it.
  buffer.text = "# Header\n\nsome **bold** text and `code`\n"
  bold_offset = buffer.text.index('bold')
  tagged = false
  GLib::Timeout.add(1500) do
    tagged = buffer.get_iter_at(offset: bold_offset).tags.map(&:name).compact.include?('bold')
    false
  end

  GLib::Timeout.add(2200) do
    check(failures, 'markup handler tagged the bold run') { tagged }
    check(failures, 'statistics counter delivered a result') { counted && counted.words == 4 }
    counter.stop
    application.app.quit
    false
  end
end

application.run([])

puts(failures.empty? ? "\nall checks passed" : "\n#{failures.length} failed: #{failures.join(', ')}")
exit(failures.empty? ? 0 : 1)
