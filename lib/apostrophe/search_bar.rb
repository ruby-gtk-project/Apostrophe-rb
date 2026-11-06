# frozen_string_literal: true

require 'adwaita'
require_relative 'helpers'

module Apostrophe
  # SearchBar adds regex-capable search and replace over the editor's buffer,
  # highlighting every match and letting the cursor step between them.
  #
  # Ported from apostrophe/search_and_replace.py and data/ui/SearchBar.ui.
  # Upstream drives most of this through GObject property bindings declared
  # in the .ui file (`replace-mode-enabled` toggling `search-mode-enabled`,
  # the revealer bound to it, the toggle button bound bidirectionally); the
  # port wires the same behaviour with plain signal handlers, which is the
  # same result without a template to parse.
  class SearchBar < Adwaita::Bin
    def initialize(text_view)
      super()
      @text_view = text_view
      @text_buffer = text_view.buffer
      @matches = []
      @active = 0
      self.child = search_bar
    end

    def build = self

    # Upstream's `search-mode-enabled` setter: win.find toggles this true.
    def search_mode_enabled = search_bar.search_mode_enabled?

    def search_mode_enabled=(value)
      search_bar.search_mode_enabled = value
      if value
        on_search_enabled
      else
        on_search_disabled
      end
    end

    # win.find_replace: opens search (if needed) with the replace row shown.
    def replace_mode_enabled=(value)
      replace_toggle.active = value
      if value
        self.search_mode_enabled = true
      end
    end

    private

      def on_search_enabled
        @text_buffer = @text_view.buffer
        if @text_buffer.has_selection?
          start_iter, end_iter = @text_buffer.selection_bounds
          search_entry.text = @text_buffer.get_slice(start_iter, end_iter, false)
        end
        search_entry.grab_focus
        search_entry.select_region(0, -1)
        search
      end

      def on_search_disabled
        @text_buffer.remove_tag(highlight_tag, @text_buffer.start_iter, @text_buffer.end_iter)
        @matches = []
        replace_toggle.active = false
        @text_view.grab_focus
      end

      def search(scroll: true)
        search_text = search_entry.text
        context_start = @text_buffer.start_iter
        context_end = @text_buffer.end_iter
        text = @text_buffer.get_slice(context_start, context_end, false)

        @text_buffer.remove_tag(highlight_tag, context_start, context_end)

        if regex_button.active?
          pattern = search_text
        else
          pattern = Regexp.escape(search_text)
        end
        if case_button.active?
          options = 0
        else
          options = Regexp::IGNORECASE
        end

        @matches = []
        @active = 0
        if !pattern.empty?
          begin
            Regexp.new(pattern, options).then do |regexp|
              text.to_enum(:scan, regexp).each do
                match = Regexp.last_match
                @matches << [match.begin(0), match.end(0)]
              end
            end
          rescue RegexpError
            @matches = []
          end
        end

        @matches.each do |start_offset, end_offset|
          @text_buffer.apply_tag(
            highlight_tag,
            @text_buffer.get_iter_at(offset: start_offset),
            @text_buffer.get_iter_at(offset: end_offset),
          )
        end

        if scroll
          scroll_to(@active)
        end
      end

      def scroll_to(index)
        unless @matches.empty?
          @active = index % @matches.length
          start_offset, end_offset = @matches[@active]
          start_iter = @text_buffer.get_iter_at(offset: start_offset)
          end_iter = @text_buffer.get_iter_at(offset: end_offset)

          @text_view.scroller.smooth_scroll_to_mark(
            @text_buffer.create_mark(nil, start_iter, false), true,
          )
          @text_buffer.select_range(start_iter, end_iter)
        end
      end

      def replace_one
        unless @matches.empty?
          Helpers.user_action(@text_buffer) { do_replace(@matches[@active]) }
          active = @active
          search(scroll: false)
          @active = active
          scroll_to(@active)
        end
      end

      def replace_all
        Helpers.user_action(@text_buffer) do
          @matches.reverse_each { |match| do_replace(match) }
        end
        search(scroll: false)
      end

      def do_replace(match)
        start_offset, end_offset = match
        start_iter = @text_buffer.get_iter_at(offset: start_offset)
        end_iter = @text_buffer.get_iter_at(offset: end_offset)
        @text_buffer.delete(start_iter, end_iter)
        @text_buffer.insert(@text_buffer.get_iter_at(offset: start_offset), replace_entry.text)
      end

      def highlight_tag
        @highlight_tag ||= @text_buffer.tag_table.lookup('search_highlight') ||
          @text_buffer.create_tag('search_highlight', background: 'yellow')
      end

      # Memoized widget methods

      def search_bar
        @search_bar ||= Gtk::SearchBar.new.tap do |bar|
          bar.child = search_panel_box
          bar.connect_entry(search_entry)
        end
      end

      def search_panel_box
        @search_panel_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
          box.append(search_box)
          box.append(replace_revealer)
        end
      end

      def search_box
        @search_box ||= Gtk::Box.new(:horizontal, 6).tap do |box|
          box.append(search_entry_box)
          box.append(search_tools_box)
        end
      end

      def search_entry_box
        @search_entry_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
          box.add_css_class('linked')
          box.append(search_entry)
          box.append(previous_result_button)
          box.append(next_result_button)
        end
      end

      def search_entry
        @search_entry ||= Gtk::SearchEntry.new.tap do |entry|
          entry.signal_connect('search-changed') { search }
          entry.signal_connect('stop-search') { self.search_mode_enabled = false }
        end
      end

      def previous_result_button
        @previous_result_button ||= Gtk::Button.new(icon_name: 'go-up-symbolic').tap do |button|
          button.tooltip_text = 'Previous Match'
          button.signal_connect('clicked') { scroll_to(@active - 1) }
        end
      end

      def next_result_button
        @next_result_button ||= Gtk::Button.new(icon_name: 'go-down-symbolic').tap do |button|
          button.tooltip_text = 'Next Match'
          button.signal_connect('clicked') { scroll_to(@active + 1) }
        end
      end

      def search_tools_box
        @search_tools_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
          box.add_css_class('linked')
          box.homogeneous = true
          box.append(case_button)
          box.append(regex_button)
          box.append(replace_toggle)
        end
      end

      def case_button
        @case_button ||= Gtk::ToggleButton.new.tap do |button|
          button.label = 'aA'
          button.tooltip_text = 'Case Sensitive'
          button.signal_connect('clicked') { search }
        end
      end

      def regex_button
        @regex_button ||= Gtk::ToggleButton.new.tap do |button|
          button.label = '(.*)'
          button.tooltip_text = 'Regular Expression'
          button.signal_connect('clicked') { search }
        end
      end

      def replace_toggle
        @replace_toggle ||= Gtk::ToggleButton.new(icon_name: 'edit-find-replace-symbolic').tap do |button|
          button.tooltip_text = 'Replace'
          button.signal_connect('toggled') do
            replace_revealer.reveal_child = button.active?
            if button.active?
              self.search_mode_enabled = true
            end
          end
        end
      end

      def replace_revealer
        @replace_revealer ||= Gtk::Revealer.new.tap { |revealer| revealer.child = replace_box }
      end

      def replace_box
        @replace_box ||= Gtk::Box.new(:horizontal, 6).tap do |box|
          box.margin_top = 6
          box.append(replace_entry_box)
          box.append(replace_tools_box)
        end
      end

      def replace_entry_box
        @replace_entry_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
          box.add_css_class('linked')
          box.append(replace_entry)
        end
      end

      def replace_entry
        @replace_entry ||= Gtk::Entry.new.tap do |entry|
          entry.hexpand = true
          entry.primary_icon_name = 'edit-find-replace-symbolic'
        end
      end

      def replace_tools_box
        @replace_tools_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
          box.add_css_class('linked')
          box.append(replace_one_button)
          box.append(replace_all_button)
        end
      end

      def replace_one_button
        @replace_one_button ||= Gtk::Button.new(label: 'Replace').tap do |button|
          button.signal_connect('clicked') { replace_one }
        end
      end

      def replace_all_button
        @replace_all_button ||= Gtk::Button.new(label: 'Replace All').tap do |button|
          button.signal_connect('clicked') { replace_all }
        end
      end
  end
end
