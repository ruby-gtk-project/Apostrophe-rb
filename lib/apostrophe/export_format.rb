# frozen_string_literal: true

require_relative 'helpers'
require_relative 'theme'

module Apostrophe
  # ExportFormat is one entry in the advanced export dialog's format list: the
  # name shown to the user, the file extension written and the Pandoc writer
  # used, plus the five capability questions the dialog asks of a format to
  # decide which option groups to show.
  #
  # Ported from the `Format` class in apostrophe/export_dialog.py, with the
  # list itself from data/media/formats.json. Upstream reads that JSON at
  # startup through GResource; the port carries the same seventeen entries in
  # the same order as a constant, which is one fewer file to ship and keeps the
  # list checkable by `ruby -c`.
  #
  # Defined without a block, and reopened below: a constant assigned inside a
  # `Data.define` block binds to the enclosing scope rather than to the class,
  # so `ExportFormat::PAGED` would not exist.
  ExportFormat = Data.define(:name, :ext, :to)

  class ExportFormat
    Helpers.bind_gettext(self)

    # Formats with a page size, so the dialog offers paper size and margins.
    PAGED = %w[pdf odt docx].freeze

    # Extensions whose writer understands Pandoc's syntax highlighting.
    HIGHLIGHTED = %w[html tex docx pdf].freeze

    # Writers that produce slides rather than a flowing document.
    PRESENTATIONS = %w[beamer revealjs dzslides].freeze

    # Extensions produced by a TeX toolchain, which the TexLive warning gates.
    TEXLIVE = %w[tex pdf].freeze

    # `_` runs once, here, when this file is first required — which is
    # late enough: the process's locale comes from the environment it was
    # started in (`LANG`/`LANGUAGE`), already set before Ruby itself
    # booted, and nothing in this app changes locale while running. That
    # makes a frozen constant exactly as translation-safe as a method
    # would be, and `ALL`/`QUICK` stay constants because the drive script
    # and specs reach into them by that name.
    ALL = [
      { name: _('PDF'), ext: 'pdf', to: 'pdf' },
      { name: _('LibreOffice Text Document'), ext: 'odt', to: 'odt' },
      { name: _('Microsoft Word (docx)'), ext: 'docx', to: 'docx' },
      { name: _('EPUB v3'), ext: 'epub', to: 'epub' },
      { name: _('HTML5 Slideshow (reveal.js)'), ext: 'html', to: 'revealjs' },
      { name: _('LaTeX Beamer Slideshow (pdf)'), ext: 'pdf', to: 'beamer' },
      { name: _('LaTeX Beamer Slideshow (tex)'), ext: 'tex', to: 'beamer' },
      { name: _('HTML5 Slideshow (DZSlides)'), ext: 'html', to: 'dzslides' },
      { name: _('LaTeX (tex)'), ext: 'tex', to: 'latex' },
      { name: _('HTML'), ext: 'html', to: 'html5' },
      { name: _('MediaWiki Markup'), ext: 'txt', to: 'mediawiki' },
      { name: _('ConTeXt'), ext: 'tex', to: 'context' },
      { name: _('Textile'), ext: 'txt', to: 'textile' },
      { name: _('reStructuredText'), ext: 'txt', to: 'rst' },
      { name: _('Texinfo'), ext: 'texi', to: 'texinfo' },
      { name: _('Rich Text Format'), ext: 'rtf', to: 'rtf' },
      { name: _('Groff Man'), ext: 'man', to: 'man' },
    ].map { |attributes| new(**attributes) }.freeze

    # The three quick exports the main menu offers, each with the extension it
    # writes and the mime type its file chooser filters on. Taken from
    # `ExportDialog.formats` upstream.
    QUICK = {
      'pdf'  => {
        name:      _('PDF'),
        extension: 'pdf',
        to:        'pdf',
        mimetype:  'application/pdf',
      },
      'html' => {
        name:      _('HTML'),
        extension: 'html',
        to:        'html5',
        mimetype:  'text/html',
      },
      'odt'  => {
        name:      _('ODT'),
        extension: 'odt',
        to:        'odt',
        mimetype:  'application/vnd.oasis.opendocument.text',
      },
    }.freeze

    def self.names = ALL.map(&:name)

    def self.find_by_name(name) = ALL.find { |format| format.name == name }

    def self.quick(key) = QUICK.fetch(key)

    # The Pandoc arguments for a quick export. The HTML ones reference the
    # current theme's stylesheet and the two Lua filters, so they are built per
    # call rather than frozen into the table above.
    def self.quick_args(key)
      case key
      when 'pdf' then ['--pdf-engine=xelatex', '--variable=papersize:a4']
      when 'odt' then ['--variable=papersize:a4']
      when 'html'
        [
          '--embed-resources',
          '--standalone',
          "--css=#{Theme.current.web_css}",
          '--mathjax',
          "--lua-filter=#{Helpers.media_path('/lua/relative_to_absolute.lua')}",
          "--lua-filter=#{Helpers.media_path('/lua/task-list.lua')}",
        ]
      end
    end

    def has_pages? = PAGED.include?(to)
    def html? = to == 'html5'
    def has_syntax? = HIGHLIGHTED.include?(ext)
    def presentation? = PRESENTATIONS.include?(to)
    def requires_texlive? = TEXLIVE.include?(ext)
  end
end
