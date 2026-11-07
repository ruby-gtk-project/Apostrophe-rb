# frozen_string_literal: true

require 'adwaita'
require_relative 'helpers'

module Apostrophe
  # OpenPopover is the "Open" menu button's popover: a search entry over the
  # list of recently-opened files, each row activating the window's
  # `open_file` action with the file's URI as its target, plus a delete
  # button that drops the entry from the recent-files list without touching
  # the file itself.
  #
  # Ported from apostrophe/open_popover.py (ApostropheOpenPopover) and
  # data/ui/Recents.ui.
  #
  # Upstream binds a Gio::ListStore of a small RecentItem GObject to the list
  # box with `bind_model`, so the box stays in sync with the model
  # automatically. The Ruby bindings make registering that small GObject
  # subclass needlessly heavy for seventeen-field-free rows, so the port
  # rebuilds the row widgets directly off Gtk::RecentManager#items whenever
  # the manager changes or the search entry's text does — the same end
  # result (the box always mirrors the manager) with one fewer class.
  class OpenPopover
    Helpers.bind_gettext(self)

    # Upstream's RecentManager filters by mime type in Recents.ui through a
    # Gtk::RecentFilter the port does not build; it filters by extension
    # instead, which is the same set of files Apostrophe can actually open.
    OPENABLE_EXTENSIONS = %w[.md .markdown .txt].freeze

    def build
      popover.tap do |pop|
        pop.child = box

        box.tap do |column|
          column.append(search_entry)
          column.append(scrolled_window)

          search_entry.signal_connect('search-changed') { refresh }
        end

        scrolled_window.child = stack

        stack.tap do |s|
          s.add_child(empty_label)
          s.add_child(list_box)
        end
      end

      refresh

      popover
    end

    def popdown = popover.popdown

    private

      def recent_manager = @recent_manager ||= Gtk::RecentManager.default

      def popover
        @popover ||= Gtk::Popover.new.tap do |pop|
          pop.width_request = 320
        end
      end

      def box = @box ||= Gtk::Box.new(:vertical, 6)

      def search_entry
        @search_entry ||= Gtk::SearchEntry.new.tap do |entry|
          entry.placeholder_text = _('Search Documents')
        end
      end

      def scrolled_window
        @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |scrolled|
          scrolled.min_content_height = 1
          scrolled.max_content_height = 360
          scrolled.propagate_natural_height = true
        end
      end

      def stack = @stack ||= Gtk::Stack.new

      def empty_label
        @empty_label ||= Gtk::Label.new(_('No Recent Documents')).tap do |label|
          label.margin_top = 24
          label.margin_bottom = 24
          label.add_css_class('dim-label')
        end
      end

      def list_box
        @list_box ||= Gtk::ListBox.new.tap do |box|
          box.selection_mode = :none
        end
      end

      def recent_items
        recent_manager.items.select { |item| openable?(item) }
          .sort_by { |item| -item.modified.format('%s').to_i }
      end

      def openable?(item)
        OPENABLE_EXTENSIONS.any? { |extension| item.uri_display.to_s.end_with?(extension) }
      end

      def matching_items
        query = search_entry.text.to_s.downcase
        recent_items.select { |item| query.empty? || item.display_name.to_s.downcase.include?(query) }
      end

      def refresh
        clear_rows
        matching_items.each { |item| list_box.append(row_for(item)) }
        if list_box.first_child
          stack.visible_child = list_box
        else
          stack.visible_child = empty_label
        end
      end

      def clear_rows
        while (child = list_box.first_child)
          list_box.remove(child)
        end
      end

      def row_for(item)
        Adwaita::ActionRow.new.tap do |row|
          row.title = item.display_name
          row.subtitle = item.uri_display
          row.activatable = true
          row.action_name = 'win.open_file'
          row.set_action_target_value(GLib::Variant.new(item.uri))
          row.add_suffix(delete_button_for(item))
        end
      end

      def delete_button_for(item)
        Gtk::Button.new.tap do |button|
          button.icon_name = 'window-close-symbolic'
          button.add_css_class('flat')
          button.add_css_class('circular')
          button.valign = :center
          button.signal_connect('clicked') do
            recent_manager.remove_item(item.uri)
            refresh
          end
        end
      end
  end
end
