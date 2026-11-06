# frozen_string_literal: true

require 'adwaita'
require_relative 'settings'
require_relative 'stats_counter'

module Apostrophe
  # StatsHandler drives the statistics button in the header bar: the label
  # shows whichever stat the user picked (characters, words, sentences,
  # paragraphs or read time), counting the whole document or, while there is
  # a selection, the selected range, and its popover lets the user change
  # which stat is shown.
  #
  # Ported from apostrophe/stats_handler.py. Upstream's popover items carry
  # an `app.stat_default` action target; the port's popover menu items call
  # back into this class directly instead, since nothing else in the port
  # needs that action to exist at the application level.
  class StatsHandler
    STATS = Settings::STATS

    def initialize(stats_button, text_view)
      @stats_button = stats_button
      @text_view = text_view

      @characters = 0
      @words = 0
      @sentences = 0
      @paragraphs = 0
      @read_time = [0, 0, 0]

      @selected_characters = 0
      @selected_words = 0
      @selected_sentences = 0
      @selected_paragraphs = 0
      @selected_read_time = [0, 0, 0]

      @settings = Settings.instance

      @counter = StatsCounter.new { |result| update_stats(result) }
      @selected_counter = StatsCounter.new { |result| update_selection_stats(result) }

      text_view.buffer.signal_connect('changed') { on_text_changed }
      text_view.buffer.signal_connect('notify::cursor-position') { on_text_selected }

      stats_button.popover = popover
      stats_button.direction = :up
      stats_button.insert_action_group('stats', action_group)

      update_default_stat(close_popover: false)
    end

    # Stops both worker threads. The handler is not usable afterwards.
    def stop
      @counter.stop
      @selected_counter.stop
    end

    private

      def on_text_changed
        buffer = @text_view.buffer
        @counter.count(buffer.get_text(buffer.start_iter, buffer.end_iter, false))
      end

      def on_text_selected
        buffer = @text_view.buffer
        if buffer.has_selection?
          start_iter, end_iter = buffer.selection_bounds
          @selected_counter.count(buffer.get_text(start_iter, end_iter, false))
        end
      end

      def update_stats(result)
        @characters = result.characters
        @words = result.words
        @sentences = result.sentences
        @paragraphs = result.paragraphs
        @read_time = result.read_time
        update_default_stat(close_popover: false)
      end

      def update_selection_stats(result)
        @selected_characters = result.characters
        @selected_words = result.words
        @selected_sentences = result.sentences
        @selected_paragraphs = result.paragraphs
        @selected_read_time = result.read_time
        update_default_stat(close_popover: false)
      end

      def update_default_stat(close_popover: true)
        @stats_button.label = text_for_stat(@settings.stat_default)
        popover.menu_model = menu
        if close_popover
          popover.popdown
        end
      end

      def has_selection? = @text_view.buffer.has_selection?

      def text_for_stat(stat)
        case stat
        when 'characters' then character_text
        when 'words' then word_text
        when 'sentences' then sentence_text
        when 'paragraphs' then paragraph_text
        when 'read_time' then read_time_text
        else raise ArgumentError, "unknown stat #{stat}"
        end
      end

      def character_text
        has_selection? ? "#{@selected_characters} of #{@characters} Characters" : "#{@characters} Characters"
      end

      def word_text
        has_selection? ? "#{@selected_words} of #{@words} Words" : "#{@words} Words"
      end

      def sentence_text
        has_selection? ? "#{@selected_sentences} of #{@sentences} Sentences" : "#{@sentences} Sentences"
      end

      def paragraph_text
        has_selection? ? "#{@selected_paragraphs} of #{@paragraphs} Paragraphs" : "#{@paragraphs} Paragraphs"
      end

      def read_time_text
        if has_selection?
          "#{format_time(@selected_read_time)} of #{format_time(@read_time)} Read Time"
        else
          "#{format_time(@read_time)} Read Time"
        end
      end

      def format_time(time) = format('%d:%02d:%02d', *time)

      def on_stat_selected(stat)
        @settings.stat_default = stat
        update_default_stat
      end

      # Memoized widget methods

      def popover
        @popover ||= Gtk::PopoverMenu.new.tap do |popover|
          popover.menu_model = menu
          popover.halign = :end
          popover.margin_end = 6
          popover.margin_bottom = 6
          popover.has_arrow = false
          popover.signal_connect('closed') { @text_view.grab_focus }
        end
      end

      def menu
        Gio::Menu.new.tap do |menu|
          STATS.each do |stat|
            Gio::MenuItem.new(text_for_stat(stat), nil).tap do |item|
              item.set_action_and_target_value('stats.select', GLib::Variant.new(stat))
              menu.append_item(item)
            end
          end
        end
      end

      def action_group
        @action_group ||= Gio::SimpleActionGroup.new.tap do |group|
          Gio::SimpleAction.new('select', GLib::VariantType.new('s')).tap do |action|
            action.signal_connect('activate') { |_action, parameter| on_stat_selected(parameter.get_string.first) }
            group.add_action(action)
          end
        end
      end
  end
end
