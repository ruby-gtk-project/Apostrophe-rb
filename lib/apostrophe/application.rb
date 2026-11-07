# frozen_string_literal: true

require 'gtk4'
require 'adwaita'

require_relative 'about_dialog'
require_relative 'helpers'
require_relative 'hemingway_dialog'
require_relative 'inhibitor'
require_relative 'main_window'
require_relative 'settings'
require_relative 'shortcuts_window'
require_relative 'style'

module Apostrophe
  # The port's application: it owns the GApplication itself, the windows it
  # opens and the four actions that only make sense at that level — opening
  # another window, quitting, the keyboard-shortcuts cheat sheet and the
  # about dialog. Everything about one open document — the editor, the
  # header bar, opening and saving — belongs to MainWindow.
  #
  # Ported from apostrophe/application.py. `do_open`'s empty-window reuse and
  # the command-line `--verbose` option are left out: nothing in this port
  # yet calls `app.open` with a file list, so there is no multi-file open to
  # route, and there is no logger to turn verbose.
  class Application
    def build
      app.tap do
        app.signal_connect('activate') { on_activate }
      end
    end

    def run(argv = []) = app.run(argv)

    # Adwaita::Application is broken in the Ruby bindings; the application
    # object comes from Gtk and only the window is Adwaita.
    def app = @app ||= Gtk::Application.new('org.rubygtkproject.Apostrophe', :default_flags)

    def inhibitor = @inhibitor ||= Inhibitor.new
    def settings = Settings.instance
    def style = Style.instance
    def shortcuts_window = @shortcuts_window ||= ShortcutsWindow.new
    def about_dialog = @about_dialog ||= AboutDialog.new
    def hemingway_dialog = @hemingway_dialog ||= HemingwayDialog.new

    def windows = @windows ||= []

    # The window the drive script and every other single-window caller
    # means by "the" window: the one `activate` opened first.
    def main_window = windows.first

    # The forwarded accessors below exist so a single-window caller (the
    # drive script, chiefly) can keep reaching the editor's pieces straight
    # off the application the way it could before MainWindow existed.
    def window = main_window.window
    def header_bar = main_window.header_bar
    def menu_button = main_window.menu_button
    def focus_mode_button = main_window.focus_mode_button
    def hemingway_button = main_window.hemingway_button
    def stats_button = main_window.stats_button
    def theme_switcher = main_window.theme_switcher
    def text_view = main_window.text_view
    def text_buffer = main_window.text_buffer
    def search_bar = main_window.search_bar
    def markup_handler = main_window.markup_handler
    def format_inserter = main_window.format_inserter
    def fix_table = main_window.fix_table
    def scroller = main_window.scroller
    def stats_handler = main_window.stats_handler
    def document = main_window.document

    private

      # Forwarded (rather than public) because the single caller that reaches
      # for it directly — the drive script — already does so through `send`,
      # the same way it reached the editor's own private `toggle_search`
      # before MainWindow existed.
      def toggle_search = main_window.send(:toggle_search)

      def on_activate
        style.build
        install_app_actions
        open_new_window.present
      end

      def install_app_actions
        install_app_action('new_window') { open_new_window.present }
        install_app_action('quit') { quit }
        install_app_action('shortcuts') { shortcuts_window.present(main_window.window) }
        install_app_action('about') { about_dialog.present(main_window.window) }
        app.set_accels_for_action('app.new_window', ['<Control>n'])
        app.set_accels_for_action('app.quit', ['<Control>q'])
      end

      def install_app_action(name, &block)
        Gio::SimpleAction.new(name).tap do |action|
          action.signal_connect('activate') { block.call }
          app.add_action(action)
        end
      end

      def open_new_window
        main = MainWindow.new(
          app,
          inhibitor:        inhibitor,
          hemingway_dialog: hemingway_dialog,
          on_closed:        -> { windows.delete(main) },
        )
        main.tap do |window|
          window.build
          windows.push(window)
        end
      end

      # Upstream's Application.on_quit: ask every open window to check for
      # unsaved changes before actually quitting; a window with nothing
      # unsaved closes immediately, one that does opens its own prompt and
      # quitting continues once every window is gone.
      def quit
        windows.dup.each { |main| main.window.close }
      end
  end
end
