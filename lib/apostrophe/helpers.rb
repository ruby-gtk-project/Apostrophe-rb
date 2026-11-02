# frozen_string_literal: true

require 'adwaita'
require 'open3'
require 'shellwords'
require_relative 'rb/version'
require_relative 'settings'

module Apostrophe
  # Helpers are the odds and ends every other file reaches for: the running
  # application, the undoable-edit wrapper, the error dialog, the Pandoc call
  # and the debug-info block the about dialog shows.
  #
  # Ported from apostrophe/helpers.py. Upstream's logging setup is left out:
  # Python's `logging` module has no counterpart here, and the port's callers
  # raise or warn rather than write to a logger.
  module Helpers
    # Upstream's `__apostrophe_data_directory__` plus config.PKGDATA_DIR. The
    # port ships its data files beside lib/, so a media path resolves there.
    MEDIA_DIRECTORY = File.expand_path('resources', __dir__)

    module_function

    # Upstream's `App()` — Gio.Application.get_default.
    def app = Gio::Application.default

    # Upstream's `user_action` context manager: everything the block does to
    # the buffer collapses into a single undo step.
    def user_action(text_buffer)
      text_buffer.begin_user_action
      begin
        yield text_buffer
      ensure
        text_buffer.end_user_action
      end
    end

    # The full path of a file under the media directory, or nil when the port
    # does not ship it — the same contract as upstream's `get_media_path`.
    def media_path(path)
      File.join(MEDIA_DIRECTORY, path.delete_prefix('/')).then do |full|
        if File.exist?(full)
          full
        end
      end
    end

    def show_error(parent, message)
      Adwaita::MessageDialog.new(parent, 'Error', message).tap do |dialog|
        dialog.add_response('close', 'Close')
        dialog.close_response = 'close'
        dialog.present
      end
    end

    # Whether a command exists on PATH — upstream's `exist_executable`, used to
    # decide whether LaTeX export is available.
    def exist_executable?(command)
      ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |directory|
        File.executable?(File.join(directory, command))
      end
    end

    # A Gio::ListStore of Gtk::StringObject, the model the port's drop-downs
    # take. Upstream's `liststore_from_list`.
    def liststore_from_list(strings)
      Gio::ListStore.new(Gtk::StringObject.gtype).tap do |store|
        strings.each { |string| store.append(Gtk::StringObject.new(string)) }
      end
    end

    # The width of one character in the widget's font, in pixels. The markup
    # handler sizes every margin, indent and tab stop off this.
    def char_width(widget)
      Pango.units_to_double(
        widget.pango_context.get_metrics(nil, nil).approximate_char_width,
      )
    end

    # Runs Pandoc over `text`. Upstream calls pypandoc, which is itself a thin
    # wrapper around the `pandoc` executable, so the port shells out directly:
    # with an `outputfile` Pandoc writes the file and this returns an empty
    # string, otherwise the converted document comes back on stdout.
    #
    # Raises when Pandoc is missing or fails, which is what the export dialogs
    # and the preview pipeline report to the user.
    def pandoc_convert(text, to: 'html5', args: [], outputfile: nil)
      from = Settings.instance.input_format
      extra = args.dup
      if to == 'html5'
        extra << '--wrap=none'
      end
      if outputfile
        extra.push('--output', outputfile)
      end
      command = ['pandoc', '--from', from.empty? ? 'markdown' : from, '--to', to, *extra]
      Open3.capture3(*command, stdin_data: text).then do |stdout, stderr, status|
        unless status.success?
          raise "pandoc #{Shellwords.join(command[1..])} failed: #{stderr.strip}"
        end

        stdout
      end
    rescue Errno::ENOENT
      raise 'pandoc is not installed; Apostrophe needs it to preview and export documents'
    end

    def pandoc_version
      Open3.capture2('pandoc', '--version').first.lines.first.to_s.split.last.to_s
    rescue Errno::ENOENT
      'not installed'
    end

    # The block the about dialog shows under "Debug Information". Upstream
    # reads the OS name through GLib.get_os_info, which the Ruby bindings do
    # not expose, so /etc/os-release is parsed the way GLib parses it.
    def get_debug_info
      [
        "Apostrophe #{Apostrophe::Rb::VERSION}",
        '',
        "Flatpak: #{File.file?('/.flatpak-info') ? 'yes' : 'no'}",
        "GTK: #{Gtk.major_version}.#{Gtk.minor_version}.#{Gtk.micro_version}",
        "GLib: #{GLib::VERSION.join('.')}",
        "Libadwaita: #{Adwaita.major_version}.#{Adwaita.minor_version}.#{Adwaita.micro_version}",
        "Pandoc: #{pandoc_version}",
        '',
        "OS: #{os_info('NAME')} #{os_info('VERSION')}",
        "Display: #{display_name}",
        '',
        "gtk-theme-name: #{Gtk::Settings.default&.gtk_theme_name}",
        "GTK_THEME: #{ENV.fetch('GTK_THEME', nil)}",
        '',
        *Settings.instance.keys.map { |key| "#{key}: #{Settings.instance.variant(key)}" },
      ].join("\n")
    end

    def os_info(key)
      release_file.fetch(key, 'unknown')
    end

    def release_file
      ['/etc/os-release', '/usr/lib/os-release'].find { |path| File.readable?(path) }.then do |path|
        if path
          File.readlines(path, chomp: true).filter_map { |line| line.split('=', 2) }
            .select { |pair| pair.length == 2 }
            .to_h { |name, value| [name, value.delete('"')] }
        else
          {}
        end
      end
    end

    # Upstream strips "Gdk" and "Display" off the display's class name to get
    # "X11" or "Wayland"; the Ruby class names are namespaced
    # (GdkX11::X11Display), so the same two words come off the last segment.
    def display_name
      Gdk::Display.default.class.name.split('::').last.to_s
        .delete_suffix('Display').delete_prefix('Gdk')
    end
  end
end
