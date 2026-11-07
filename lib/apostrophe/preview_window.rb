# frozen_string_literal: true

require 'adwaita'

module Apostrophe
  # PreviewWindow is the separate top-level window PreviewRenderer opens for
  # the "Windowed" preview layout: a flat header bar over a vertical box
  # that PreviewRenderer moves the preview stack into and out of.
  #
  # Ported from apostrophe/preview_window.py and data/ui/PreviewWindow.ui.
  class PreviewWindow
    def build
      window.tap { |win| win.content = preview_box }
    end

    def preview_box = @preview_box ||= Gtk::Box.new(:vertical, 0).tap { |box| box.append(header_bar) }

    def present = window.present

    def close = window.close

    def title=(value)
      window.title = value
    end

    def set_default_size(width, height) = window.set_default_size(width, height)

    def window_object = window

    private

      def window
        @window ||= Adwaita::ApplicationWindow.new(Gio::Application.default).tap do |win|
          win.title = 'Preview'
        end
      end

      def header_bar
        @header_bar ||= Adwaita::HeaderBar.new.tap { |bar| bar.add_css_class('flat') }
      end
  end
end
