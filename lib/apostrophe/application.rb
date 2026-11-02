# frozen_string_literal: true

require "gtk4"
require "adwaita"

require_relative "document"
require_relative "fix_table"
require_relative "format_inserter"
require_relative "helpers"
require_relative "inhibitor"
require_relative "markup_handler"
require_relative "settings"
require_relative "stats_counter"
require_relative "style"
require_relative "text_buffer"
require_relative "text_view_scroller"
require_relative "theme_switcher"

module Apostrophe
  # The port's application: the editor, with live markdown highlighting, the
  # markdown insertion shortcuts, Hemingway and focus modes, the statistics
  # counter and the colour-scheme switcher in the main menu.
  #
  # Ported from apostrophe/application.py. The window's own chrome — the
  # discard infobar, the save progress bar, the file choosers and the preview
  # pane — belongs to MainWindow upstream, and the editor widget's own
  # behaviour (its drop target, its scroll-scale property, its margins) to
  # ApostropheTextView; until those files exist in the port, the editor is
  # assembled here so everything that is ported is reachable from the app.
  #
  # House style (see .claude/skills/ruby-gtk): every widget is a memoized
  # method, all configuration lives in its `tap`, assembly happens only in
  # `build`, and the launcher is one expression.
  class Application
    # Upstream's TextView.ui carries these as GtkShortcuts on the view; here
    # they are window actions with accelerators, which is the same binding
    # without a .ui file to parse.
    SHORTCUTS = {
      "insert-italic"        => "<Control>i",
      "insert-bold"          => "<Control>b",
      "insert-hrule"         => "<Control>r",
      "insert-listitem"      => "<Control>u",
      "insert-strikethrough" => "<Control><Shift>d",
      "insert-header-1"      => "<Control>1",
      "insert-header-2"      => "<Control>2",
      "insert-header-3"      => "<Control>3",
      "insert-header-4"      => "<Control>4",
      "unindent"             => "<Shift>ISO_Left_Tab",
      "fix-table"            => "<Control>t",
    }.freeze

    def build
      app.tap do
        app.signal_connect("activate") do
          style.build

          window.tap do |win|
            win.content = toast_overlay
          end

          toast_overlay.tap do |overlay|
            overlay.child = toolbar_view
          end

          toolbar_view.tap do |view|
            view.add_top_bar(header_bar)
            view.content = editor_scrolled_window
          end

          header_bar.tap do |bar|
            bar.pack_start(focus_mode_button)
            bar.pack_start(hemingway_button)
            bar.pack_end(menu_button)
            bar.pack_end(stats_label)

            menu_button.tap do |button|
              button.popover = menu_popover
            end

            menu_popover.tap do |popover|
              popover.child = theme_switcher.build
            end

            focus_mode_button.signal_connect("toggled") { on_focus_mode_toggled }
            hemingway_button.signal_connect("toggled") { on_hemingway_toggled }
          end

          editor_scrolled_window.tap do |scrolled|
            scrolled.child = text_view

            # The editor's margins, indents and tab stops are all measured in
            # characters of its font, so they are recomputed whenever the view
            # is laid out again — which is when the adjustment changes.
            scrolled.vadjustment.signal_connect("changed") do
              markup_handler.update_margins_indents
            end
          end

          text_view.tap do |view|
            view.buffer = text_buffer
          end

          text_buffer.tap do |buffer|
            buffer.signal_connect("changed") { on_text_changed }
            buffer.signal_connect("mark-set") { |_buffer, _location, mark| on_mark_set(mark) }
          end

          install_actions
          markup_handler
          style.on_change { markup_handler.on_style_updated }

          on_text_changed
          window.present
        end
      end
    end

    def run(argv = []) = app.run(argv)

    # Adwaita::Application is broken in the Ruby bindings; the application
    # object comes from Gtk and only the window is Adwaita.
    def app = @app ||= Gtk::Application.new("org.rubygtkproject.Apostrophe", :default_flags)

    def window
      @window ||= Adwaita::ApplicationWindow.new(app).tap do |win|
        win.title = document.title
        win.set_default_size(800, 600)
        win.add_css_class("apostrophe-window")
      end
    end

    def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new
    def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
    def header_bar = @header_bar ||= Adwaita::HeaderBar.new

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = "open-menu-symbolic"
        button.tooltip_text = "Main Menu"
      end
    end

    def menu_popover = @menu_popover ||= Gtk::Popover.new

    def focus_mode_button
      @focus_mode_button ||= Gtk::ToggleButton.new.tap do |button|
        button.icon_name = "focus-windows-symbolic"
        button.tooltip_text = "Focus Mode"
      end
    end

    def hemingway_button
      @hemingway_button ||= Gtk::ToggleButton.new.tap do |button|
        button.icon_name = "edit-delete-symbolic"
        button.tooltip_text = "Hemingway Mode"
        button.active = settings.hemingway_mode?
      end
    end

    def stats_label
      @stats_label ||= Gtk::Label.new("0 Words").tap do |label|
        label.add_css_class("stats-button")
        label.margin_end = 6
      end
    end

    def editor_scrolled_window
      @editor_scrolled_window ||= Gtk::ScrolledWindow.new.tap do |scrolled|
        scrolled.hscrollbar_policy = :never
        scrolled.vexpand = true
      end
    end

    def text_view
      @text_view ||= Gtk::TextView.new.tap do |view|
        view.add_css_class("apostrophe-editor")
        view.wrap_mode = :word_char
        view.left_margin = 24
        view.right_margin = 24
        view.top_margin = 24
        view.bottom_margin = 24
        view.monospace = true
      end
    end

    def text_buffer
      @text_buffer ||= TextBuffer.new(on_attempted_hemingway: -> { on_attempted_hemingway })
    end

    def markup_handler = @markup_handler ||= MarkupHandler.new(text_view)
    def format_inserter = @format_inserter ||= FormatInserter.new
    def fix_table = @fix_table ||= FixTable.new(text_buffer)
    def scroller = @scroller ||= TextViewScroller.new(text_view, editor_scrolled_window)
    def inhibitor = @inhibitor ||= Inhibitor.new
    def document = @document ||= Document.new
    def settings = Settings.instance
    def style = Style.instance
    def theme_switcher = @theme_switcher ||= ThemeSwitcher.new

    def stats_counter
      @stats_counter ||= StatsCounter.new { |result| on_counted(result) }
    end

    private

      def install_actions
        SHORTCUTS.each_key do |name|
          Gio::SimpleAction.new(name).tap do |action|
            action.signal_connect("activate") { dispatch(name) }
            window.add_action(action)
          end
          app.set_accels_for_action("win.#{name}", [SHORTCUTS.fetch(name)])
        end
      end

      def dispatch(name)
        case name
        when "insert-italic" then format_inserter.insert_italic(text_view)
        when "insert-bold" then format_inserter.insert_bold(text_view)
        when "insert-hrule" then format_inserter.insert_horizontal_rule(text_view)
        when "insert-listitem" then format_inserter.insert_list_item(text_view)
        when "insert-strikethrough" then format_inserter.insert_strikethrough(text_view)
        when "unindent" then text_buffer.unindent
        when "fix-table" then fix_table.fix_table
        else format_inserter.insert_header(text_view, name.split("-").last.to_i)
        end
      end

      # Every edit re-highlights, re-counts, scrolls the cursor back into view
      # and marks the document dirty, which is what holds the logout inhibitor
      # open until it is saved.
      def on_text_changed
        markup_handler.apply
        stats_counter.count(buffer_text)
        smooth_scroll_to_cursor
        inhibitor.inhibit(:logout)
      end

      # Upstream only scrolls when the cursor was moved from the keyboard,
      # which is what the selection_bound mark without a selection stands for.
      def on_mark_set(mark)
        if mark.name == "selection_bound" && !text_buffer.has_selection?
          markup_handler.apply
          smooth_scroll_to_cursor
        end
      end

      # Deferred to the main loop the way upstream defers it: the scroll has to
      # be computed after the view has re-laid out around the new text.
      def smooth_scroll_to_cursor
        GLib::Idle.add do
          scroller.smooth_scroll_to_mark(text_buffer.get_mark("insert"), markup_handler.focus_mode)
          false
        end
      end

      def on_counted(result)
        stats_label.text = "#{result.words} Words"
      end

      def on_focus_mode_toggled
        markup_handler.focus_mode = focus_mode_button.active?
        markup_handler.apply
      end

      def on_hemingway_toggled
        hemingway_button.active?.then do |active|
          text_buffer.hemingway_mode = active
          settings.hemingway_mode = active
        end
      end

      # Upstream counts the attempts and offers the explainer dialog after a
      # few in quick succession; until that dialog is ported, the toast it
      # shows alongside is what tells the user why the deletion did nothing.
      def on_attempted_hemingway
        toast_overlay.add_toast(Adwaita::Toast.new("Hemingway Mode is on; text cannot be deleted"))
      end

      def buffer_text
        text_buffer.get_text(text_buffer.start_iter, text_buffer.end_iter, false)
      end
  end
end
