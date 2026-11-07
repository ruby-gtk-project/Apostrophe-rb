# frozen_string_literal: true

require 'adwaita'
require_relative 'preview_layout_switcher'
require_relative 'preview_window'

module Apostrophe
  # PreviewRenderer renders the preview according to the user-selected
  # layout: attached to the main window as a flap (full-width, half-width,
  # half-height) or detached into its own PreviewWindow (windowed). It owns
  # none of the preview's *content* — PreviewHandler does that, by adding
  # the rendered widget to the stack this class shows and hides — only the
  # window chrome and the resize/reveal animations around it.
  #
  # Ported from apostrophe/preview_renderer.py (`PreviewRenderer`). Upstream
  # is a GObject.Object with a `preview_layout` property that a `notify`
  # handler reacts to; the Ruby bindings make declaring a GObject property on
  # a plain class needlessly heavy for one integer, so `preview_layout=`
  # below calls `resize_and_show` directly, which is exactly what upstream's
  # `notify::preview-layout` handler (`update_mode`) does once a preview is
  # already showing.
  #
  # Upstream also reads `self.text_view.get_min_width()` to size the
  # half-width flap; this port's TextView does not expose that (see its own
  # file for why), so MIN_EDITOR_WIDTH stands in for it.
  class PreviewRenderer
    MIN_EDITOR_WIDTH = 450

    def initialize(window:, text_view:, flap:, preview_stack:, on_windowed_closed: nil)
      @window = window
      @text_view = text_view
      @flap = flap
      @preview_stack = preview_stack
      @on_windowed_closed = on_windowed_closed

      @preview_layout = PreviewLayout::FULL_WIDTH
      @preview_layout_cache = nil
      @window_size_cache = 0
      @preview_window = nil
      @showing = false

      @window.signal_connect('close-request') { on_window_closed }
    end

    attr_reader :preview_layout

    def preview_layout=(value)
      @preview_layout = value
      if @showing
        show
      end
    end

    # Adds `widget` to the preview stack and shows it. Equivalent to
    # upstream's `load_webview`, generalised to whatever content
    # PreviewHandler hands it.
    def load_content(widget)
      widget.visible = true
      @preview_stack.add_child(widget)
      @preview_stack.visible_child = widget
    end

    def show
      @showing = true
      case [@preview_layout_cache, @preview_layout]
      in [nil, PreviewLayout::WINDOWED]
        show_preview_window
      in [PreviewLayout::FULL_WIDTH, PreviewLayout::HALF_WIDTH] |
         [PreviewLayout::HALF_WIDTH, PreviewLayout::FULL_WIDTH] |
         [nil, PreviewLayout::FULL_WIDTH | PreviewLayout::HALF_WIDTH | PreviewLayout::HALF_HEIGHT]
        resize_window
        set_flap_mode
      in [PreviewLayout::HALF_HEIGHT, PreviewLayout::FULL_WIDTH | PreviewLayout::HALF_WIDTH] |
         [PreviewLayout::FULL_WIDTH | PreviewLayout::HALF_WIDTH, PreviewLayout::HALF_HEIGHT]
        hide
        resize_window
        set_flap_mode
      in [PreviewLayout::WINDOWED, PreviewLayout::FULL_WIDTH | PreviewLayout::HALF_WIDTH | PreviewLayout::HALF_HEIGHT]
        hide
        @flap.flap = @preview_stack
        show
      in [PreviewLayout::FULL_WIDTH | PreviewLayout::HALF_WIDTH | PreviewLayout::HALF_HEIGHT, PreviewLayout::WINDOWED]
        hide
        show_preview_window
      else
        nil
      end
    end

    def hide
      @showing = false
      @flap.reveal_flap = false
      @preview_stack.remove_css_class('half-width')
      @preview_stack.remove_css_class('full-width')

      if @preview_layout_cache == PreviewLayout::WINDOWED
        @window.present
        @preview_window&.preview_box&.remove(@preview_stack)
        @preview_window&.close
        @preview_window = nil
      elsif @preview_layout_cache == PreviewLayout::HALF_WIDTH
        shrink_window
      end

      @preview_layout_cache = nil
    end

    private

      def set_flap_mode
        @preview_stack.remove_css_class('half-width')
        @preview_stack.remove_css_class('full-width')

        case @preview_layout
        when PreviewLayout::FULL_WIDTH
          @flap.orientation = :horizontal
          @flap.fold_policy = :always
          @preview_stack.add_css_class('full-width')
          @flap.reveal_flap = true
        when PreviewLayout::HALF_WIDTH
          @flap.orientation = :horizontal
          @flap.fold_policy = :never
          @preview_stack.add_css_class('half-width')
          @flap.reveal_flap = true
        when PreviewLayout::HALF_HEIGHT
          @flap.orientation = :vertical
          @flap.fold_policy = :never
          @flap.reveal_flap = true
        else
          raise ArgumentError, "Unknown preview mode #{@preview_layout}"
        end

        @preview_layout_cache = @preview_layout
      end

      def shrink_window
        @flap.set_size_request(MIN_EDITOR_WIDTH, -1)
        animate(
          @window,
          'default-width',
          @window.width,
          @window_size_cache,
        )
      end

      def grow_window
        @window_size_cache = @window.width
        animate(
          @flap,
          'width-request',
          MIN_EDITOR_WIDTH,
          (MIN_EDITOR_WIDTH * 2) + 2,
        )
      end

      def resize_window
        case [@preview_layout_cache, @preview_layout]
        in [nil | PreviewLayout::HALF_HEIGHT | PreviewLayout::FULL_WIDTH, PreviewLayout::HALF_WIDTH]
          grow_window
        in [PreviewLayout::HALF_WIDTH, PreviewLayout::HALF_HEIGHT | PreviewLayout::FULL_WIDTH]
          shrink_window
        else
          nil
        end
      end

      def animate(target_object, property, from, to, duration: 250)
        target = Adwaita::PropertyAnimationTarget.new(target_object, property)
        Adwaita::TimedAnimation.new(
          target_object,
          from,
          to,
          duration,
          target,
        ).play
      end

      def show_preview_window
        unless @preview_window
          @preview_window = PreviewWindow.new.tap do |win|
            win.build
            win.window_object.signal_connect('close-request') { on_window_closed }
            win.preview_box.append(@preview_stack)
            win.set_default_size(@window.width, @window.height)
            win.present
          end
        end
        @preview_layout_cache = PreviewLayout::WINDOWED
      end

      def on_window_closed
        if @preview_window
          @showing = false
          @preview_layout_cache = nil
          @preview_window = nil
          @on_windowed_closed&.call
        end
        false
      end
  end
end
