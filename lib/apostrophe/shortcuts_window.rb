# frozen_string_literal: true

require 'adwaita'
require 'cgi'

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
    # [group title, [[shortcut title, accelerator], ...]], in upstream's order.
    GROUPS = [
      ['General', [
        ['New', '<Primary>n'],
        ['Open', '<Primary>o'],
        ['Save', '<Primary>s'],
        ['Save as', '<Shift><Primary>s'],
        ['Close document', '<Primary>w'],
        ['Quit application', '<Primary>q'],
      ]
],
      ['Modes', [
        ['Focus mode', '<Primary>d'],
        ['Hemingway mode', '<Primary>t'],
        ['Preview', '<Primary>p'],
        ['Fullscreen', 'F11'],
      ]
],
      ['Find', [
        ['Find', '<Primary>f'],
        ['Find and replace', '<Primary>h'],
      ]
],
      ['Markdown', [
        ['Separator', '<Primary>r'],
        ['Header', '<Primary>1 4'],
        ['List item', '<Primary>u'],
        ['Italic', '<Primary>i'],
        ['Bold', '<Primary>b'],
        ['Strikeout', '<Shift><Primary>D'],
      ]
],
      ['Copy and paste', [
        ['Copy selected text to clipboard', '<Primary>C'],
        ['Cut selected text to clipboard', '<Primary>X'],
        ['Paste selected text from clipboard', '<Primary>V'],
      ]
],
      ['Undo and redo', [
        ['Undo previous command', '<Primary>Z'],
        ['Redo previous command', '<Shift><Primary>Z'],
      ]
],
      ['Selection', [
        ['Select all text', '<Primary>A'],
      ]
],
    ].freeze

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

      def xml
        <<~XML
          <interface>
            <object class="GtkShortcutsWindow" id="shortcuts">
              <property name="modal">True</property>
              <child>
                <object class="GtkShortcutsSection" id="section">
                  <property name="section-name">shortcuts</property>
                  <property name="max-height">10</property>
                  #{GROUPS.map { |title, shortcuts| group_xml(title, shortcuts) }.join}
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
