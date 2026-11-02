# frozen_string_literal: true

require_relative 'helpers'
require_relative 'settings'

module Apostrophe
  # Theme maps a colour scheme onto the web stylesheet the preview is rendered
  # with. Three themes exist; "auto" is not one of them, so a system scheme
  # falls through to the first (light), the way upstream's `get_current` starts
  # from `defaultThemes[0]` and only replaces it on an exact name match.
  #
  # Ported from apostrophe/theme_switcher.py (Theme, defaultThemes).
  Theme = Data.define(:name, :web_css) do
    def self.defaults
      @defaults ||= [
        new(name: 'light', web_css: Helpers.media_path('/css/web/adwaita.css')),
        new(name: 'dark', web_css: Helpers.media_path('/css/web/adwaita.css')),
        new(name: 'sepia', web_css: Helpers.media_path('/css/web/adwaita-sepia.css')),
      ].freeze
    end

    def self.current
      Settings.instance.color_scheme.then do |color_scheme|
        defaults.find { |theme| theme.name == color_scheme } || defaults.first
      end
    end

    # The GTK stylesheet this port loads on top of Adwaita for the theme. Light
    # needs only the base sheet; dark and sepia each override colours on top of
    # it, which is what data/media/css/gtk/style-dark.css and style-sepia.css
    # do upstream.
    def gtk_css
      Helpers.media_path("/css/gtk/#{name == 'light' ? 'style' : "style-#{name}"}.css")
    end
  end
end
