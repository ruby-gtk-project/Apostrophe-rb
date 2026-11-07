# frozen_string_literal: true

require 'gtk4'
require 'socket'
require 'timeout'
require 'uri'
require_relative 'latex_to_png'
require_relative 'markup_regex'
require_relative 'settings'

module Apostrophe
  # InlinePreview is the Ctrl+click popover: hold Ctrl and click a maths
  # formula, an image link, a footnote reference or a plain word, and a
  # small popover shows a rendered preview of it right there in the editor.
  #
  # Ported from apostrophe/inline_preview.py. The link preview — a
  # 0.3125-zoom WebKit WebView loading the URL — is not ported: upstream's
  # own `get_view_for_link` returns before ever reaching that code (an
  # unconditional `return` sits at the top of the method), so the preview it
  # actually ships for a link, and the one this class ships too, is none.
  #
  # The dictionary lookup (`get_view_for_lexikon`) talks to dict.org over a
  # raw socket rather than through `telnetlib`, which upstream uses and
  # which Ruby has no standard-library counterpart for; the DICT protocol
  # itself (RFC 2229) is plain line-oriented text, so a socket is all
  # `telnetlib` was ever used for here.
  class InlinePreview
    WIDTH = 400
    HEIGHT = 300

    WORD_TYPES = {
      'n'   => 'noun',
      'v'   => 'verb',
      'adj' => 'adjective',
      'adv' => 'adverb',
    }.freeze

    def initialize(text_view)
      @text_view = text_view
      @text_buffer = text_view.text_buffer
      @characters_per_line = Settings.instance.characters_per_line
      @cursor_mark = @text_buffer.create_mark(
        'inline_preview_click',
        @text_buffer.get_iter_at(mark: @text_buffer.get_mark('insert')),
        true,
      )
      @latex_converter = LatexToPng.new
      @preview_fns = {
        MarkupRegex::MATH        => method(:view_for_math),
        MarkupRegex::IMAGE       => method(:view_for_image),
        MarkupRegex::LINK        => method(:view_for_link),
        MarkupRegex::LINK_ALT    => method(:view_for_link),
        MarkupRegex::FOOTNOTE_ID => method(:view_for_footnote),
        /(?<text>\w+)/           => method(:view_for_lexikon),
      }

      text_view.add_controller(click_gesture)
    end

    private

      def click_gesture
        @click_gesture ||= Gtk::GestureClick.new.tap do |gesture|
          gesture.button = 1
          gesture.signal_connect('pressed') { |_g, _n_press, x, y| on_pressed(x, y) }
        end
      end

      def popover
        @popover ||= Gtk::Popover.new.tap do |pop|
          pop.set_parent(@text_view)
          pop.add_css_class('quick-preview-popup')
          pop.autohide = true
        end
      end

      def control_held?
        (click_gesture.current_event_state.to_i & Gdk::ModifierType::CONTROL_MASK.to_i) != 0
      end

      def on_pressed(x, y)
        if control_held?
          buffer_x, buffer_y = @text_view.window_to_buffer_coords(:text, x.to_i, y.to_i)
          iter = @text_view.get_iter_at_location(buffer_x, buffer_y)
          if iter
            @text_buffer.move_mark(@cursor_mark, iter)
            open_popover
          end
        end
      end

      def open_popover
        start_iter = @text_buffer.get_iter_at(mark: @cursor_mark)
        line_offset = start_iter.line_offset
        end_iter = @text_buffer.get_iter_at(mark: @cursor_mark)
        start_iter.set_line_offset(0)
        end_iter.forward_to_line_end
        line_text = @text_buffer.get_text(start_iter, end_iter, false)

        @preview_fns.each do |regex, view_fn|
          found = match_covering(line_text, regex, line_offset)
          if found
            show_view_for(view_fn.call(found))
            break
          end
        end
      end

      def match_covering(text, regex, offset)
        found = nil
        text.scan(regex) do
          match = Regexp.last_match
          if match.begin(0) <= offset && offset <= match.end(0)
            found = match
          end
        end
        found
      end

      def show_view_for(view)
        if view
          popover.child = view
          popover.pointing_to = pointing_rect
          popover.popup
        end
      end

      def pointing_rect
        @text_view.get_iter_location(@text_buffer.get_iter_at(mark: @cursor_mark)).then do |rect|
          x, y = @text_view.buffer_to_window_coords(:text, rect.x, rect.y)
          Gdk::Rectangle.new(
            x,
            y,
            rect.width,
            rect.height,
          )
        end
      end

      def view_for_math(match)
        Gtk::Image.new(file: @latex_converter.generate_png(match[:text]))
      rescue LatexToPng::RenderError => e
        Gtk::Label.new("Formula looks incorrect:\n\n“#{e.message}”")
      rescue Errno::ENOENT
        Gtk::Label.new('Formula preview needs latex and dvipng, which are not installed.')
      end

      def view_for_image(match)
        path = match[:url]
        if path.start_with?('https://', 'http://', 'www.')
          view_for_link(match)
        else
          Gtk::Image.new(pixbuf: image_pixbuf(path))
        end
      rescue StandardError
        nil
      end

      def image_pixbuf(raw_path)
        path = raw_path.delete_prefix('file://')
        unless path.start_with?('/')
          path = File.join(Settings.instance.open_file_path, path)
        end
        GdkPixbuf::Pixbuf.new(file: URI.decode_www_form_component(path), width: WIDTH, height: HEIGHT)
      end

      # Upstream's own `get_view_for_link` returns before building anything;
      # see this file's own header comment for why that is faithfully kept
      # rather than "fixed".
      def view_for_link(_match) = nil

      def view_for_footnote(match)
        footnote_id = match[:id]
        found = find_footnote(footnote_id)
        if found
          text = found[:text].gsub(/\n[\t ]+/, "\n")
        else
          text = 'No matching footnote found'
        end
        Gtk::Label.new(text).tap do |label|
          label.max_width_chars = @characters_per_line
          label.wrap = true
        end
      end

      def find_footnote(id)
        full_text = @text_buffer.get_text(@text_buffer.start_iter, @text_buffer.end_iter, false)
        pos = 0
        result = nil
        while pos
          match = MarkupRegex::FOOTNOTE.match(full_text, pos)
          if match.nil?
            pos = nil
          elsif match[:id] == id
            result = match
            pos = nil
          else
            pos = match.end(0)
          end
        end
        result
      end

      def view_for_lexikon(match)
        term = match[:text]
        entries = DictClient.define_wordnet(term)
        entries && build_lexikon_grid(term, entries)
      rescue StandardError
        nil
      end

      def build_lexikon_grid(term, entries)
        grid = Gtk::Grid.new.tap do |g|
          g.add_css_class('lexikon')
          g.row_spacing = 2
          g.column_spacing = 4
        end
        row = 0
        entries.each do |entry|
          defs = entry.fetch(:defs)
          word_type = WORD_TYPES[entry.fetch(:class)]
          if !defs.empty? && word_type
            row = add_lexikon_entry(
              grid,
              row,
              term,
              word_type,
              defs,
            )
          end
        end
        row.positive? ? grid : nil
      end

      def add_lexikon_entry(grid, row, term, word_type, defs)
        header = Gtk::Label.new("#{term} ~ #{word_type}").tap do |l|
          l.add_css_class('header')
          if row.zero?
            l.add_css_class('first')
          end
          l.halign = :start
          l.justify = :left
        end
        grid.attach(
          header,
          0,
          row,
          3,
          1,
        )

        defs.each do |definition|
          row += 1
          grid.attach(
            lexikon_number_label(definition),
            0,
            row,
            1,
            1,
          )
          grid.attach(
            lexikon_description_label(definition),
            1,
            row,
            1,
            1,
          )
        end
        row + 1
      end

      def lexikon_number_label(definition)
        Gtk::Label.new("#{definition.fetch(:num)}.").tap do |l|
          l.add_css_class('number')
          l.valign = :start
        end
      end

      def lexikon_description_label(definition)
        Gtk::Label.new(Array(definition[:description]).join(' ')).tap do |l|
          l.add_css_class('description')
          l.halign = :start
          l.max_width_chars = @characters_per_line
          l.wrap = true
          l.justify = :fill
        end
      end

      # DictClient speaks just enough of RFC 2229 (the DICT protocol) to send
      # one DEFINE command to dict.dict.org and read the response back, the
      # way upstream's DictAccessor does over telnetlib.
      class DictClient
        HOST = 'dict.dict.org'
        PORT = 2628

        def self.define_wordnet(term)
          response = new.define('wn', term)
          response && parse_wordnet(response)
        end

        # Upstream's `parse_wordnet`: WordNet's DEFINE response is one blob of
        # text per part of speech (n/v/adj/adv), each definition numbered and
        # carrying synonyms/antonyms in brackets and examples in quotes.
        def self.parse_wordnet(response)
          text = response.split("\n").drop(2).join(' ').gsub(/\s+/, ' ').strip
          pieces = text.split(/( adv | adj | n | v |\Aadv |\Aadj |\An |\Av )/)
          entries = []
          current = { defs: [], class: 'none' }
          pieces.each do |piece|
            piece = piece.strip
            if !piece.empty? && WORD_TYPES.key?(piece)
              entries << current
              current = { defs: [], class: piece }
            elsif !piece.empty?
              current[:defs].concat(parse_definitions(piece))
            end
          end
          entries << current
          entries
        end

        def self.parse_definitions(text)
          segments = text.split(/(?: |\A)(\d): /)
          defs = []
          current = nil
          segments.each do |segment|
            if segment.strip =~ /\A\d\z/
              if current && !current[:description].to_a.empty?
                defs << current
              end
              current = { num: segment.strip }
            elsif current
              apply_segment(current, segment)
            end
          end
          if current && !current[:description].to_a.empty?
            defs << current
          end
          defs
        end

        def self.apply_segment(definition, segment)
          segment.scan(/\[(syn|ant): (.+?)\] ?/).each do |kind, body|
            definition[kind == 'syn' ? :syn : :ant] = body.scan(/\{(.*?)\}/).flatten
          end
          trimmed = segment.sub(/\[.+\]/m, '')
          parts = trimmed.split(';').map(&:strip).reject(&:empty?)
          definition[:examples] = parts.select { |part| part.start_with?('"') }
          definition[:description] = parts.reject { |part| part.start_with?('"') }
        end

        def initialize(host: HOST, port: PORT, timeout: 10)
          @host = host
          @port = port
          @timeout = timeout
        end

        # Sends `DEFINE <database> "<word>"` and returns the response's
        # definition text (everything between the "150 ..." header and the
        # final "250 ok" line), or nil when the word was not found.
        def define(database, word)
          socket = TCPSocket.new(@host, @port)
          read_response(socket) # the greeting banner
          if database.nil? || database.empty? || database == 'all'
            d = '*'
          else
            d = database
          end
          w = word.gsub('"', '\\"')
          response = run_command(socket, %(DEFINE #{d} "#{w}"))
          lines = response.lines
          if lines.last.to_s.start_with?('250') && lines.first.to_s.start_with?('1')
            lines[1..-2].join
          end
        ensure
          quit(socket)
        end

        private

          def run_command(socket, command)
            socket.write("#{command}\r\n")
            read_response(socket)
          end

          def read_response(socket)
            buffer = +''
            Timeout.timeout(@timeout) do
              until buffer.match?(/^[2-5][0-9]{2} .*\r\n\z/)
                buffer << socket.readpartial(4096)
              end
            end
            buffer
          end

          def quit(socket)
            socket&.write("QUIT\r\n")
            socket&.close
          rescue IOError, Errno::EPIPE, Errno::ECONNRESET
            nil
          end
      end
  end
end
