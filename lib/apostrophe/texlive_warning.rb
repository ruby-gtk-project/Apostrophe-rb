# frozen_string_literal: true

require 'gtk4'
require_relative 'helpers'

module Apostrophe
  # TexliveWarning is the empty-state AdvancedExportDialog shows in place of
  # its options pane when the chosen format needs a TeX toolchain and
  # `pdftex` is not on PATH: one of two near-identical panels (Flatpak,
  # distro) depending on how the app is running, the Flatpak one with a
  # copyable install command.
  #
  # Ported from the `TexliveWarning` class in apostrophe/export_dialog.py and
  # data/ui/TexliveWarning.ui.
  class TexliveWarning
    FLATPAK_COMMAND = 'flatpak install org.gnome.gitlab.somas.Apostrophe.Plugin.TexLive'

    def build
      stack.tap do |s|
        s.add_named(flatpak_panel, 'flatpak')
        s.add_named(distro_panel, 'distro')
        if File.file?('/.flatpak-info')
          s.visible_child_name = 'flatpak'
        else
          s.visible_child_name = 'distro'
        end
      end
    end

    private

      def stack
        @stack ||= Gtk::Stack.new.tap do |s|
          s.vhomogeneous = false
          s.hhomogeneous = false
        end
      end

      def flatpak_panel
        @flatpak_panel ||= panel_box.tap do |box|
          box.append(title_label)
          box.append(label(<<~TEXT.strip))
            Apostrophe needs the TeXLive extension
            in order to export PDF or LaTeX files.

            Install it from Apostrophe's page in Software
            or by running the following command in a terminal:
          TEXT
          box.append(command_entry)
          box.append(copy_button)
        end
      end

      def distro_panel
        @distro_panel ||= panel_box.tap do |box|
          box.append(title_label_for_distro)
          box.append(label(<<~TEXT.strip))
            Apostrophe needs TeXLive
            in order to export PDF or LaTeX files.

            Install it from your distribution repositories
          TEXT
        end
      end

      # Fresh boxes per panel: the two panels cannot share widget instances.
      def panel_box
        Gtk::Box.new(:vertical, 16).tap do |box|
          box.halign = :center
          box.valign = :center
          box.margin_start = 12
          box.margin_end = 12
          box.margin_top = 12
          box.margin_bottom = 12
        end
      end

      def title_label = title_label_for_distro

      def title_label_for_distro
        Gtk::Label.new('TexLive Required').tap do |l|
          l.add_css_class('title-2')
          l.justify = :center
          l.margin_bottom = 16
        end
      end

      def label(text)
        Gtk::Label.new(text).tap do |l|
          l.justify = :center
          l.wrap = true
        end
      end

      def command_entry
        @command_entry ||= Gtk::Entry.new.tap do |entry|
          entry.text = FLATPAK_COMMAND
          entry.editable = false
          entry.max_width_chars = 48
        end
      end

      def copy_button
        @copy_button ||= Gtk::Button.new.tap do |button|
          button.halign = :center
          button.label = 'Copy to clipboard'
          button.signal_connect('clicked') { copy }
        end
      end

      def copy
        command_entry.clipboard.set(command_entry.text)
      end
  end
end
