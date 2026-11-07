# frozen_string_literal: true

require 'adwaita'
require_relative 'helpers'
require_relative 'settings'

module Apostrophe
  # ThemeSwitcher is the row of four colour swatches that sits at the top of the
  # main menu: follow the system, light, sepia, dark. The swatches themselves
  # are drawn entirely by the `themeswitcher` rules in the application's
  # stylesheet, which is why each button carries a class and no content.
  #
  # Ported from apostrophe/theme_switcher.py and data/ui/ThemeSwitcher.ui.
  #
  # Upstream exposes a `selected-color-scheme` GObject property and binds the
  # `color-scheme` setting to it, so the property setter both moves the radio
  # group and tells Adwaita's style manager which scheme to force. The Ruby
  # bindings do not support declaring a property on a subclass, so the port
  # writes the setting directly and lets Style — which already watches that
  # setting — do the forcing. The result is the same round trip: a click writes
  # the setting, the setting moves the swatch and swaps the stylesheet.
  class ThemeSwitcher
    Helpers.bind_gettext(self)

    # The scheme each swatch stands for, with the CSS class that paints it and
    # the tooltip upstream gives it. `N_` only marks the tooltip for
    # extraction (see its own docs) — `selector` runs the actual lookup
    # through `_` when a swatch is actually built.
    SCHEMES = [
      { name: 'auto', css_class: 'system', tooltip: N_('Use System Colors') },
      { name: 'light', css_class: 'light', tooltip: N_('Use Light Colors') },
      { name: 'sepia', css_class: 'sepia', tooltip: N_('Use Sepia Colors') },
      { name: 'dark', css_class: 'dark', tooltip: N_('Use Dark Colors') },
    ].freeze

    def build
      root.tap do |box|
        box.append(swatch_box)

        swatch_box.tap do |swatches|
          SCHEMES.each do |scheme|
            selector(scheme.fetch(:name)).tap do |button|
              swatches.append(button)
              button.signal_connect('notify::active') { on_color_scheme_changed }
            end
          end
        end

        # The system swatch is only useful where the desktop reports a
        # preference, which is what upstream's `show-system` property binding
        # tracks.
        style_manager.bind_property(
          'system-supports-color-schemes',
          selector('auto'),
          'visible',
          :sync_create,
        )
      end

      select_current
      Settings.instance.connect_changed('color-scheme') { select_current }

      root
    end

    # Moves the group to the swatch the setting names, without that move
    # writing the setting straight back.
    def select_current
      Settings.instance.color_scheme.then do |color_scheme|
        @applying = true
        begin
          selector(known_scheme(color_scheme)).active = true
        ensure
          @applying = false
        end
      end
    end

    def root
      @root ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.add_css_class('themeswitcher')
      end
    end

    def swatch_box
      @swatch_box ||= Gtk::Box.new(:horizontal, 8).tap do |box|
        box.halign = :center
        box.margin_start = 12
        box.margin_end = 12
        box.margin_bottom = 6
      end
    end

    # One swatch per scheme, memoized by name. The first one is the group
    # leader and the rest join it, which is what makes the four of them behave
    # as radio buttons.
    def selector(name)
      selectors[name] ||= Gtk::CheckButton.new.tap do |button|
        SCHEMES.find { |scheme| scheme.fetch(:name) == name }.then do |scheme|
          button.tooltip_text = _(scheme.fetch(:tooltip))
          button.add_css_class(scheme.fetch(:css_class))
          button.halign = :center
        end
        unless name == 'auto'
          button.group = selector('auto')
        end
      end
    end

    def selectors = @selectors ||= {}

    def scheme_names = @scheme_names ||= SCHEMES.map { |scheme| scheme.fetch(:name) }

    def style_manager = @style_manager ||= Adwaita::StyleManager.default

    private

      # A scheme this widget has a swatch for; anything else falls back to the
      # system swatch, the way upstream's setter ignores a name it does not know.
      def known_scheme(name)
        if scheme_names.include?(name)
          name
        else
          'auto'
        end
      end

      def on_color_scheme_changed
        unless @applying
          scheme_names.find { |name| selector(name).active? }.then do |name|
            if name
              Settings.instance.color_scheme = name
            end
          end
        end
      end
  end
end
