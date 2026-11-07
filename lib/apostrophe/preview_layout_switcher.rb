# frozen_string_literal: true

require 'gtk4'
require_relative 'helpers'
require_relative 'preview_layout_switcher_item'
require_relative 'settings'

module Apostrophe
  # PreviewLayout is the four ways the preview can be shown, ported from the
  # `PreviewLayout` IntEnum in apostrophe/preview_layout_switcher.py. The
  # order matters: it is also the order of Settings::PREVIEW_MODES and of the
  # `preview-mode` gsettings enum, so a layout's integer value is always its
  # index into either list.
  module PreviewLayout
    extend GetText
    bindtextdomain(Helpers::GETTEXT_DOMAIN, path: Helpers::LOCALE_DIRECTORY)

    FULL_WIDTH  = 0
    HALF_WIDTH  = 1
    HALF_HEIGHT = 2
    WINDOWED    = 3

    # `text` is only marked with `N_` here (see its docs); callers run it
    # through `_` when they actually show it, in
    # PreviewLayoutSwitcherItem#initialize.
    ALL = [
      { value: FULL_WIDTH, text: N_('Full-Width'), icon: 'preview-layout-full-width-symbolic' },
      { value: HALF_WIDTH, text: N_('Half-Width'), icon: 'preview-layout-half-width-symbolic' },
      { value: HALF_HEIGHT, text: N_('Half-Height'), icon: 'preview-layout-half-height-symbolic' },
      { value: WINDOWED, text: N_('Windowed'), icon: 'preview-layout-windowed-symbolic' },
    ].freeze

    def self.icon_for(value) = ALL.fetch(value).fetch(:icon)

    # The layout the `preview-mode` setting currently names.
    def self.from_settings = Settings::PREVIEW_MODES.index(Settings.instance.preview_mode) || FULL_WIDTH

    def self.to_settings(value) = Settings.instance.preview_mode = Settings::PREVIEW_MODES.fetch(value)
  end

  # PreviewLayoutSwitcher is the headerbar control that shows/hides the
  # preview and, once it is shown, lets the user pick how it is laid out:
  # full-width, half-width, half-height or a separate window.
  #
  # Ported from the `PreviewLayoutSwitcher` class in
  # apostrophe/preview_layout_switcher.py and
  # data/ui/PreviewLayoutSwitcher.ui. The toggle button that shows the
  # preview is upstream's `preview_switcher_toggle`; its own action name
  # (`win.preview`) is wired by whoever embeds this switcher, the same way
  # HeaderBar's other toggle buttons are wired by MainWindow.
  class PreviewLayoutSwitcher
    Helpers.bind_gettext(self)

    def initialize(on_layout_changed: nil)
      @on_layout_changed = on_layout_changed
      @preview_layout = PreviewLayout.from_settings
      @items = PreviewLayout::ALL.map { |layout| PreviewLayoutSwitcherItem.new(layout) }
    end

    attr_reader :preview_layout

    def build
      box.tap do |b|
        b.append(toggle_button)
        b.append(revealer)
      end
    end

    # Exposed so MainWindow can install `win.preview` as a property action on
    # this button's `active` property, the way HeaderBar exposes its own
    # toggle buttons.
    def toggle_button_object = toggle_button

    # Set after construction, once the caller that holds the renderer this
    # switcher drives exists (HeaderBar builds this switcher before
    # MainWindow has a PreviewRenderer to call back into).
    def on_layout_changed=(block)
      @on_layout_changed = block
    end

    def preview_layout=(value)
      @preview_layout = value
      update_ui
    end

    private

      def box = @box ||= Gtk::Box.new(:horizontal, 0)

      def toggle_button
        @toggle_button ||= Gtk::ToggleButton.new.tap do |button|
          button.tooltip_text = _('Preview')
          button.icon_name = 'view-dual-symbolic'
          button.add_css_class('preview_button_left')
          button.signal_connect('notify::active') { revealer.reveal_child = button.active? }
        end
      end

      def revealer
        @revealer ||= Gtk::Revealer.new.tap do |rev|
          rev.transition_type = :slide_right
          rev.child = menu_button
        end
      end

      def menu_button
        @menu_button ||= Gtk::MenuButton.new.tap do |button|
          button.popover = popover
          button.always_show_arrow = true
          button.child = layout_image
          button.add_css_class('preview_button_right')
          button.add_css_class('raised')
        end
      end

      def layout_image
        @layout_image ||= Gtk::Image.new.tap { |image| image.icon_name = PreviewLayout.icon_for(@preview_layout) }
      end

      def popover
        @popover ||= Gtk::Popover.new.tap do |pop|
          pop.add_css_class('menu')
          pop.child = list_box
          pop.signal_connect('show') { update_ui }
        end
      end

      def list_box
        @list_box ||= Gtk::ListBox.new.tap do |box|
          box.selection_mode = :none
          @items.each { |item| box.append(item) }
          box.signal_connect('row-activated') { |_box, row| on_row_activated(row) }
        end
      end

      def update_ui
        layout_image.icon_name = PreviewLayout.icon_for(@preview_layout)
        @items.each { |item| item.selected = (item.layout.fetch(:value) == @preview_layout) }
        list_box.select_row(@items[@preview_layout])
      end

      def on_row_activated(row)
        @preview_layout = row.layout.fetch(:value)
        update_ui
        popover.popdown
        @on_layout_changed&.call(@preview_layout)
      end
  end
end
