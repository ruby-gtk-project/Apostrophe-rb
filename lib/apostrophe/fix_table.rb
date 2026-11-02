# frozen_string_literal: true

require 'adwaita'
require 'fileutils'
require_relative 'helpers'

module Apostrophe
  # FixTable reflows the markdown table the cursor is in, so every column is as
  # wide as its widest cell again and the `+---+---+` separators line up.
  #
  # Ported from apostrophe/fix_table.py.
  #
  # Two things upstream does are deliberately not carried over: its debug
  # `print` calls, and the final write, which inserts the rebuilt table at the
  # start of the buffer without removing the old one. The port replaces the
  # lines the table occupies, which is what "fix table" means, and does it in
  # one user action so a single undo puts the old table back.
  class FixTable
    def initialize(text_buffer)
      @text_buffer = text_buffer
    end

    # A line of `+` and the given fill character, one segment per column:
    #   separator([2, 4], '-') => "+----+------+"
    def self.separator(widths, char)
      widths.map { |width| "+#{char * (width + 2)}" }.join + '+'
    end

    # One row, each cell padded to its column's width:
    #   line(['name', 'surname'], [7, 10]) => "| name    | surname    |"
    def self.line(columns, widths)
      [columns.length, widths.length].min.then do |pairs|
        columns.take(pairs).zip(widths.take(pairs))
          .map { |text, width| "| #{text}#{' ' * (width - text.length)} " }
          .join + '|'
      end
    end

    # The whole table, with the `+===+` rule under the header row:
    #
    #   +----------+---------+
    #   | software | version |
    #   +==========+=========+
    #   | ruby     | 3.4     |
    #   +----------+---------+
    def self.table(content)
      widths = column_widths(content)
      [
        separator(widths, '-'),
        line(content.first, widths),
        separator(widths, '='),
        *content.drop(1).flat_map { |row| [line(row, widths), separator(widths, '-')] },
      ].join("\n")
    end

    # Python's `zip(*content)` stops at the shortest row, so a ragged table is
    # measured over the columns every row has.
    def self.column_widths(content)
      content.map(&:length).min.then do |columns|
        (0...columns).map { |index| content.map { |row| row[index].length }.max }
      end
    end

    def self.in_a_table?(line) = line.include?('|') || line.include?('+')

    def self.in_a_paragraph?(line) = !line.strip.empty?

    def self.remove_spaces(string) = string.gsub(/\s\s+/, ' ')

    def self.separators_removing_spaces(string) = string.gsub(/\s\s+/, '|')

    # The cells of one row, with the padding and the empty leading and trailing
    # segments the `|` delimiters leave behind dropped.
    def self.cells(string)
      remove_spaces(string).split('|').map(&:strip).reject(&:empty?)
    end

    # The table's cells, taken from the lines that have any.
    def self.extract_table(lines, top, bottom)
      lines[top..bottom].select { |line| line.include?('|') }.map { |line| cells(line) }
    end

    # The words of each line as a row of cells, used to build a table out of
    # space-separated text rather than to reflow an existing one.
    def self.extract_words_as_lists(lines, top, bottom)
      lines[top..bottom].map { |line| separators_removing_spaces(line).split('|') }
    end

    # Reflows the table the cursor is in. Does nothing when the cursor is not
    # in one, which is the case upstream logs and leaves alone.
    def fix_table
      current_line.then do |line_text|
        if self.class.in_a_table?(line_text)
          reflow
        end
      end
    end

    # The first and last line of the run of lines around the cursor for which
    # the block holds — the table's extent, or the paragraph's.
    def table_bounds(&predicate)
      lines = buffer_lines
      current = cursor_line
      [top_bound(lines, current, &predicate), bottom_bound(lines, current, &predicate)]
    end

    private

      def reflow
        buffer_lines.then do |lines|
          top, bottom = table_bounds { |line| self.class.in_a_table?(line) }
          content = self.class.extract_table(lines, top, bottom)
          unless content.empty?
            replace_lines(top, bottom, self.class.table(content))
          end
        end
      end

      def replace_lines(top, bottom, text)
        Helpers.user_action(@text_buffer) do
          start_iter = @text_buffer.get_iter_at(line: top)
          end_iter = @text_buffer.get_iter_at(line: bottom)
          end_iter.forward_to_line_end
          @text_buffer.delete(start_iter, end_iter)
          @text_buffer.insert(start_iter, text)
        end
      end

      def top_bound(lines, current)
        0.then do |top|
          current.downto(1) do |index|
            unless yield(lines[index].to_s)
              top = index + 1
              break
            end
          end
          top
        end
      end

      def bottom_bound(lines, current)
        (lines.length - 1).then do |bottom|
          (current...lines.length).each do |index|
            unless yield(lines[index].to_s)
              bottom = index - 1
              break
            end
          end
          bottom
        end
      end

      def buffer_lines
        @text_buffer.get_text(@text_buffer.start_iter, @text_buffer.end_iter, false).split("\n", -1)
      end

      def cursor_line
        @text_buffer.get_iter_at(mark: @text_buffer.get_mark('insert')).line
      end

      def current_line
        @text_buffer.get_iter_at(mark: @text_buffer.get_mark('insert')).then do |cursor_iter|
          end_line = cursor_iter.copy
          end_line.forward_to_line_end
          @text_buffer.get_text(cursor_iter, end_line, false)
        end
      end
  end
end
