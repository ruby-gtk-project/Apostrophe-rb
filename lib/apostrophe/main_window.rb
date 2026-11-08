# frozen_string_literal: true

require 'gtk4'
require 'adwaita'
require_relative 'advanced_export_dialog'
require_relative 'document'
require_relative 'export_dialog'
require_relative 'fix_table'
require_relative 'format_inserter'
require_relative 'headerbar'
require_relative 'helpers'
require_relative 'inline_preview'
require_relative 'markup_handler'
require_relative 'preview_layout_switcher'
require_relative 'preview_renderer'
require_relative 'search_bar'
require_relative 'settings'
require_relative 'stats_handler'
require_relative 'text_view'
require_relative 'text_view_scroller'

module Apostrophe
  # MainWindow is the application's real window: the editor, the header bar,
  # the search bar and the statistics button it already had, plus the file
  # lifecycle upstream's window owns — opening, saving, the unsaved-changes
  # prompt, the "file changed on disk" infobar and the save progress bar.
  #
  # Ported from apostrophe/main_window.py and data/ui/Window.ui. Left out:
  # the preview flap/stack (the preview pipeline needs a WebKit binding this
  # dev shell does not have) and fullscreen handling (upstream's is entirely
  # about hiding/showing the preview's chrome, which does not exist here).
  class MainWindow
    Helpers.bind_gettext(self)

    # Upstream's TextView.ui carries these as GtkShortcuts on the view; here
    # they are window actions with accelerators, which is the same binding
    # without a .ui file to parse.
    SHORTCUTS = {
      'insert-italic'        => '<Control>i',
      'insert-bold'          => '<Control>b',
      'insert-hrule'         => '<Control>r',
      'insert-listitem'      => '<Control>u',
      'insert-strikethrough' => '<Control><Shift>d',
      'insert-header-1'      => '<Control>1',
      'insert-header-2'      => '<Control>2',
      'insert-header-3'      => '<Control>3',
      'insert-header-4'      => '<Control>4',
      'unindent'             => '<Shift>ISO_Left_Tab',
      'fix-table'            => '<Control>t',
    }.freeze

    attr_reader :document

    def initialize(app, inhibitor:, hemingway_dialog:, on_closed: nil)
      @app = app
      @inhibitor = inhibitor
      @hemingway_dialog = hemingway_dialog
      @on_closed = on_closed
      @document = Document.new
      @did_change = false
      @file_monitor = nil
    end

    def build
      window.tap do |win|
        win.content = toast_overlay
      end

      toast_overlay.tap { |overlay| overlay.child = chrome_box }

      chrome_box.tap do |box|
        box.append(header_bar)
        box.append(discard_infobar)
        box.append(save_progressbar)
        box.append(flap)
      end

      flap.tap { |f| f.content = editor_overlay }

      editor_overlay.tap do |overlay|
        overlay.child = editor_scrolled_window
        overlay.add_overlay(search_bar.build)
        overlay.add_overlay(stats_revealer)
      end

      preview_layout_switcher.on_layout_changed = ->(value) { preview_renderer.preview_layout = value }
      preview_renderer.preview_layout = preview_layout_switcher.preview_layout
      preview_renderer.load_content(preview_placeholder)
      preview_toggle_button.signal_connect('notify::active') { on_preview_toggled }

      editor_scrolled_window.tap do |scrolled|
        scrolled.child = text_view

        # The editor's margins, indents and tab stops are all measured in
        # characters of its font, so they are recomputed whenever the view
        # is laid out again — which is when the adjustment changes.
        scrolled.vadjustment.signal_connect('changed') { markup_handler.update_margins_indents }
      end

      text_view.scroller = scroller

      text_buffer.tap do |buffer|
        buffer.signal_connect('changed') { on_text_changed }
        buffer.signal_connect('mark-set') { |_buffer, _location, mark| on_mark_set(mark) }
      end

      stats_handler
      install_actions
      markup_handler
      inline_preview
      style.on_change { markup_handler.on_style_updated }

      update_title
      on_text_changed_quietly

      window
    end

    def present = window.present

    def window
      @window ||= Adwaita::ApplicationWindow.new(@app).tap do |win|
        win.set_default_size(1000, 600)
        win.add_css_class('apostrophe-window')
        win.signal_connect('close-request') { do_close_request }
      end
    end

    def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new
    def chrome_box = @chrome_box ||= Gtk::Box.new(:vertical, 0)
    def header_bar_assembly = @header_bar_assembly ||= HeaderBar.new
    def header_bar = @header_bar ||= header_bar_assembly.build

    def menu_button = header_bar_assembly.menu_button
    def focus_mode_button = header_bar_assembly.focus_mode_button
    def hemingway_button = header_bar_assembly.hemingway_button
    def theme_switcher = header_bar_assembly.theme_switcher

    def stats_button
      @stats_button ||= Gtk::MenuButton.new.tap do |button|
        button.add_css_class('stats-button')
        button.always_show_arrow = true
        button.tooltip_text = _('Show Statistics')
      end
    end

    # The stats button's own overlay slot, from Window.ui's `stats_revealer`:
    # bottom-right, revealed from the start.
    def stats_revealer
      @stats_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.valign = :end
        revealer.halign = :end
        revealer.transition_type = :crossfade
        revealer.transition_duration = 750
        revealer.reveal_child = true
        revealer.child = stats_button.tap do |button|
          button.halign = :end
          button.margin_end = 6
          button.margin_bottom = 6
        end
      end
    end

    def editor_overlay = @editor_overlay ||= Gtk::Overlay.new

    # The preview's flap: PreviewRenderer folds the editor over for the
    # full-width layout, splits it for half-width/half-height, or empties
    # this out entirely for the windowed layout.
    def flap = @flap ||= Adwaita::Flap.new

    def preview_stack = @preview_stack ||= Gtk::Stack.new

    def preview_layout_switcher = header_bar_assembly.preview_layout_switcher
    def preview_toggle_button = preview_layout_switcher.toggle_button_object

    def preview_renderer
      @preview_renderer ||= PreviewRenderer.new(
        window:             window,
        text_view:          text_view,
        flap:               flap,
        preview_stack:      preview_stack,
        on_windowed_closed: -> { preview_toggle_button.active = false },
      )
    end

    # The preview's content. Upstream renders the document's own markdown to
    # HTML in a WebKit WebView; this dev shell has no WebKit binding for GTK4
    # (see preview_handler.rb and preview_web_view.rb for why those two stay
    # unported), so this placeholder stands in for it. Everything around it
    # — the layout switcher, the flap and its resize animations, the
    # detached preview window — is fully wired and works.
    def preview_placeholder
      @preview_placeholder ||= Gtk::Label.new(
        _('Preview needs a WebKit binding this build does not have.') + "\n\n" + _('The layout (full-width, half-width, half-height, windowed) still works.'),
      ).tap do |label|
        label.wrap = true
        label.justify = :center
        label.margin_start = 24
        label.margin_end = 24
      end
    end

    def editor_scrolled_window
      @editor_scrolled_window ||= Gtk::ScrolledWindow.new.tap do |scrolled|
        scrolled.hscrollbar_policy = :never
        scrolled.vexpand = true
      end
    end

    def text_view
      @text_view ||= TextView.new(on_attempted_hemingway: -> { on_attempted_hemingway })
    end

    def text_buffer = text_view.text_buffer
    def search_bar = @search_bar ||= SearchBar.new(text_view)

    def markup_handler = @markup_handler ||= MarkupHandler.new(text_view)
    def inline_preview = @inline_preview ||= InlinePreview.new(text_view)
    def format_inserter = @format_inserter ||= FormatInserter.new
    def fix_table = @fix_table ||= FixTable.new(text_buffer)
    def scroller = @scroller ||= TextViewScroller.new(text_view, editor_scrolled_window)
    def settings = Settings.instance
    def style = Style.instance
    def stats_handler = @stats_handler ||= StatsHandler.new(stats_button, text_view)

    def did_change? = @did_change

    # The "file changed on disk" warning from Window.ui, revealed by the file
    # monitor and dismissed either by its own close button or by reloading.
    def discard_infobar
      @discard_infobar ||= Gtk::InfoBar.new.tap do |infobar|
        infobar.message_type = :warning
        infobar.show_close_button = true
        infobar.revealed = false
        infobar.signal_connect('response') { |_bar, response| dismiss_discard_infobar(response) }

        infobar.add_child(discard_infobar_label_box)
        infobar.add_action_widget(discard_button, 0)
      end
    end

    def save_progressbar
      @save_progressbar ||= Gtk::ProgressBar.new.tap do |bar|
        bar.visible = false
        bar.add_css_class('osd')
      end
    end

    private

      def discard_infobar_label_box
        Gtk::Box.new(:vertical, 2).tap do |box|
          box.append(discard_infobar_title)
          box.append(discard_infobar_subtitle)
        end
      end

      def discard_infobar_title
        Gtk::Label.new(_('File Has Changed on Disk')).tap do |label|
          label.halign = :start
          label.wrap = true
          label.add_css_class('heading')
        end
      end

      def discard_infobar_subtitle
        Gtk::Label.new(_('The file has been changed by another program.')).tap do |label|
          label.halign = :start
          label.wrap = true
        end
      end

      def discard_button
        Gtk::Button.new.tap do |button|
          button.label = _('Discard Changes and Reload')
          button.use_underline = true
          button.signal_connect('clicked') { reload_file }
        end
      end

      def progressbar_fade_out
        @progressbar_fade_out ||= Adwaita::TimedAnimation.new(

          save_progressbar,

          1,

          0,

          500,
          Adwaita::PropertyAnimationTarget.new(save_progressbar, 'opacity'),

        ).tap do |anim|
          anim.set_easing(:ease_out_cubic)
          anim.signal_connect('done') { save_progressbar.visible = false }
        end
      end

      def progressbar_animation
        @progressbar_animation ||= Adwaita::TimedAnimation.new(

          save_progressbar,

          0,

          1,

          300,
          Adwaita::PropertyAnimationTarget.new(save_progressbar, 'fraction'),

        ).tap do |anim|
          anim.signal_connect('done') { progressbar_fade_out.play }
        end
      end

      def install_actions
        install_markdown_shortcuts
        install_window_action('find', accel: '<Control>f') { toggle_search }
        install_window_action('find_replace', accel: '<Control>h') { search_bar.replace_mode_enabled = true }
        install_property_action('focus_mode', focus_mode_button, 'active', accel: '<Control>d')
        install_property_action('hemingway_mode', hemingway_button, 'active', accel: '<Control>t')
        install_property_action('preview', preview_toggle_button, 'active', accel: '<Control>p')
        focus_mode_button.signal_connect('toggled') { on_focus_mode_toggled }
        hemingway_button.signal_connect('toggled') { on_hemingway_toggled }

        install_window_action('new') { new_document }
        install_window_action('open', accel: '<Control>o') { open_document }
        install_window_action_with_string('open_file') { |uri| open_from_uri(uri) }
        install_window_action('save', accel: '<Control>s') { save_document }
        install_window_action('save_as', accel: '<Shift><Control>s') { save_document_as }
        install_window_action_with_string('export') { |format_key| open_export(format_key) }
        install_window_action('advanced_export') { open_advanced_export }
        install_window_action('copy_html') { copy_html_to_clipboard }
        install_window_action('close', accel: '<Control>w') { do_close_request }
      end

      def install_markdown_shortcuts
        SHORTCUTS.each_key do |name|
          Gio::SimpleAction.new(name).tap do |action|
            action.signal_connect('activate') { dispatch(name) }
            window.add_action(action)
          end
          @app.set_accels_for_action("win.#{name}", [SHORTCUTS.fetch(name)])
        end
      end

      def install_window_action(name, accel: nil, &block)
        Gio::SimpleAction.new(name).tap do |action|
          action.signal_connect('activate') { block.call }
          window.add_action(action)
        end
        @app.set_accels_for_action("win.#{name}", [accel]) if accel
      end

      def install_window_action_with_string(name, &block)
        Gio::SimpleAction.new(name, GLib::VariantType.new('s')).tap do |action|
          action.signal_connect('activate') { |_action, parameter| block.call(parameter) }
          window.add_action(action)
        end
      end

      def install_property_action(name, object, property, accel: nil)
        window.add_action(Gio::PropertyAction.new(name, object, property))
        @app.set_accels_for_action("win.#{name}", [accel]) if accel
      end

      def toggle_search
        search_bar.search_mode_enabled = !search_bar.search_mode_enabled
      end

      def dispatch(name)
        case name
        when 'insert-italic' then format_inserter.insert_italic(text_view)
        when 'insert-bold' then format_inserter.insert_bold(text_view)
        when 'insert-hrule' then format_inserter.insert_horizontal_rule(text_view)
        when 'insert-listitem' then format_inserter.insert_list_item(text_view)
        when 'insert-strikethrough' then format_inserter.insert_strikethrough(text_view)
        when 'unindent' then text_buffer.unindent
        when 'fix-table' then fix_table.fix_table
        else format_inserter.insert_header(text_view, name.split('-').last.to_i)
        end
      end

      # Every edit re-highlights, scrolls the cursor back into view and marks
      # the document dirty, which is what holds the logout inhibitor open
      # until it is saved.
      def on_text_changed
        unless @did_change
          @did_change = true
          update_title
          @inhibitor.inhibit(:logout)
        end
        markup_handler.apply
        smooth_scroll_to_cursor
      end

      # The pieces of on_text_changed that must run once at startup
      # (highlighting an initial buffer) without marking the brand-new,
      # unmodified document as changed.
      def on_text_changed_quietly
        markup_handler.apply
      end

      # Upstream only scrolls when the cursor was moved from the keyboard,
      # which is what the selection_bound mark without a selection stands for.
      def on_mark_set(mark)
        if mark.name == 'selection_bound' && !text_buffer.has_selection?
          markup_handler.apply
          smooth_scroll_to_cursor
        end
      end

      # Deferred to the main loop the way upstream defers it: the scroll has to
      # be computed after the view has re-laid out around the new text.
      def smooth_scroll_to_cursor
        GLib::Idle.add do
          scroller.smooth_scroll_to_mark(text_buffer.get_mark('insert'), markup_handler.focus_mode)
          false
        end
      end

      def on_focus_mode_toggled
        focus_mode_button.active?.then do |active|
          markup_handler.focus_mode = active
          text_view.focus_mode = active
          text_view.update_vertical_margin
        end
        markup_handler.apply
      end

      def on_hemingway_toggled
        hemingway_button.active?.then do |active|
          text_buffer.hemingway_mode = active
          settings.hemingway_mode = active
        end
      end

      # Upstream's on_attempted_hemingway: every attempted deletion is logged,
      # and when four of them land within 70 seconds of each other the
      # explainer dialog is shown instead of the plain toast.
      def on_attempted_hemingway
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @hemingway_attempts = (@hemingway_attempts || [0, 0, 0, 0]).last(3) + [now]

        if now - @hemingway_attempts.first <= 70
          @hemingway_attempts = [0, 0, 0, 0]
          @hemingway_dialog.present(window)
        else
          toast_overlay.add_toast(Adwaita::Toast.new(_('Hemingway Mode is on; text cannot be deleted')))
        end
      end

      def update_title
        if @did_change
          prefix = '• '
        else
          prefix = ''
        end
        title = "#{prefix}#{document.title}"
        window.title = title
        if document.saved?
          header_bar.tooltip_text = document.path
        else
          header_bar.tooltip_text = ''
        end
      end

      # Upstream's save_document: writes the buffer to the current GFile,
      # falling back to save_document_as when there isn't one yet.
      def save_document
        if document.gfile
          write_current_file
        else
          save_document_as
        end
      end

      def write_current_file
        discard_infobar.revealed = false
        @file_monitor&.cancel
        save_progressbar.opacity = 1
        save_progressbar.visible = true
        progressbar_animation.play

        document.gfile.replace_contents_bytes_async(

          GLib::Bytes.new(encode_text.b),
          nil,
          false,
          :none,
          nil,

        ) { |gfile, result| on_save_finished(gfile, result) }
      end

      # We try the document's own encoding first and fall back to UTF-8,
      # the same two-step upstream's save_document takes.
      def encode_text
        text_view.text.encode(document.encoding)
      rescue EncodingError
        document.encoding = 'UTF-8'
        text_view.text.encode('UTF-8')
      end

      def on_save_finished(gfile, result)
        gfile.replace_contents_finish(result)
        @did_change = false
        update_title
        @inhibitor.uninhibit
        set_file_monitor
      rescue GLib::Error => e
        Helpers.show_error(window, e.message)
        set_file_monitor
      end

      def save_document_as
        chooser = Gtk::FileChooserNative.new(
          _('Save your File'),
          window,
          :save,
          _('Save'),
          _('Cancel'),
        )
        chooser.add_filter(markdown_filter)
        if document.title.end_with?('.md')
          default_name = document.title
        else
          default_name = "#{document.title}.md"
        end
        chooser.current_name = default_name
        chooser.signal_connect('response') { |dialog, response| on_save_as_response(dialog, response) }
        chooser.show
      end

      def on_save_as_response(dialog, response)
        if response == :accept
          file = dialog.file
          unless file.query_exists
            file.create(:none)
          end
          document.gfile = file
          Gtk::RecentManager.default.add_item(document.uri)
          update_title
          save_document
        end
        dialog.destroy
      end

      def markdown_filter
        Gtk::FileFilter.new.tap do |filter|
          filter.add_mime_type('text/x-markdown')
          filter.add_mime_type('text/plain')
          filter.name = _('Markdown (.md)')
        end
      end

      def open_document
        menu_button.popdown
        header_bar_assembly.open_popover_object.popdown

        chooser = Gtk::FileChooserNative.new(
          _('Open a .md file'),
          window,
          :open,
          _('Open'),
          _('Cancel'),
        )
        chooser.add_filter(markdown_open_filter)
        chooser.add_filter(plaintext_filter)
        chooser.signal_connect('response') { |dialog, response| on_open_response(dialog, response) }
        chooser.show
      end

      def on_open_response(dialog, response)
        if response == :accept
          check_change { load_file(dialog.file) }
        end
        dialog.destroy
      end

      def markdown_open_filter
        Gtk::FileFilter.new.tap do |filter|
          filter.add_mime_type('text/markdown')
          filter.add_mime_type('text/x-markdown')
          filter.name = _('Markdown Files')
        end
      end

      def plaintext_filter
        Gtk::FileFilter.new.tap do |filter|
          filter.add_mime_type('text/plain')
          filter.name = _('Plain Text Files')
        end
      end

      def open_from_uri(uri)
        header_bar_assembly.open_popover_object.popdown
        check_change { load_file(Gio::File.new_for_uri(uri)) }
      end

      def load_file(file)
        document.gfile = file
        file.load_contents_async(nil) { |gfile, result| on_load_finished(gfile, result) }
        set_file_monitor
      end

      def on_load_finished(gfile, result)
        _ok, contents, _etag = gfile.load_contents_finish(result)
        decoded = decode_contents(contents.pack('C*'))
        text_view.text = decoded
        GLib::Idle.add do
          text_buffer.place_cursor(text_buffer.start_iter)
          false
        end

        unless document.uri.to_s.start_with?('resource:')
          Gtk::RecentManager.default.add_item(document.uri)
        end

        @did_change = false
        update_title
      rescue GLib::Error => e
        Helpers.show_error(window, e.message)
      end

      def decode_contents(bytes)
        document.encoding = 'UTF-8'
        bytes.force_encoding('UTF-8').then do |text|
          text.valid_encoding? ? text : fallback_decode(bytes)
        end
      end

      def fallback_decode(bytes)
        document.encoding = 'ISO-8859-1'
        bytes.force_encoding('ISO-8859-1').encode('UTF-8')
      end

      def set_file_monitor
        if document.gfile
          @file_monitor = document.gfile.monitor_file(:none, nil)
          @file_monitor.signal_connect('changed') { |*_args| discard_infobar.revealed = true }
        end
      end

      def reload_file
        discard_infobar.revealed = false
        load_file(document.gfile)
      end

      def dismiss_discard_infobar(response)
        if response == :close
          discard_infobar.revealed = false
        end
      end

      def new_document
        check_change do
          text_view.clear
          @did_change = false
          document.gfile = nil
          update_title
        end
      end

      def copy_html_to_clipboard
        window.clipboard.set(Helpers.pandoc_convert(text_view.text))
      rescue RuntimeError => e
        Helpers.show_error(window, e.message)
      end

      def open_export(format_key)
        ExportDialog.new(window, document).export(format_key, text_view.text)
      end

      def open_advanced_export
        AdvancedExportDialog.new(window, document, text_view.text).present
      end

      # Upstream's toggle_preview: a preview grabs focus away from the
      # editor when it is shown, and the renderer does the rest.
      def on_preview_toggled
        if preview_toggle_button.active?
          preview_renderer.show
        else
          preview_renderer.hide
        end
      end

      # Upstream's check_change: offers to save unsaved changes before running
      # `callback`, which does the work the caller actually wanted (opening
      # another file, clearing the buffer, closing the window).
      def check_change(&callback)
        if @did_change
          confirm_discard(&callback)
        else
          callback.call
        end
      end

      def confirm_discard(&callback)
        dialog = Adwaita::MessageDialog.new(
          window,
          _('Save changes?'),
          format(
            _('“%{title}” contains unsaved changes. If you don’t save, all your changes will be permanently lost.'),
            title: document.title,
          ),
        )
        dialog.add_response('cancel', _('Cancel'))
        dialog.add_response('close', _('Discard'))
        dialog.add_response('save', _('Save'))
        dialog.set_response_appearance('close', :destructive)
        dialog.set_response_appearance('save', :suggested)
        dialog.default_response = 'save'
        dialog.close_response = 'cancel'
        dialog.signal_connect('response') { |_d, response| on_discard_response(response, &callback) }
        dialog.present
      end

      def on_discard_response(response, &callback)
        case response
        when 'cancel' then nil
        when 'save' then save_then(&callback)
        else callback.call
        end
      end

      def save_then(&callback)
        save_document
        callback.call
      end

      # Upstream's do_close_request calls itself again once check_change's
      # callback decides the window may actually go, relying on GTK
      # re-emitting "close-request" for a second, real close. This binding's
      # `Gtk::Window#close` does not re-emit that signal from inside its own
      # handler, so the port destroys the window directly instead once it is
      # safe to, and always tells GTK it handled the request itself.
      def do_close_request
        check_change { really_close }
        true
      end

      def really_close
        window.destroy
        @on_closed&.call
      end
  end
end
