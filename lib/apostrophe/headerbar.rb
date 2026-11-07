# frozen_string_literal: true

require 'adwaita'
require_relative 'helpers'
require_relative 'open_popover'
require_relative 'theme_switcher'

module Apostrophe
  # HeaderBar assembles the window's title bar: the new-document and open
  # buttons at the start, the save split-button (whose attached menu holds
  # the export actions) and, at the end, the focus-mode and Hemingway
  # toggles, the main menu and the find toggle.
  #
  # Ported from apostrophe/headerbars.py (BaseHeaderbar) and
  # data/ui/Headerbar.ui. The preview-layout switcher and the
  # exit-fullscreen button upstream packs here are left out: both belong to
  # the preview pipeline, which this round cannot build (the dev shell has
  # no WebKit binding).
  #
  # Every action referenced by name here (`app.new_window`, `win.save`,
  # `win.open_file`, …) is installed by Application or MainWindow; a
  # GtkMenuButton/GtkButton with an action name that does not exist yet is
  # simply insensitive, which is how upstream's own `app.preferences` item
  # behaves on the port today.
  class HeaderBar
    def build
      bar.tap do |headerbar|
        headerbar.pack_start(new_button)
        headerbar.pack_start(open_button)
        headerbar.pack_start(save_button)

        headerbar.pack_end(menu_button)
        headerbar.pack_end(find_button)
        headerbar.pack_end(focus_mode_button)
        headerbar.pack_end(hemingway_button)

        open_button.tap { |button| button.popover = open_popover.build }

        menu_button.tap do |button|
          button.menu_model = menu_model
          popover = button.popover
          if popover
            popover.add_child(theme_switcher.build, 'themeswitcher')
          end
        end
      end
    end

    def open_popover_object = open_popover

    def open_button = @open_button ||= Gtk::MenuButton.new.tap { |button| button.label = 'Open' }
    def menu_button = @menu_button ||= Gtk::MenuButton.new
    def focus_mode_button = @focus_mode_button ||= toggle_button('focus-windows-symbolic', 'Focus Mode')
    def hemingway_button = @hemingway_button ||= toggle_button('edit-delete-symbolic', 'Hemingway Mode')
    def theme_switcher = @theme_switcher ||= ThemeSwitcher.new

    private

      def bar
        @bar ||= Adwaita::HeaderBar.new.tap do |headerbar|
          headerbar.add_css_class('titlebar')
        end
      end

      def new_button
        @new_button ||= Gtk::Button.new.tap do |button|
          button.tooltip_text = 'New'
          button.action_name = 'app.new_window'
          button.icon_name = 'document-new-symbolic'
        end
      end

      def save_button
        @save_button ||= Adwaita::SplitButton.new.tap do |button|
          button.label = 'Save'
          button.action_name = 'win.save'
          button.menu_model = export_menu_model
        end
      end

      def find_button
        @find_button ||= Gtk::ToggleButton.new.tap do |button|
          button.tooltip_text = 'Find'
          button.action_name = 'win.find'
          button.icon_name = 'system-search-symbolic'
        end
      end

      def toggle_button(icon_name, tooltip)
        Gtk::ToggleButton.new.tap do |button|
          button.icon_name = icon_name
          button.tooltip_text = tooltip
        end
      end

      def open_popover = @open_popover ||= OpenPopover.new

      # The main menu, ported item-for-item from Headerbar.ui's `Menu`.
      def menu_model
        @menu_model ||= Gio::Menu.new.tap do |menu|
          menu.append_section(nil, theme_switcher_section)
          menu.append_section(nil, hemingway_and_focus_section)
          menu.append_section(nil, Gio::Menu.new.tap { |s| s.append('Find and Replace', 'win.find_replace') })
          menu.append_section(nil, Gio::Menu.new.tap { |s| s.append('Preferences', 'app.preferences') })
          menu.append_section(nil, help_section)
        end
      end

      def theme_switcher_section
        Gio::Menu.new.tap do |section|
          item = Gio::MenuItem.new(nil, nil)
          item.set_attribute_value('custom', GLib::Variant.new('themeswitcher'))
          section.append_item(item)
        end
      end

      def hemingway_and_focus_section
        Gio::Menu.new.tap do |section|
          section.append('Hemingway Mode', 'win.hemingway_mode')
          section.append('Focus Mode', 'win.focus_mode')
        end
      end

      def help_section
        Gio::Menu.new.tap do |section|
          section.append_item(tutorial_item)
          section.append('Keyboard Shortcuts', 'app.shortcuts')
          section.append('About Apostrophe', 'app.about')
        end
      end

      # Upstream's "Open Tutorial" item targets a GResource path; the port
      # ships its media directly under lib/apostrophe/resources instead, so
      # the target is the plain file path Helpers.media_path resolves.
      def tutorial_item
        Gio::MenuItem.new('Open Tutorial', nil).tap do |item|
          item.set_action_and_target_value(
            'win.open_file',
            GLib::Variant.new("file://#{Helpers.media_path('apostrophe_markdown.md')}"),
          )
        end
      end

      # The export menu attached to the save split-button, ported item-for-item
      # from Headerbar.ui's `export_menu`.
      def export_menu_model
        @export_menu_model ||= Gio::Menu.new.tap do |menu|
          menu.append_section(nil, Gio::Menu.new.tap { |s| s.append('Save As…', 'win.save_as') })
          menu.append_section(nil, quick_export_section)
          menu.append_section(nil, Gio::Menu.new.tap { |s| s.append('Advanced Export…', 'win.advanced_export') })
          menu.append_section(nil, Gio::Menu.new.tap { |s| s.append('Copy HTML', 'win.copy_html') })
        end
      end

      def quick_export_section
        Gio::Menu.new.tap do |section|
          %w[pdf html odt].each do |key|
            item = Gio::MenuItem.new(key.upcase, nil)
            item.set_action_and_target_value('win.export', GLib::Variant.new(key))
            section.append_item(item)
          end
        end
      end
  end
end
