# frozen_string_literal: true

require 'gtk4'
require_relative 'export_format'
require_relative 'helpers'

module Apostrophe
  # ExportDialog runs one of the three quick exports the main menu's save
  # split-button offers (PDF, HTML, ODT): a native save chooser defaulting to
  # the document's own name, then a single Pandoc call to the chosen file.
  #
  # Ported from the `ExportDialog` class and module-level `export` function in
  # apostrophe/export_dialog.py. Upstream also builds a TexliveWarning in
  # front of a PDF export when `pdftex` is missing; that dialog is not ported
  # yet (see AdvancedExportDialog's own file for why), so a PDF export
  # without a TeX toolchain simply surfaces Pandoc's own failure through the
  # same error dialog every other export failure uses.
  class ExportDialog
    Helpers.bind_gettext(self)

    def initialize(window, document)
      @window = window
      @document = document
    end

    # format_key is one of ExportFormat::QUICK's keys ("pdf", "html", "odt").
    def export(format_key, text)
      format = ExportFormat.quick(format_key)

      chooser.tap do |dialog|
        dialog.add_filter(filter_for(format))
        dialog.current_name = "#{@document.name}.#{format.fetch(:extension)}"
        dialog.signal_connect('response') { |_dialog, response| on_response(
          response,
          dialog,
          format_key,
          format,
          text,
        ) }
        dialog.show
      end
    end

    private

      def chooser
        Gtk::FileChooserNative.new(
          _('Export'),
          @window,
          :save,
          _('Export'),
          _('Cancel'),
        )
      end

      def filter_for(format)
        Gtk::FileFilter.new.tap do |filter|
          filter.name = format.fetch(:name)
          filter.add_mime_type(format.fetch(:mimetype))
        end
      end

      def on_response(response, dialog, format_key, format, text)
        if response == :accept
          write(
            dialog.file,
            format_key,
            format,
            text,
          )
        end
        dialog.destroy
      end

      def write(file, format_key, format, text)
        Helpers.pandoc_convert(
          text,
          to:         format.fetch(:to),
          args:       ExportFormat.quick_args(format_key),
          outputfile: file.path,
        )
      rescue RuntimeError => e
        Helpers.show_error(@window, _('An error happened while trying to export:') + "\n\n#{e.message}")
      end
  end
end
