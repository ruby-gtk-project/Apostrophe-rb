# frozen_string_literal: true

require 'adwaita'
require 'cgi'
require_relative 'helpers'

module Apostrophe
  # ShortcutsWindow is the app.shortcuts window: every accelerator Apostrophe
  # binds, grouped the way upstream groups them.
  #
  # Ported from data/ui/Shortcuts.ui, a GtkShortcutsWindow built straight from
  # a .ui file. `Gtk::ShortcutsWindow.new` is broken in this binding — it
  # raises `TypeError: GtkWindow is not subtype of GtkShortcutsWindow` even
  # inside a running Gtk::Application, confirmed by testing every constructor
  # shape the loader's error lists as available — so this class keeps the
  # group data as a plain Ruby structure (the single source of truth) and
  # reaches the widget by handing a Gtk::Builder a small XML document
  # generated from that data, which is the one construction path that works.
  class ShortcutsWindow
    Helpers.bind_gettext(self)

    def present(parent)
      window.transient_for = parent
      window.present
    end

    private

      def window
        @window ||= builder.get_object('shortcuts').tap do |win|
          win.modal = true
        end
      end

      def builder = @builder ||= Gtk::Builder.new.tap { |b| b.add_from_string(xml) }

      # [group title, [[shortcut title, accelerator], ...]], in upstream's
      # order. Built as a method rather than a frozen constant, so each
      # title goes through `_` when the window is actually built rather
      # than when this file is first required.
      def groups
        [
          [_('General'), [
            [_('New'), '<Primary>n'],
            [_('Open'), '<Primary>o'],
            [_('Save'), '<Primary>s'],
            [_('Save as'), '<Shift><Primary>s'],
            [_('Close document'), '<Primary>w'],
            [_('Quit application'), '<Primary>q'],
          ]
],
          [_('Modes'), [
            [_('Focus mode'), '<Primary>d'],
            [_('Hemingway mode'), '<Primary>t'],
            [_('Preview'), '<Primary>p'],
            [_('Fullscreen'), 'F11'],
          ]
],
          [_('Find'), [
            [_('Find'), '<Primary>f'],
            [_('Find and replace'), '<Primary>h'],
          ]
],
          [_('Markdown'), [
            [_('Separator'), '<Primary>r'],
            [_('Header'), '<Primary>1 4'],
            [_('List item'), '<Primary>u'],
            [_('Italic'), '<Primary>i'],
            [_('Bold'), '<Primary>b'],
            [_('Strikeout'), '<Shift><Primary>D'],
          ]
],
          [_('Copy and paste'), [
            [_('Copy selected text to clipboard'), '<Primary>C'],
            [_('Cut selected text to clipboard'), '<Primary>X'],
            [_('Paste selected text from clipboard'), '<Primary>V'],
          ]
],
          [_('Undo and redo'), [
            [_('Undo previous command'), '<Primary>Z'],
            [_('Redo previous command'), '<Shift><Primary>Z'],
          ]
],
          [_('Selection'), [
            [_('Select all text'), '<Primary>A'],
          ]
],
        ]
      end

      def xml
        <<~XML
          <interface>
            <object class="GtkShortcutsWindow" id="shortcuts">
              <property name="modal">True</property>
              <child>
                <object class="GtkShortcutsSection" id="section">
                  <property name="section-name">shortcuts</property>
                  <property name="max-height">10</property>
                  #{groups.map { |title, shortcuts| group_xml(title, shortcuts) }.join}
                </object>
              </child>
            </object>
          </interface>
        XML
      end

      def group_xml(title, shortcuts)
        <<~XML
          <child>
            <object class="GtkShortcutsGroup">
              <property name="visible">True</property>
              <property name="title" translatable="yes">#{escape(title)}</property>
              #{shortcuts.map { |shortcut_title, accelerator| shortcut_xml(shortcut_title, accelerator) }.join}
            </object>
          </child>
        XML
      end

      def shortcut_xml(title, accelerator)
        <<~XML
          <child>
            <object class="GtkShortcutsShortcut">
              <property name="visible">True</property>
              <property name="title" translatable="yes">#{escape(title)}</property>
              <property name="accelerator">#{escape(accelerator)}</property>
            </object>
          </child>
        XML
      end

      def escape(text) = CGI.escapeHTML(text)
  end
end
