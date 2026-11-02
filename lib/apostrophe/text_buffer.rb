# frozen_string_literal: true

require 'adwaita'
require_relative 'helpers'
require_relative 'markup_regex'

module Apostrophe
  # TextBuffer is the editor's buffer. Beyond holding the text it takes over
  # three insertions — newline, tab and the opening half of a bracket pair —
  # and it enforces Hemingway mode, in which text can be added but not removed.
  #
  # Ported from apostrophe/text_buffer.py.
  #
  # Upstream overrides the `do_insert_text` and `do_delete_range` virtual
  # methods and calls `Gtk.TextBuffer.do_insert_text` to reach the default
  # behaviour. The Ruby bindings expose no virtual methods on TextBuffer, so
  # the same interception is done by connecting to the `insert-text` and
  # `delete-range` signals and calling `signal_emit_stop` to suppress the
  # default handler. Because there is no way to call that default handler
  # directly, an insertion this class makes itself is wrapped in a passthrough
  # flag that makes the handler stand aside — which is what keeps a plain tab
  # insertion from recursing into itself.
  class TextBuffer < Gtk::TextBuffer
    # The closing half of each pair that is completed automatically.
    PAIRS = {
      '(' => ')',
      '[' => ']',
      '{' => '}',
      '"' => '"',
      "'" => "'",
      '<' => '>',
    }.freeze

    # Tab cycles a bullet forward through this sequence, Shift+Tab back.
    NEXT_BULLET = { '-' => '*', '*' => '+', '+' => '-' }.freeze
    PREVIOUS_BULLET = { '+' => '*', '*' => '-', '-' => '+' }.freeze

    attr_accessor :hemingway_mode

    # `on_attempted_hemingway` stands in for upstream's `attempted-hemingway`
    # action signal: the window uses it to count deletion attempts and offer
    # the explainer dialog. Defining a new GObject signal is not something the
    # Ruby bindings support on a subclass, and nothing outside the window needs
    # to listen, so it is a plain callback.
    def initialize(on_attempted_hemingway: nil)
      super()

      @hemingway_mode = false
      @on_attempted_hemingway = on_attempted_hemingway
      @passthrough = false

      signal_connect('insert-text') { |_buffer, iter, text, _length| on_insert_text(iter, text) }
      signal_connect('delete-range') { |_buffer, _start, _end| on_delete_range }
    end

    # The sentence the cursor sits in, which is the region focus mode leaves at
    # full contrast.
    def current_sentence_bounds
      get_iter_at(mark: get_mark('insert')).then do |cursor_iter|
        start_sentence = cursor_iter.copy
        unless start_sentence.starts_sentence
          start_sentence.backward_sentence_start
        end
        end_sentence = cursor_iter.copy
        unless end_sentence.ends_sentence
          end_sentence.forward_sentence_end
        end
        [start_sentence, end_sentence]
      end
    end

    # The line the cursor sits in. Upstream notes that `backward_line` does not
    # behave as expected and walks back from the end of the line by its offset
    # instead; that is carried over unchanged, which means the bounds are the
    # whole line when the cursor is at its end — the position the newline and
    # tab handlers below are reached from.
    def current_line_bounds
      get_iter_at(mark: get_mark('insert')).then do |cursor_iter|
        end_line = cursor_iter.copy
        unless end_line.ends_line
          end_line.forward_line
        end
        start_line = end_line.copy
        start_line.backward_chars(end_line.line_offset)
        [start_line, end_line]
      end
    end

    # Shift+Tab. On a list line the bullet cycles backwards and one level of
    # indentation comes off; off a list, the trailing tab is removed.
    def unindent
      if @hemingway_mode
        @on_attempted_hemingway&.call
      else
        start_line, end_line = current_line_bounds
        current_line = get_text(start_line, end_line, true)
        match = full_match(MarkupRegex::LIST, current_line)
        if match
          unindent_list(match, start_line, end_line)
        else
          unindent_tab
        end
      end
    end

    private

      def on_insert_text(iter, text)
        if @passthrough
          nil
        elsif @hemingway_mode && has_selection?
          signal_emit_stop('insert-text')
        elsif text == "\n"
          signal_emit_stop('insert-text')
          autocomplete_lists
        elsif text == "\t"
          signal_emit_stop('insert-text')
          indent
        elsif PAIRS.key?(text) && pair_wanted?
          signal_emit_stop('insert-text')
          close_pair(iter, text)
        end
      end

      def on_delete_range
        if @hemingway_mode
          signal_emit_stop('delete-range')
          @on_attempted_hemingway&.call
        end
      end

      # A pair is only completed when what follows the cursor is whitespace or
      # the end of the buffer, so typing a bracket before existing text does
      # not bury that text inside it.
      def pair_wanted?
        get_iter_at(mark: get_mark('insert')).then do |cursor_iter|
          cursor_iter.offset == char_count || cursor_iter.char.to_s.match?(/\s/)
        end
      end

      def close_pair(iter, text)
        insert_unhandled(iter, text + PAIRS.fetch(text))
        get_iter_at(mark: get_mark('insert')).then do |cursor_iter|
          cursor_iter.forward_cursor_positions(-1)
          place_cursor(cursor_iter)
        end
      end

      # Tab. On a bullet line with no text yet the bullet cycles forward and
      # gains a level of indentation; anywhere else a plain tab goes in.
      def indent
        start_line, end_line = current_line_bounds
        current_line = get_text(start_line, end_line, true)
        text = "\t"

        full_match(MarkupRegex::LIST, current_line).then do |match|
          if match && match[:text].nil?
            text = deeper_indent(match) + NEXT_BULLET.fetch(match[:symbol], '-') + ' '
            without_hemingway { delete(start_line, end_line) }
          end
        end

        full_match(MarkupRegex::ORDERED_LIST, current_line).then do |match|
          if match && match[:text].nil?
            text = "#{deeper_indent(match)}1#{match[:delimiter]} "
            without_hemingway { delete(start_line, end_line) }
          end
        end

        insert_unhandled(get_iter_at(mark: get_mark('insert')), text)
      end

      # Newline. A bullet or numbered line with text on it is continued with
      # the next prefix; one with no text ends the list, its prefix deleted.
      def autocomplete_lists
        start_line, end_line = current_line_bounds
        current_line = get_text(start_line, end_line, true)
        text = "\n"

        prefix_match(MarkupRegex::ORDERED_LIST, current_line).then do |match|
          if match
            if match[:text]
              if match[:number]
                text += "#{match[:indent]}#{match[:number].to_i + 1}#{match[:delimiter]} "
              end
            else
              without_hemingway { delete(start_line, end_line) }
            end
          end
        end

        prefix_match(MarkupRegex::LIST, current_line).then do |match|
          if match
            if match[:text]
              text += "#{match[:indent]}#{match[:symbol]} "
            else
              without_hemingway { delete(start_line, end_line) }
            end
          end
        end

        insert_unhandled(get_iter_at(mark: get_mark('insert')), text)
      end

      def unindent_list(match, start_line, end_line)
        indentation = match[:indent].to_s.delete_suffix("\t").delete_suffix('    ')
        text = indentation + PREVIOUS_BULLET.fetch(match[:symbol], '+') + ' '
        if match[:text]
          text += match[:text]
        end

        delete(start_line, end_line)
        insert_unhandled(get_iter_at(mark: get_mark('insert')), text)
      end

      # Upstream removes the tab at the very end of the buffer rather than the
      # one before the cursor, and that is what is ported here: Shift+Tab off a
      # list is only reached while typing at the end of the document.
      def unindent_tab
        pen_iter = end_iter
        pen_iter.backward_char
        if pen_iter.char.to_s == "\t"
          Helpers.user_action(self) { delete(pen_iter, end_iter) }
        end
      end

      # A tab-indented line is replaced by a single tab, a space-indented one
      # gains four spaces — upstream's rule, carried over as written.
      def deeper_indent(match)
        if match[:indent].to_s.include?("\t")
          "\t"
        else
          "    #{match[:indent]}"
        end
      end

      # Python's `re.fullmatch`: the pattern has to account for the whole
      # string, not just a run inside it.
      def full_match(regex, string)
        regex.match(string).then do |match|
          if match && match[0] == string
            match
          end
        end
      end

      # Python's `re.match`: anchored at the start of the string. Both list
      # patterns can also start at a newline, so a match that begins further in
      # is not one `re.match` would have found.
      def prefix_match(regex, string)
        regex.match(string).then do |match|
          if match && match.begin(0).zero?
            match
          end
        end
      end

      # Hemingway mode blocks every delete-range, including the ones this class
      # makes while rewriting a list prefix, so it comes off for the duration
      # and goes back to whatever it was.
      def without_hemingway
        cached = @hemingway_mode
        @hemingway_mode = false
        begin
          yield
        ensure
          @hemingway_mode = cached
        end
      end

      # Inserts without the interception above, which is how this class reaches
      # the behaviour upstream gets by calling `Gtk.TextBuffer.do_insert_text`.
      def insert_unhandled(position, text)
        @passthrough = true
        begin
          insert(position, text)
        ensure
          @passthrough = false
        end
      end
  end
end
