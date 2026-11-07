# frozen_string_literal: true

require 'adwaita'
require_relative 'helpers'

module Apostrophe
  # FormatInserter applies markdown formatting at the cursor: it wraps a
  # selection in the markers for italic, bold or strikethrough, toggles those
  # markers back off when they are already there, inserts a horizontal rule,
  # continues or starts a bullet list, and prefixes a header.
  #
  # Ported from apostrophe/text_view_format_inserter.py. Every method takes the
  # text view, so each one can be used directly or as a shortcut callback, the
  # way upstream's are. Upstream's `insert_ordered_list_item` has an empty body
  # and no caller, so there is nothing of it to carry over.
  #
  # Each insertion runs inside `Helpers.user_action`, so one shortcut press is
  # one undo step.
  class FormatInserter
    Helpers.bind_gettext(self)

    LIST_BULLETS = ['- ', '* ', '+ '].freeze

    def insert_italic(text_view)
      wrap(text_view, '_', _('italic text'))
    end

    def insert_bold(text_view)
      wrap(text_view, '**', _('bold text'))
    end

    def insert_strikethrough(text_view)
      wrap(text_view, '~~', _('strikethrough text'))
    end

    def insert_horizontal_rule(text_view)
      text_view.buffer.then do |buffer|
        Helpers.user_action(buffer) { buffer.insert_at_cursor("\n\n---\n") }
        text_view.scroll_mark_onscreen(buffer.get_mark('insert'))
      end
    end

    # With a selection that starts at a line boundary this toggles the bullet
    # on that line; without one it continues the list the cursor is in, or
    # starts a new one, leaving the placeholder word selected.
    def insert_list_item(text_view)
      text_view.buffer.then do |buffer|
        if buffer.has_selection?
          toggle_bullet(buffer)
        else
          start_or_continue_list(text_view, buffer)
        end
      end
    end

    # Replaces the selection with a header of the given level, or inserts a
    # placeholder header when nothing is selected. Either way the header's text
    # is left selected so it can be typed over.
    def insert_header(text_view, level = 1)
      text_view.buffer.then do |buffer|
        text = nil
        Helpers.user_action(buffer) do
          if buffer.has_selection?
            start_iter, end_iter = buffer.selection_bounds
            text = buffer.get_text(start_iter, end_iter, false)
            buffer.delete(start_iter, end_iter)
          else
            text = _('Header')
          end

          buffer.insert_at_cursor("#{'#' * level} #{text}")
        end

        select_text(text_view, 0, text.length)
      end
    end

    private

      # Wraps the selection in `marker`, or unwraps it when the markers are
      # already on either side of it. With nothing selected, `helptext` is
      # inserted wrapped and left selected.
      #
      # Upstream looks one marker's width outside the selection first, because
      # the selection a previous wrap left behind is the text *between* the
      # markers; that widened read is what makes a second press undo the first.
      def wrap(text_view, marker, helptext = '')
        buffer = text_view.buffer
        text_length = 0
        move_back = 0

        Helpers.user_action(buffer) do
          if buffer.has_selection?
            text_length, move_back = wrap_selection(buffer, marker)
          else
            buffer.insert_at_cursor(marker + helptext + marker)
            text_length = helptext.length
            move_back = marker.length
          end
        end

        select_text(text_view, move_back, text_length)
      end

      def wrap_selection(buffer, marker)
        start_iter, end_iter = buffer.selection_bounds
        widened = start_iter.offset >= marker.length &&
                  end_iter.offset <= buffer.char_count - marker.length

        ext_start = start_iter.copy
        ext_end = end_iter.copy
        if widened
          ext_start.backward_chars(marker.length)
          ext_end.forward_chars(marker.length)
          text = buffer.get_text(ext_start, ext_end, true)
        else
          text = buffer.get_text(start_iter, end_iter, true)
        end

        if widened && text.start_with?(marker) && text.end_with?(marker)
          unwrap_selection(
            buffer,
            marker,
            text,
            ext_start,
            ext_end,
          )
        else
          rewrap_selection(
            buffer,
            marker,
            text,
            widened,
            start_iter,
            end_iter,
          )
        end
      end

      def unwrap_selection(buffer, marker, text, ext_start, ext_end)
        text.delete_prefix(marker).delete_suffix(marker).then do |inner|
          buffer.delete(ext_start, ext_end)
          buffer.insert_at_cursor(inner)
          [inner.length, 0]
        end
      end

      # The strip-and-substitute dance keeps whatever whitespace the selection
      # picked up at its edges outside the markers.
      def rewrap_selection(buffer, marker, text, widened, start_iter, end_iter)
        if widened
          text = text.delete_prefix(marker).delete_suffix(marker)
        end
        inner = text.strip
        buffer.delete(start_iter, end_iter)
        buffer.insert_at_cursor(text.sub(inner, marker + inner + marker))
        [inner.length, marker.length]
      end

      def toggle_bullet(buffer)
        start_iter, end_iter = buffer.selection_bounds
        if start_iter.starts_line
          Helpers.user_action(buffer) do
            if buffer.get_text(start_iter, end_iter, false).start_with?(*LIST_BULLETS)
              delete_end = start_iter.copy
              delete_end.forward_chars(2)
              buffer.delete(start_iter, delete_end)
            else
              buffer.insert(start_iter, '- ')
            end
          end
        end
      end

      # Upstream reads back three lines, then looks at the last of them: when
      # it is already a bullet the same bullet character continues the list,
      # and otherwise a new list is opened with however many blank lines the
      # text above it still needs.
      def start_or_continue_list(text_view, buffer)
        helptext = _('Item')
        cursor_iter = buffer.get_iter_at(mark: buffer.get_mark('insert'))
        start_ext = cursor_iter.copy
        start_ext.backward_lines(3)
        lines = split_lines(buffer.get_text(start_ext, cursor_iter, false))

        Helpers.user_action(buffer) do
          buffer.insert_at_cursor(list_item_text(lines, cursor_iter, helptext))
        end

        select_text(text_view, 0, helptext.length)
      end

      # Python's `str.splitlines` drops the empty segment a trailing newline
      # leaves behind, but keeps the empty segments between consecutive
      # newlines. `split("\n", -1)` keeps all of them and `split("\n")` keeps
      # none, so neither is the same function — hence dropping exactly the one.
      def split_lines(text)
        text.split("\n", -1).then do |parts|
          if parts.last.to_s.empty?
            parts[0..-2]
          else
            parts
          end
        end
      end

      # In a document with nothing above the cursor, upstream iterates over
      # zero lines and inserts nothing at all; here the first branch below
      # opens a list, which is what the shortcut is for.
      def list_item_text(lines, cursor_iter, helptext)
        last = lines[-1].to_s
        if last.start_with?(*LIST_BULLETS)
          continuation_text(last[0, 2], cursor_iter, helptext)
        elsif last.empty? && lines[-2].to_s.empty?
          "- #{helptext}"
        elsif last.empty?
          continuation_text('- ', cursor_iter, helptext)
        else
          "\n\n- #{helptext}"
        end
      end

      def continuation_text(bullet, cursor_iter, helptext)
        if cursor_iter.starts_line
          "#{bullet}#{helptext}"
        else
          "\n#{bullet}#{helptext}"
        end
      end

      # Selects `length` characters ending `offset` characters before the
      # cursor, by moving the two selection marks rather than by calling
      # select_range — which is what leaves the cursor at the start of the
      # selection, ready to be typed over.
      def select_text(text_view, offset, length)
        buffer = text_view.buffer
        cursor_iter = buffer.get_iter_at(mark: buffer.get_mark('insert'))
        cursor_iter.backward_chars(offset)
        buffer.move_mark_by_name('selection_bound', cursor_iter)
        cursor_iter.backward_chars(length)
        buffer.move_mark_by_name('insert', cursor_iter)
      end
  end
end
