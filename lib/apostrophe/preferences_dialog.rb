# frozen_string_literal: true

require 'adwaita'
require_relative 'helpers'
require_relative 'settings'

module Apostrophe
  # PreferencesDialog is the app.preferences window: autohide-headerbar,
  # bigger-text and the input-format combo row, each bound straight to its
  # gsettings key.
  #
  # Ported from apostrophe/preferences_dialog.py
  # (ApostrophePreferencesDialog) and data/ui/Preferences.ui. The spellcheck
  # and session-restore rows are left out: upstream's own `.ui` marks both
  # `visible=False` (neither feature is wired up there either), so there is
  # nothing behind them to port.
  class PreferencesDialog
    Helpers.bind_gettext(self)
    # Upstream's `formats` list, each a Pandoc input format with the
    # documentation URL its help button opens.
    FORMATS = [
      { name: "Pandoc's Markdown", format: 'markdown', help: 'https://pandoc.org/MANUAL.html#pandocs-markdown' },
      { name: 'CommonMark', format: 'commonmark', help: 'https://commonmark.org' },
      { name: 'GitHub Flavored Markdown', format: 'gfm', help: 'https://help.github.com/en/categories/writing-on-github' },
      { name: 'MultiMarkdown', format: 'markdown_mmd', help: 'https://fletcherpenney.net/multimarkdown' },
      { name: 'Plain Markdown', format: 'markdown_strict', help: 'https://daringfireball.net/projects/markdown' },
    ].freeze

    def present(parent)
      window.transient_for = parent
      window.present
    end

    private

      def settings = Settings.instance

      def window
        @window ||= Adwaita::PreferencesWindow.new.tap do |win|
          win.default_height = 380
          win.search_enabled = false
          win.add(page)

          settings.bind('autohide-headerbar', autohide_headerbar_switch, 'active')
          settings.bind('bigger-text', bigger_text_switch, 'active')

          current_index = FORMATS.index { |format| format.fetch(:format) == settings.input_format } || 0
          input_format_comborow.selected = current_index
          input_format_comborow.signal_connect('notify::selected') { on_input_format }
        end
      end

      def page
        @page ||= Adwaita::PreferencesPage.new.tap { |p| p.add(group) }
      end

      def group
        @group ||= Adwaita::PreferencesGroup.new.tap do |g|
          g.add(autohide_headerbar_row)
          g.add(bigger_text_row)
          g.add(input_format_comborow)
        end
      end

      def autohide_headerbar_row
        @autohide_headerbar_row ||= Adwaita::ActionRow.new.tap do |row|
          row.title = _('Autohide headerbar')
          row.subtitle = _('Autohide header and statusbars while typing')
          row.activatable_widget = autohide_headerbar_switch
          row.add_suffix(autohide_headerbar_switch)
        end
      end

      def autohide_headerbar_switch = @autohide_headerbar_switch ||= Gtk::Switch.new.tap { |s| s.valign = :center }

      def bigger_text_row
        @bigger_text_row ||= Adwaita::ActionRow.new.tap do |row|
          row.title = _('Use bigger text')
          row.subtitle = _('Reduce the margins width and increase the text size when possible')
          row.activatable_widget = bigger_text_switch
          row.add_suffix(bigger_text_switch)
        end
      end

      def bigger_text_switch = @bigger_text_switch ||= Gtk::Switch.new.tap { |s| s.valign = :center }

      def input_format_comborow
        @input_format_comborow ||= Adwaita::ComboRow.new.tap do |row|
          row.title = _('Input format')
          row.subtitle = _('Flavor of markdown Apostrophe will use')
          row.model = Gtk::StringList.new(FORMATS.map { |format| format.fetch(:name) })
          row.add_suffix(input_format_help_button)
        end
      end

      def input_format_help_button
        @input_format_help_button ||= Gtk::Button.new.tap do |button|
          button.valign = :center
          button.icon_name = 'dialog-information-symbolic'
          button.tooltip_text = _('Markdown flavor documentation')
          button.add_css_class('flat')
          button.add_css_class('circular')
          button.signal_connect('clicked') { on_input_format_help }
        end
      end

      def on_input_format
        FORMATS[input_format_comborow.selected]&.then do |format|
          settings.input_format = format.fetch(:format)
        end
      end

      def on_input_format_help
        FORMATS[input_format_comborow.selected]&.then do |format|
          Gtk.show_uri(window, format.fetch(:help), Gdk::CURRENT_TIME)
        end
      end
  end
end
