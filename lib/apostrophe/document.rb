# frozen_string_literal: true

require 'adwaita'
require_relative 'helpers'
require_relative 'settings'

module Apostrophe
  # Document is the file the window currently has open: the GFile itself, the
  # encoding it was read with, the directory it lives in, its display name and
  # that name without the ".md" suffix.
  #
  # Ported from the `File` dataclass at the foot of apostrophe/main_window.py.
  # Renamed because `File` is Ruby's own file class, and the name upstream
  # chose would shadow it for every file that requires this one.
  #
  # Assigning a GFile is what computes the rest, exactly as upstream's property
  # setter does — including chdir into the document's directory, so that
  # relative image paths in the markdown resolve while that document is open,
  # and recording that directory in the `open-file-path` setting.
  class Document
    Helpers.bind_gettext(self)

    attr_reader :gfile, :path, :title, :name
    attr_accessor :encoding

    def initialize(gfile: nil, encoding: 'UTF-8')
      @encoding = encoding
      self.gfile = gfile
    end

    def gfile=(file)
      if file
        adopt(file)
      else
        forget
      end
      @gfile = file
    end

    # Whether this document has ever been written to disk. The window shows the
    # title either way, so this only decides whether saving needs a chooser.
    def saved? = !@gfile.nil?

    def uri = @gfile&.uri

    private

      def adopt(file)
        if file.native?
          @path = file.parent.path
          base_path = file.parent.path
          Dir.chdir(base_path)
        else
          @path = file.parent.uri
          base_path = '/'
        end

        @title = file.query_info('standard', :none, nil)
          .get_attribute_as_string('standard::display-name')
        remember(base_path)
      end

      def forget
        @path = ''
        @title = _('New File')
        remember('/')
      end

      def remember(base_path)
        @name = @title.delete_suffix('.md')
        Settings.instance.open_file_path = base_path
      end
  end
end
