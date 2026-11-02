# frozen_string_literal: true

require 'adwaita'
require_relative 'helpers'
require_relative 'markup_regex'

module Apostrophe
  # MarkupHandler highlights the markdown in the editor as it is typed: italic,
  # bold, strikethrough, inline code and maths get their own text tags, links
  # and images have their syntax greyed out, a horizontal rule is centred,
  # block quotes and headers are pulled into the margin, and fenced code blocks
  # get a shaded paragraph. In focus mode everything outside the current
  # sentence is greyed as well.
  #
  # Ported from apostrophe/text_view_markup_handler.py.
  #
  # Upstream parses in a worker *process* over a pipe, watched with
  # `GLib.io_add_watch`. The port uses a worker *thread* and a queue: Ruby's
  # threads are preemptible enough for this (the parse is pure regex over a
  # string, with no GTK call in it) and the result is handed back to the main
  # loop with `GLib::Idle.add`, which is the thread-safe way to touch widgets.
  # The same "one parse in flight, re-apply when it lands" protocol upstream
  # uses is kept, so a burst of keystrokes cannot queue up a parse per key.
  class MarkupHandler
    TAG_NAME_ITALIC = 'italic'
    TAG_NAME_BOLD = 'bold'
    TAG_NAME_BOLD_ITALIC = 'bold_italic'
    TAG_NAME_STRIKETHROUGH = 'strikethrough'
    TAG_NAME_CENTER = 'center'
    TAG_NAME_WRAP_NONE = 'wrap_none'
    TAG_NAME_PLAIN_TEXT = 'plain_text'
    TAG_NAME_GRAY_TEXT = 'gray_text'
    TAG_NAME_CODE_TEXT = 'code_text'
    TAG_NAME_CODE_BLOCK = 'code_block'
    TAG_NAME_UNFOCUSED_TEXT = 'unfocused_text'
    TAG_NAME_MARGIN_INDENT = 'margin_indent'

    # The patterns whose whole match takes one tag.
    SPAN_REGEXPS = [
      [MarkupRegex::ITALIC_ASTERISK, TAG_NAME_ITALIC],
      [MarkupRegex::ITALIC_UNDERSCORE, TAG_NAME_ITALIC],
      [MarkupRegex::BOLD, TAG_NAME_BOLD],
      [MarkupRegex::BOLD_ITALIC, TAG_NAME_BOLD_ITALIC],
      [MarkupRegex::STRIKETHROUGH, TAG_NAME_STRIKETHROUGH],
      [MarkupRegex::CODE, TAG_NAME_CODE_TEXT],
      [MarkupRegex::MATH, TAG_NAME_CODE_TEXT],
      [MarkupRegex::TABLE, TAG_NAME_WRAP_NONE],
    ].freeze

    # The patterns where only the syntax around the "text" group is greyed.
    SURROUND_REGEXPS = [
      [MarkupRegex::LINK, TAG_NAME_GRAY_TEXT],
      [MarkupRegex::IMAGE, TAG_NAME_GRAY_TEXT],
    ].freeze

    # Whether the text outside the current sentence is greyed out. The text
    # view owns the mode; this is the flag the next apply reads.
    attr_accessor :focus_mode

    def initialize(text_view)
      @text_view = text_view
      @text_buffer = text_view.buffer
      @focus_mode = false

      @tags_margins_indents = {}
      @baseline_margin = 0
      @char_width = 0

      @parsing = false
      @apply_pending = false
      @queue = Thread::Queue.new
      @worker = start_worker

      create_tags
      update_margins_indents
      on_style_updated
    end

    # Re-reads the colour the shaded code background is drawn in. Called after
    # every theme change, which is what upstream's application does through
    # `textview.markup.on_style_updated`.
    def on_style_updated
      code_background.then do |color|
        tag_code_text.set_property('background', color)
        tag_code_block.set_property('paragraph-background', color)
      end
    end

    # Parses the buffer and applies the result. While a parse is in flight this
    # only records that another is wanted, so the queue holds at most one text.
    def apply
      if @parsing
        @apply_pending = true
      else
        @parsing = true
        @apply_pending = false
        @queue.push(@text_buffer.get_slice(@text_buffer.start_iter, @text_buffer.end_iter, false))
      end
    end

    # Applies a parse result, as long as the buffer still holds the text that
    # was parsed; the focus-mode greying is redone either way, since it depends
    # on the cursor rather than on the text.
    def do_apply(original_text, result = [])
      start_iter = @text_buffer.start_iter
      end_iter = @text_buffer.end_iter
      text = @text_buffer.get_slice(start_iter, end_iter, false)

      if text == original_text
        clear_markup_tags(start_iter, end_iter)
        result.each do |tag_name, tag_args, tag_start, tag_end|
          @text_buffer.apply_tag(
            tag_for(tag_name, tag_args),
            @text_buffer.get_iter_at(offset: tag_start),
            @text_buffer.get_iter_at(offset: tag_end),
          )
        end
      end

      apply_focus_mode(start_iter, end_iter)
    end

    # Margin and indent are both measured in characters of the editor's font,
    # so both are recomputed whenever the font or the view's own left margin
    # changes — along with the tab stops, which are four characters wide.
    def update_margins_indents
      baseline_margin = @text_view.left_margin
      char_width = Helpers.char_width(@text_view)

      unless baseline_margin == @baseline_margin && char_width == @char_width
        @baseline_margin = baseline_margin
        @char_width = char_width

        @text_view.tabs = Pango::TabArray.new(1, true).tap do |tab_array|
          tab_array.set_tab(0, :left, 4 * char_width)
        end

        @tags_margins_indents.each do |(margin_level, indent_level), tag|
          margin, indent = margin_indent(
            margin_level,
            indent_level,
            baseline_margin: baseline_margin,
            char_width:      char_width,
          )
          tag.set_property('left-margin', margin)
          tag.set_property('indent', indent)
        end
      end
    end

    # Margin and indent are cumulative, and differ in two ways: the margin only
    # affects the first line of a wrapped paragraph while the indent affects
    # every line, and the margin level may be negative, since a baseline margin
    # exists for it to be subtracted from.
    def margin_indent(margin_level, indent_level, baseline_margin: nil, char_width: nil)
      baseline_margin ||= @text_view.left_margin
      char_width ||= Helpers.char_width(@text_view)
      [
        [baseline_margin + (char_width * margin_level), 0].max,
        char_width * indent_level,
      ]
    end

    def margin_indent_tag(margin_level, indent_level)
      [margin_level, indent_level].then do |level|
        @tags_margins_indents[level] ||= create_margin_indent_tag(margin_level, indent_level)
      end
    end

    # Ends the worker thread. The handler is not usable afterwards; the text
    # view calls this when it is destroyed.
    def stop
      @queue.close
      @worker.join(1)
    end

    private

      def start_worker
        Thread.new do
          while (text = next_text)
            parse(text).then do |result|
              GLib::Idle.add do
                @parsing = false
                if @apply_pending
                  apply
                end
                do_apply(text, result)
                false
              end
            end
          end
        end
      end

      # Takes the most recent text in the queue and drops the ones behind it:
      # an older text's highlighting is never worth computing.
      def next_text
        @queue.pop.then do |text|
          until @queue.empty?
            text = @queue.pop
          end
          text
        end
      end

      # The parse itself: a list of [tag_name, tag_args, start_offset,
      # end_offset]. Pure string work, which is why it is safe off the main
      # thread.
      def parse(text)
        [].tap do |result|
          SPAN_REGEXPS.each do |regexp, tag_name|
            text.scan(regexp) do
              result << [tag_name, [], Regexp.last_match.begin(0), Regexp.last_match.end(0)]
            end
          end

          SURROUND_REGEXPS.each do |regexp, tag_name|
            text.scan(regexp) do
              match = Regexp.last_match
              result << [tag_name, [], match.begin(0), match.begin(:text)]
              result << [tag_name, [], match.end(:text), match.end(0)]
            end
          end

          text.scan(MarkupRegex::LINK_ALT) do
            match = Regexp.last_match
            result << [TAG_NAME_GRAY_TEXT, [], match.begin(:text), match.end(:text)]
          end

          text.scan(MarkupRegex::HORIZONTAL_RULE) do
            match = Regexp.last_match
            result << [TAG_NAME_CENTER, [], match.begin(:symbols), match.end(:symbols)]
          end

          text.scan(MarkupRegex::BLOCK_QUOTE) do
            match = Regexp.last_match
            result << [TAG_NAME_MARGIN_INDENT, [2, -2], match.begin(0), match.end(0)]
          end

          text.scan(MarkupRegex::HEADER) do
            match = Regexp.last_match
            result << [TAG_NAME_MARGIN_INDENT, [-match[:level].length - 1, 0], match.begin(0), match.end(0)]
            result << [TAG_NAME_BOLD, [], match.begin(0), match.end(0)]
          end

          text.scan(MarkupRegex::HEADER_UNDER) do
            match = Regexp.last_match
            result << [TAG_NAME_BOLD, [], match.begin(0), match.end(0)]
          end

          text.scan(MarkupRegex::CODE_BLOCK) do
            match = Regexp.last_match
            result << [TAG_NAME_CODE_BLOCK, [], match.begin(:block), match.end(:block)]
          end
        end
      end

      def create_margin_indent_tag(margin_level, indent_level)
        margin, indent = margin_indent(margin_level, indent_level)
        @text_buffer.create_tag(
          "margin_indent_#{margin_level}_#{indent_level}",
          'left-margin' => margin,
          'indent'      => indent,
        )
      end

      def tag_for(tag_name, tag_args)
        if tag_name == TAG_NAME_MARGIN_INDENT
          margin_indent_tag(*tag_args)
        else
          tags_markup.fetch(tag_name)
        end
      end

      def tags_markup
        @tags_markup ||= {
          TAG_NAME_ITALIC        => tag_italic,
          TAG_NAME_BOLD          => tag_bold,
          TAG_NAME_BOLD_ITALIC   => tag_bold_italic,
          TAG_NAME_STRIKETHROUGH => tag_strikethrough,
          TAG_NAME_CENTER        => tag_center,
          TAG_NAME_WRAP_NONE     => tag_wrap_none,
          TAG_NAME_PLAIN_TEXT    => tag_plain_text,
          TAG_NAME_GRAY_TEXT     => tag_gray_text,
          TAG_NAME_CODE_TEXT     => tag_code_text,
          TAG_NAME_CODE_BLOCK    => tag_code_block,
        }
      end

      def clear_markup_tags(start_iter, end_iter)
        tags_markup.each_value { |tag| @text_buffer.remove_tag(tag, start_iter, end_iter) }
        @tags_margins_indents.each_value { |tag| @text_buffer.remove_tag(tag, start_iter, end_iter) }
      end

      def apply_focus_mode(start_iter, end_iter)
        @text_buffer.remove_tag(tag_unfocused_text, start_iter, end_iter)
        if @focus_mode
          start_sentence, end_sentence = @text_buffer.current_sentence_bounds
          @text_buffer.apply_tag(tag_unfocused_text, start_iter, start_sentence)
          @text_buffer.apply_tag(tag_unfocused_text, end_sentence, end_iter)
        end
      end

      # Touching every tag method once, so each tag exists in the buffer's tag
      # table from the start — the order tags are created in decides which wins
      # where two of them overlap.
      def create_tags
        tags_markup
        tag_unfocused_text
      end

      def code_background
        @text_view.style_context.lookup_color('code_bg_color').then do |found, color|
          if found
            color.to_s
          else
            @text_view.style_context.lookup_color('background_color').last.to_s
          end
        end
      end

      def tag_italic
        @tag_italic ||= @text_buffer.create_tag(
          TAG_NAME_ITALIC,
          'weight' => Pango::Weight::NORMAL,
          'style'  => :italic,
        )
      end

      def tag_bold
        @tag_bold ||= @text_buffer.create_tag(
          TAG_NAME_BOLD,
          'weight' => Pango::Weight::BOLD,
          'style'  => :normal,
        )
      end

      def tag_bold_italic
        @tag_bold_italic ||= @text_buffer.create_tag(
          TAG_NAME_BOLD_ITALIC,
          'weight' => Pango::Weight::BOLD,
          'style'  => :italic,
        )
      end

      def tag_strikethrough
        @tag_strikethrough ||= @text_buffer.create_tag(
          TAG_NAME_STRIKETHROUGH,
          'strikethrough' => true,
        )
      end

      def tag_center
        @tag_center ||= @text_buffer.create_tag(
          TAG_NAME_CENTER,
          'justification' => :center,
        )
      end

      def tag_wrap_none
        @tag_wrap_none ||= @text_buffer.create_tag(
          TAG_NAME_WRAP_NONE,
          'wrap-mode'          => :none,
          'pixels-above-lines' => 0,
          'pixels-below-lines' => 0,
        )
      end

      def tag_plain_text
        @tag_plain_text ||= @text_buffer.create_tag(
          TAG_NAME_PLAIN_TEXT,
          'weight'        => Pango::Weight::NORMAL,
          'style'         => :normal,
          'strikethrough' => false,
          'justification' => :left,
        )
      end

      def tag_gray_text
        @tag_gray_text ||= @text_buffer.create_tag(
          TAG_NAME_GRAY_TEXT,
          'foreground' => 'gray',
          'weight'     => Pango::Weight::NORMAL,
          'style'      => :normal,
        )
      end

      def tag_code_text
        @tag_code_text ||= @text_buffer.create_tag(
          TAG_NAME_CODE_TEXT,
          'weight'        => Pango::Weight::NORMAL,
          'style'         => :normal,
          'strikethrough' => false,
        )
      end

      def tag_code_block
        @tag_code_block ||= @text_buffer.create_tag(
          TAG_NAME_CODE_BLOCK,
          'weight'        => Pango::Weight::NORMAL,
          'style'         => :normal,
          'strikethrough' => false,
          'indent'        => margin_indent(0, 1).last,
        )
      end

      def tag_unfocused_text
        @tag_unfocused_text ||= @text_buffer.create_tag(
          TAG_NAME_UNFOCUSED_TEXT,
          'foreground' => 'gray',
          'weight'     => Pango::Weight::NORMAL,
          'style'      => :normal,
        )
      end
  end
end
