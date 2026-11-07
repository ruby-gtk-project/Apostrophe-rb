# frozen_string_literal: true

require 'gtk4'
require_relative 'helpers'

module Apostrophe
  # PreviewLayoutSwitcherItem is one row of the preview layout popover: an
  # icon and a title at the start, a checkmark at the end that only the
  # currently selected row shows.
  #
  # Ported from the `PreviewLayoutSwitcherItem` class in
  # apostrophe/preview_layout_switcher.py and
  # data/ui/PreviewLayoutSwitcherItem.ui. Upstream exposes `selected` as a
  # GObject property and reacts to its own `notify::selected` signal; the
  # Ruby bindings make declaring a property on a Gtk::ListBoxRow subclass
  # needlessly heavy for one boolean, so `selected=` below does directly
  # what upstream's `on_selected` handler does.
  class PreviewLayoutSwitcherItem < Gtk::ListBoxRow
    Helpers.bind_gettext(self)

    # `layout` is one entry of PreviewLayout::ALL: a hash with :value, :text
    # and :icon.
    attr_reader :layout

    def initialize(layout)
      super()
      @layout = layout
      @selected = false
      self.child = row
      icon.icon_name = layout.fetch(:icon)
      title.label = _(layout.fetch(:text))
    end

    def selected? = @selected

    def selected=(value)
      @selected = value
      if value
        checkmark.opacity = 1
      else
        checkmark.opacity = 0
      end
    end

    private

      def row
        @row ||= Gtk::Box.new(:horizontal, 0).tap do |box|
          box.append(label_box)
          box.append(checkmark)
        end
      end

      def label_box
        @label_box ||= Gtk::Box.new(:horizontal, 12).tap do |box|
          box.halign = :start
          box.valign = :center
          box.append(icon)
          box.append(title)
        end
      end

      def icon = @icon ||= Gtk::Image.new.tap { |image| image.add_css_class('list-icon') }

      def title = @title ||= Gtk::Label.new

      def checkmark
        @checkmark ||= Gtk::Image.new.tap do |image|
          image.icon_name = 'emblem-ok-symbolic'
          image.add_css_class('checkmark')
          image.opacity = 0
        end
      end
  end
end
