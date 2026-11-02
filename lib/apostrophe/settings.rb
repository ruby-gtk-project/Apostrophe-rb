# frozen_string_literal: true

require 'adwaita'
require 'fileutils'

module Apostrophe
  # Settings is the application's GSettings, the same thirteen keys and two
  # enums upstream declares.
  #
  # Ported from apostrophe/settings.py and
  # data/org.gnome.gitlab.somas.Apostrophe.gschema.xml, which this port ships
  # as data/schemas/org.rubygtkproject.Apostrophe.gschema.xml.
  #
  # Upstream can call `Gio.Settings.new(id)` directly because meson installs
  # the compiled schema into the system's glib-2.0/schemas directory. Running
  # the port straight out of a checkout has no install step, so when the schema
  # is not in the default source this compiles data/schemas into a cache
  # directory and builds a schema source over it. Once the flake's package has
  # installed the schema the default source finds it and nothing is compiled.
  class Settings
    SCHEMA_ID = 'org.rubygtkproject.Apostrophe'

    # Every key in the schema, with the reader used for it. `get_value` returns
    # a GLib::Variant, which is what upstream's debug info prints.
    KEYS = {
      'color-scheme'          => :string,
      'spellcheck'            => :boolean,
      'sync-scroll'           => :boolean,
      'input-format'          => :string,
      'autohide-headerbar'    => :boolean,
      'open-file-path'        => :string,
      'stat-default'          => :enum,
      'characters-per-line'   => :int,
      'hemingway-mode'        => :boolean,
      'hemingway-toast-count' => :int,
      'preview-mode'          => :enum,
      'preview-active'        => :boolean,
      'bigger-text'           => :boolean,
    }.freeze

    # The nicks of the two enums, in schema order, so an enum key can be read
    # and written as the symbol upstream uses rather than as an index.
    STATS = %w[characters words sentences paragraphs read_time].freeze
    PREVIEW_MODES = %w[full-width half-width half-height windowed].freeze

    ENUM_NICKS = {
      'stat-default' => STATS,
      'preview-mode' => PREVIEW_MODES,
    }.freeze

    class << self
      # One Gio::Settings for the whole process, the way upstream's
      # `Settings.new()` hands every caller the same backend.
      def instance = @instance ||= new

      def schema_directory
        File.expand_path('../../data/schemas', __dir__)
      end

      def compiled_schema_directory
        File.join(
          ENV.fetch('XDG_CACHE_HOME', File.expand_path('~/.cache')),
          'apostrophe-rb',
          'schemas',
        )
      end
    end

    def initialize
      @settings = Gio::Settings.new(schema, nil, nil)
    end

    def [](key) = read(key.to_s)

    def []=(key, value)
      write(key.to_s, value)
      value
    end

    # Named readers and writers for each key, so callers do not repeat the
    # dashed strings: `settings.sync_scroll?`, `settings.characters_per_line`.
    KEYS.each_key do |key|
      name = key.tr('-', '_')
      define_method(name) { read(key) }
      define_method(:"#{name}=") { |value| write(key, value) }
      if KEYS[key] == :boolean
        define_method(:"#{name}?") { read(key) }
      end
    end

    # Binds a key to a GObject property, the way upstream binds `color-scheme`
    # to the theme switcher's `selected-color-scheme`.
    def bind(key, object, property, flags = :default)
      @settings.bind(
        key.to_s,
        object,
        property.to_s.tr('_', '-'),
        flags,
      )
    end

    def connect_changed(key, &block)
      @settings.signal_connect("changed::#{key}") { |_settings, changed| block.call(read(changed)) }
    end

    # The GLib::Variant for a key, which is how upstream's debug info renders
    # each setting.
    def variant(key) = @settings.get_value(key.to_s)

    def keys = KEYS.keys

    private

      def read(key)
        case KEYS.fetch(key)
        when :string then @settings.get_string(key)
        when :boolean then @settings.get_boolean(key)
        when :int then @settings.get_int(key)
        when :enum then ENUM_NICKS.fetch(key)[@settings.get_enum(key)]
        end
      end

      def write(key, value)
        case KEYS.fetch(key)
        when :string then @settings.set_string(key, value.to_s)
        when :boolean then @settings.set_boolean(key, !!value)
        when :int then @settings.set_int(key, value.to_i)
        when :enum then @settings.set_enum(key, ENUM_NICKS.fetch(key).index(value.to_s))
        end
      end

      def schema
        Gio::SettingsSchemaSource.default.then do |default_source|
          default_source&.lookup(SCHEMA_ID, true) || local_source.lookup(SCHEMA_ID, true)
        end
      end

      # Compiles the shipped schema XML into the user's cache directory and
      # reads it back from there. glib-compile-schemas only rewrites the
      # compiled file when the XML is newer, so this is cheap on every run
      # after the first.
      def local_source
        self.class.compiled_schema_directory.then do |directory|
          FileUtils.mkdir_p(directory)
          Dir[File.join(self.class.schema_directory, '*.gschema.xml')].each do |xml|
            target = File.join(directory, File.basename(xml))
            stale = !File.exist?(target) || File.mtime(target) < File.mtime(xml)
            if stale
              FileUtils.cp(xml, target)
            end
          end
          system('glib-compile-schemas', directory, out: File::NULL)
          Gio::SettingsSchemaSource.new(directory, Gio::SettingsSchemaSource.default, true)
        end
      end
  end
end
