# frozen_string_literal: true

require 'adwaita'
require_relative 'helpers'
require_relative 'rb/version'

module Apostrophe
  # AboutDialog is the app.about window: Apostrophe's name, version,
  # copyright, credits and the debug information block.
  #
  # Ported from data/ui/About.ui.in, an AdwAboutWindow filled in at build time
  # by meson's `configure_file` (`@app-id@`, `@version@`, `@package_url@`).
  # This port has no build-time substitution step, so those three values are
  # filled in directly: the version from lib/apostrophe/rb/version.rb, the app
  # id as the port's own `org.rubygtkproject.Apostrophe`, and the project's
  # GitHub URL in place of upstream's GitLab one.
  class AboutDialog
    DEVELOPERS = [
      'Wolf Vollprecht <w.vollprecht@gmail.com>',
      'Manuel Genovés <manuel.genoves@gmail.com>',
      'Gonçalo Silva <goncalossilva@gmail.com>',
      'Thomas Lavend <lavendthomas@outlook.be>',
      'Vova Kolobok',
    ].freeze

    DESIGNERS = [
      'Tobias Bernard <hi@tobiasbernard.com>',
      'Manuel Genovés <manuel.genoves@gmail.com>',
    ].freeze

    def build = window

    def present(parent)
      window.transient_for = parent
      window.present
    end

    private

      def window
        @window ||= Adwaita::AboutWindow.new.tap do |win|
          win.application_name = 'Apostrophe'
          win.application_icon = 'accessories-text-editor-symbolic'
          win.version = Apostrophe::Rb::VERSION
          win.copyright = 'Copyright (C) 2022, Manuel G., Wolf V.'
          win.website = 'https://github.com/ruby-gtk-project/Apostrophe-rb'
          win.developer_name = 'Manuel Genovés'
          win.developers = DEVELOPERS
          win.designers = DESIGNERS
          win.artists = ['Tobias Bernard <hi@tobiasbernard.com>']
          win.issue_url = 'https://github.com/ruby-gtk-project/Apostrophe-rb/issues'
          win.license_type = :gpl_3_0
          win.debug_info = Helpers.get_debug_info
        end
      end
  end
end
