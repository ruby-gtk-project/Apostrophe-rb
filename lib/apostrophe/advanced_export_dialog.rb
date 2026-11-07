# frozen_string_literal: true

require 'adwaita'
require 'fileutils'
require 'open3'
require_relative 'export_format'
require_relative 'helpers'
require_relative 'texlive_warning'
require_relative 'theme'

module Apostrophe
  # AdvancedExportDialog is the `win.advanced_export` window: a two-pane
  # leaflet, a list of every format Pandoc can write on the left and, on the
  # right, the options that format supports (page size, HTML self-containment,
  # syntax highlighting, presentation bullets) — or the TexliveWarning empty
  # state in place of the options when the format needs a TeX toolchain that
  # is not installed.
  #
  # Ported from the `AdvancedExportDialog` class in apostrophe/export_dialog.py
  # and data/ui/Export.ui. The format list is ExportFormat::ALL (ported from
  # data/media/formats.json), rather than reading that JSON back at runtime.
  class AdvancedExportDialog
    Helpers.bind_gettext(self)

    PAGE_SIZES = %w[A4 Letter].freeze
    SYNTAX_STYLES = %w[pygments kate monochrome espresso zenburn haddock tango].freeze

    def initialize(parent, document, text)
      @parent = parent
      @document = document
      @text = text
      @selected_index = 0
    end

    def present
      window.transient_for = @parent
      # Selecting the first row (after the window is fully built, so the
      # row-selected handler's own calls back into `leaflet` and
      # `formats_list` hit their memoized values instead of re-entering
      # construction) is what shows that format's options immediately,
      # matching upstream's own `select_row` call in its constructor.
      formats_list.select_row(formats_list.get_row_at_index(0))
      window.present
    end

    private

      def selected_format = ExportFormat::ALL.fetch(@selected_index)

      def show_texlive_warning? = selected_format.requires_texlive? && !Helpers.exist_executable?('pdftex')

      def exports_multiple_files? = selected_format.to == 'revealjs'

      def window
        @window ||= Adwaita::Window.new.tap do |win|
          win.modal = true
          win.default_width = 800
          win.default_height = 550
          win.destroy_with_parent = true
          win.content = root_box
        end
      end

      def root_box
        @root_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
          box.append(headerbar)
          box.append(leaflet)
        end
      end

      def headerbar
        @headerbar ||= Adwaita::HeaderBar.new.tap do |bar|
          bar.pack_start(go_previous_revealer)
          bar.pack_start(cancel_button)
          bar.pack_end(export_button)
        end
      end

      def go_previous_revealer
        @go_previous_revealer ||= Gtk::Revealer.new.tap do |rev|
          rev.transition_type = :slide_right
          rev.transition_duration = 150
          rev.child = go_previous_button
        end
      end

      def go_previous_button
        @go_previous_button ||= Gtk::Button.new.tap do |button|
          button.margin_end = 6
          button.icon_name = 'go-previous-symbolic'
          button.signal_connect('clicked') { leaflet.visible_child = formats_page }
        end
      end

      def cancel_button
        @cancel_button ||= Gtk::Button.new.tap do |button|
          button.label = _('Cancel')
          button.add_css_class('popup')
          button.signal_connect('clicked') { window.close }
        end
      end

      def export_button
        @export_button ||= Gtk::Button.new.tap do |button|
          button.label = _('Export')
          button.add_css_class('popup')
          button.add_css_class('suggested-action')
          button.signal_connect('clicked') { on_export }
        end
      end

      def leaflet
        @leaflet ||= Adwaita::Leaflet.new.tap do |leaf|
          leaf.homogeneous = false
          leaf.transition_type = :slide
          leaf.append(formats_page)
          leaf.append(Gtk::Separator.new(:vertical).tap { |s| s.vexpand = true })
          leaf.append(options_page)
          leaf.visible_child = formats_page
          leaf.signal_connect('notify::folded') { update_go_back }
          leaf.signal_connect('notify::visible-child') { update_go_back }
        end
      end

      def formats_page
        @formats_page ||= Gtk::ScrolledWindow.new.tap do |scrolled|
          scrolled.min_content_width = 300
          scrolled.propagate_natural_height = true
          scrolled.child = formats_list
        end
      end

      def formats_list
        @formats_list ||= Gtk::ListBox.new.tap do |box|
          ExportFormat::ALL.each do |format|
            box.append(Adwaita::ActionRow.new.tap { |row| row.title = format.name })
          end
          box.signal_connect('row-selected') { |_box, row| on_format_selected(row) }
        end
      end

      def options_page
        @options_page ||= Gtk::Stack.new.tap do |stack|
          stack.add_named(options_scrolled_window, 'options')
          stack.add_named(texlive_warning.build, 'texlive_warning')
        end
      end

      def texlive_warning = @texlive_warning ||= TexliveWarning.new

      def options_scrolled_window
        @options_scrolled_window ||= Gtk::ScrolledWindow.new.tap do |scrolled|
          scrolled.min_content_width = 400
          scrolled.propagate_natural_height = true
          scrolled.child = options_clamp
        end
      end

      def options_clamp
        @options_clamp ||= Adwaita::Clamp.new.tap do |clamp|
          clamp.margin_top = 20
          clamp.margin_bottom = 20
          clamp.maximum_size = 550
          clamp.tightening_threshold = 300
          clamp.child = options_box
        end
      end

      def options_box
        @options_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
          box.append(general_options_group)
          box.append(page_size_group)
          box.append(html_options_group)
          box.append(syntax_options_group)
          box.append(presentation_options_group)
        end
      end

      def general_options_group
        @general_options_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.add(general_expander) }
      end

      def general_expander
        @general_expander ||= Adwaita::ExpanderRow.new.tap do |row|
          row.title = _('Options')
          row.activatable = false
          row.add_row(standalone_row)
          row.add_row(toc_row)
          row.add_row(numbers_row)
        end
      end

      def standalone_row
        @standalone_row ||= Adwaita::ActionRow.new.tap do |row|
          row.title = _('Standalone')
          row.subtitle = _('Use a header and footer to include things like stylesheets and meta information')
          row.activatable_widget = sw_standalone
          row.add_suffix(sw_standalone)
        end
      end

      def sw_standalone
        @sw_standalone ||= Gtk::Switch.new.tap do |sw|
          sw.valign = :center
          sw.active = true
          sw.signal_connect('notify::active') { sw_toc.sensitive = sw.active? }
        end
      end

      def toc_row
        @toc_row ||= Adwaita::ActionRow.new.tap do |row|
          row.title = _('Table of Contents')
          row.activatable_widget = sw_toc
          row.add_suffix(sw_toc)
        end
      end

      def sw_toc = @sw_toc ||= Gtk::Switch.new.tap { |sw| sw.valign = :center }

      def numbers_row
        @numbers_row ||= Adwaita::ActionRow.new.tap do |row|
          row.title = _('Number Sections')
          row.activatable_widget = sw_numbers
          row.add_suffix(sw_numbers)
        end
      end

      def sw_numbers = @sw_numbers ||= Gtk::Switch.new.tap { |sw| sw.valign = :center }

      def page_size_group
        @page_size_group ||= Adwaita::PreferencesGroup.new.tap do |g|
          g.title = _('Page Size')
          g.margin_top = 18
          g.add(page_size_row)
        end
      end

      def page_size_row
        @page_size_row ||= Adwaita::ComboRow.new.tap do |row|
          row.title = _('Page Size')
          row.activatable = false
          row.model = Gtk::StringList.new(PAGE_SIZES)
        end
      end

      def html_options_group
        @html_options_group ||= Adwaita::PreferencesGroup.new.tap do |g|
          g.title = _('HTML Options')
          g.margin_top = 18
          g.add(self_contained_row)
        end
      end

      def self_contained_row
        @self_contained_row ||= Adwaita::ActionRow.new.tap do |row|
          row.title = _('Self-contained')
          row.subtitle = _('Produces an HTML file with no external dependencies')
          row.activatable_widget = sw_self_contained
          row.add_suffix(sw_self_contained)
        end
      end

      def sw_self_contained = @sw_self_contained ||= Gtk::Switch.new.tap { |sw| sw.valign = :center; sw.active = true }

      def syntax_options_group
        @syntax_options_group ||= Adwaita::PreferencesGroup.new.tap do |g|
          g.title = _('Syntax Highlighting')
          g.margin_top = 18
          g.add(syntax_highlighting_expander)
        end
      end

      def syntax_highlighting_expander
        @syntax_highlighting_expander ||= Adwaita::ExpanderRow.new.tap do |row|
          row.title = _('Use Syntax Highlighting')
          row.enable_expansion = false
          row.show_enable_switch = true
          row.add_row(syntax_style_row)
        end
      end

      def syntax_style_row
        @syntax_style_row ||= Adwaita::ComboRow.new.tap do |row|
          row.title = _('Highlight style')
          row.activatable = false
          row.model = Gtk::StringList.new(SYNTAX_STYLES)
        end
      end

      def presentation_options_group
        @presentation_options_group ||= Adwaita::PreferencesGroup.new.tap do |g|
          g.title = _('Presentation')
          g.margin_top = 18
          g.add(incremental_bullets_row)
        end
      end

      def incremental_bullets_row
        @incremental_bullets_row ||= Adwaita::ActionRow.new.tap do |row|
          row.title = _('Incremental bullets')
          row.subtitle = _('Show one bullet point after another in a slideshow')
          row.activatable_widget = sw_incremental_bullets
          row.add_suffix(sw_incremental_bullets)
        end
      end

      def sw_incremental_bullets
        @sw_incremental_bullets ||= Gtk::Switch.new.tap { |sw| sw.valign = :center; sw.active = true }
      end

      def on_format_selected(row)
        unless row.nil?
          @selected_index = row.index
          leaflet.visible_child = options_page
          update_option_visibility
          update_title
          update_go_back
        end
      end

      def update_option_visibility
        format = selected_format
        page_size_group.visible = format.has_pages?
        html_options_group.visible = format.html?
        syntax_options_group.visible = format.has_syntax?
        presentation_options_group.visible = format.presentation?
        export_button.sensitive = !show_texlive_warning?
        if show_texlive_warning?
          options_page.visible_child_name = 'texlive_warning'
        else
          options_page.visible_child_name = 'options'
        end
      end

      def update_title = window.title = format(_('Export to %{name}'), name: selected_format.name)

      def update_go_back
        go_previous_revealer.reveal_child = leaflet.folded? && leaflet.visible_child == options_page
      end

      def update_title_and_visibility
        update_option_visibility
        update_title
      end

      def retrieve_args
        format = selected_format
        args = []

        if format.ext == 'pdf'
          args << '--pdf-engine=xelatex'
        end
        if sw_standalone.active?
          args << '--standalone'
        end
        if sw_toc.active?
          args << '--toc'
        end
        if sw_numbers.active?
          args << '--number-sections'
        end

        if format.has_pages? && page_size_row.selected.zero?
          if %w[pdf latex context].include?(format.to)
            args << '--variable=papersize:a4'
          elsif %w[odt docx].include?(format.to)
            reference = Helpers.media_path("/reference_files/reference-a4.#{format.to}")
            if reference
              args << "--reference-doc=#{reference}"
            end
          end
        end

        if format.html?
          args << "--css=#{Theme.current.web_css}"
          args << '--mathjax'
          args << "--lua-filter=#{Helpers.media_path('/lua/relative_to_absolute.lua')}"
          args << "--lua-filter=#{Helpers.media_path('/lua/task-list.lua')}"
          if sw_self_contained.active?
            args << '--embed-resources'
            args << '--standalone'
          end
        end

        if format.has_syntax? && syntax_highlighting_expander.enable_expansion?
          style = SYNTAX_STYLES[syntax_style_row.selected]
          if style
            args << "--highlight-style=#{style}"
          end
        end

        if format.presentation? && sw_incremental_bullets.active?
          args << '--incremental'
        end
        if format.to == 'revealjs'
          args.push('-V', 'revealjs-url=reveal.js')
        end

        args
      end

      def on_export
        args = retrieve_args
        format = selected_format

        if exports_multiple_files?
          chooser = Gtk::FileChooserNative.new(
            _('Export'),
            window,
            :select_folder,
            _('Select folder'),
            _('Cancel'),
          )
        else
          chooser = Gtk::FileChooserNative.new(
            _('Export'),
            window,
            :save,
            format(_('Export to %{name}'), name: format.name),
            _('Cancel'),
          )
          chooser.current_name = "#{@document.name}.#{format.ext}"
        end

        chooser.signal_connect('response') { |_dialog, response| on_export_response(
          chooser,
          response,
          format,
          args,
        ) }
        chooser.show
      end

      def on_export_response(chooser, response, format, args)
        if response == :accept
          write_export(chooser.file, format, args)
        end
        chooser.destroy
        window.close
      end

      def write_export(file, format, args)
        if exports_multiple_files?
          extract_revealjs(file.path)
          outputfile = File.join(file.path, "#{@document.name}.#{format.ext}")
        else
          outputfile = file.path
        end

        Helpers.pandoc_convert(
          @text,
          to:         format.to,
          args:       args,
          outputfile: outputfile,
        )
      rescue RuntimeError => e
        Helpers.show_error(window, _('An error happened while trying to export:') + "\n\n#{e.message}")
      end

      # Unzips the bundled reveal.js into the export folder. Shelled out to
      # `unzip` the same way export itself shells out to `pandoc`, rather than
      # pulling in a zip gem for one extraction.
      def extract_revealjs(destination)
        zip_path = Helpers.media_path('/media/reveal.js.zip')
        if zip_path
          FileUtils.mkdir_p(destination)
          _, stderr, status = Open3.capture3(
            'unzip',
            '-o',
            '-q',
            zip_path,
            '-d',
            destination,
          )
          unless status.success?
            raise "unzip failed: #{stderr.strip}"
          end
        end
      end
  end
end
