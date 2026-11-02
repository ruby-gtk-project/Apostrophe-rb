# frozen_string_literal: true

require 'adwaita'
require_relative 'helpers'
require_relative 'settings'
require_relative 'theme'

module Apostrophe
  # Style loads the application's own stylesheet onto a display and swaps the
  # theme-specific sheet whenever the colour scheme changes.
  #
  # Ported from data/media/css/gtk/style.css, style-dark.css and
  # style-sepia.css, which this port ships under lib/apostrophe/resources/css.
  #
  # Upstream never loads style.css or style-dark.css itself: GTK4 picks both up
  # automatically from the application's GResource base path, and only the
  # sepia sheet is added to and removed from the display by hand. The port
  # loads from files rather than a resource bundle, so that automatic pickup
  # does not happen and both sheets are loaded here instead — the base sheet
  # once, and whichever of dark/sepia applies through a second provider that is
  # reloaded in place, so switching schemes never stacks providers on the
  # display.
  #
  # The classes the base sheet defines, and which the widgets ask for by name:
  # apostrophe-window, apostrophe-editor, stats-button, lexikon,
  # quick-preview-popup, themeswitcher, preview_button_left,
  # preview_button_right, open-popover, preview-flap, preview-stack.
  class Style
    BASE_PRIORITY = Gtk::StyleProvider::PRIORITY_APPLICATION
    THEME_PRIORITY = Gtk::StyleProvider::PRIORITY_USER

    def self.instance = @instance ||= new

    def initialize
      @observers = []
    end

    # Loads both providers onto the display and keeps the theme provider in
    # step with the colour scheme from then on. `notify::dark` is watched as
    # well as the setting, because the "auto" scheme follows the system and
    # changes the sheet without the setting changing.
    def build(display: Gdk::Display.default)
      # Upstream registers its five symbolic icons by shipping them inside the
      # GResource bundle, under the prefix GTK scans by itself. The port ships
      # them as files, so the directory holding them goes on the display's icon
      # theme search path, where GTK finds a bare `<name>.svg` without the
      # theme/size/context subdirectories a full icon theme would need.
      Gtk::IconTheme.get_for_display(display)
        .add_search_path(File.expand_path('resources/icons', __dir__))

      Gtk::StyleContext.add_provider_for_display(display, base_provider, BASE_PRIORITY)
      Gtk::StyleContext.add_provider_for_display(display, theme_provider, THEME_PRIORITY)

      Settings.instance.connect_changed('color-scheme') { apply_theme }
      style_manager.signal_connect('notify::dark') { apply_theme }
      style_manager.signal_connect('notify::high-contrast') { apply_theme }

      apply_theme

      self
    end

    # Registers a block to run after every theme change. The markup handler
    # uses it to re-read the code background colour, which is what upstream
    # does through `textview.markup.on_style_updated`.
    def on_change(&block)
      @observers << block
      block
    end

    def apply_theme
      Theme.current.then do |theme|
        style_manager.color_scheme = color_scheme_for(theme.name)
        load_theme_sheet(theme)
        @observers.each(&:call)
      end
    end

    # Adwaita only knows light and dark; sepia is a light scheme whose colours
    # the sepia sheet overrides, which is how upstream's theme switcher maps it.
    def color_scheme_for(name)
      case name
      when 'dark' then :force_dark
      when 'light', 'sepia' then :force_light
      else :prefer_light
      end
    end

    def base_provider
      @base_provider ||= Gtk::CssProvider.new.tap do |provider|
        provider.load_from_path(Helpers.media_path('/css/gtk/style.css'))
      end
    end

    def theme_provider = @theme_provider ||= Gtk::CssProvider.new

    def style_manager = @style_manager ||= Adwaita::StyleManager.default

    private

      # Sepia wins over dark because it is an explicit choice; otherwise the
      # dark sheet follows the style manager, so it applies under the "auto"
      # scheme on a dark system too. Light needs no extra sheet: its colours
      # are the ones the base sheet already defines.
      def load_theme_sheet(theme)
        if theme.name == 'sepia'
          theme_provider.load_from_path(theme.gtk_css)
        elsif style_manager.dark?
          theme_provider.load_from_path(Helpers.media_path('/css/gtk/style-dark.css'))
        else
          theme_provider.load_from_data('')
        end
      end
  end
end
