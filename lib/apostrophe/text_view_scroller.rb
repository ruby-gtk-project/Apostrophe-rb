# frozen_string_literal: true

require 'adwaita'

module Apostrophe
  # TextViewScroller reads and writes the editor's scroll position as a scale
  # from 0 to 1 — the quantity the preview's scroll is synchronised against —
  # and scrolls a mark into view, either at once or over an eased animation.
  #
  # Ported from apostrophe/text_view_scroller.py.
  class TextViewScroller
    # How close to the edge of the viewport a mark may sit before a scroll is
    # needed, in pixels.
    MARGIN = 32

    def initialize(text_view, scrolled_window)
      @text_view = text_view
      @scrolled_window = scrolled_window
      @smooth_scroller = nil
    end

    def can_scroll?
      adjustment.then { |a| a.upper > a.page_size }
    end

    def scroll_scale
      adjustment.then do |a|
        if a.upper > a.page_size
          a.value / (a.upper - a.page_size)
        else
          0
        end
      end
    end

    def scroll_scale=(scale)
      adjustment.then { |a| a.value = (a.upper - a.page_size) * scale }
    end

    # Scrolls until the mark is visible, if it is not already.
    def scroll_to_mark(mark, center)
      target_pos_for_mark(mark, center).then do |target|
        if target
          adjustment.value = target
        end
      end
    end

    # The same, animated. An animation already in flight is ended first, so two
    # marks in quick succession do not fight over the adjustment.
    def smooth_scroll_to_mark(mark, center)
      if @smooth_scroller&.started?
        @smooth_scroller.end_scroll
      end

      target_pos_for_mark(mark, center).then do |target|
        if target
          @smooth_scroller = SmoothScroller.new(@scrolled_window, adjustment.value, target)
          @smooth_scroller.start
        end
      end
    end

    # Where the adjustment would have to sit for the mark to be visible, or nil
    # when it already is. With `center` the mark is pulled to the middle of the
    # viewport instead of just inside its edge.
    def target_pos_for_mark(mark, center)
      mark_rect = @text_view.get_iter_location(@text_view.buffer.get_iter_at(mark: mark))
      a = adjustment
      pos_y = mark_rect.y + mark_rect.height + @text_view.top_margin
      pos_viewport_y = pos_y - a.value

      if center
        if pos_viewport_y == a.page_size / 2
          nil
        else
          pos_y - (a.page_size / 2)
        end
      elsif pos_viewport_y > a.page_size - MARGIN
        pos_y - a.page_size + MARGIN
      elsif pos_viewport_y < MARGIN
        pos_y - MARGIN - mark_rect.height
      end
    end

    private

      def adjustment = @scrolled_window.vadjustment
  end

  # SmoothScroller eases the scrolled window's adjustment from one position to
  # another off the frame clock, with the cubic ease-out upstream uses.
  #
  # Ported from the `SmoothScroller` class in
  # apostrophe/text_view_scroller.py.
  class SmoothScroller
    def initialize(scrolled_window, source_pos, target_pos)
      @scrolled_window = scrolled_window
      @source_pos = source_pos
      @target_pos = target_pos
      @duration = [100, (target_pos - source_pos) / 50].max * 4000

      @started = false
      @setup = false
      @start_time = 0
      @end_time = 0
      @tick_callback_id = 0
    end

    def started? = @started

    def start
      @started = true
      @tick_callback_id = @scrolled_window.add_tick_callback do |widget, frame_clock|
        tick(widget, frame_clock)
      end
    end

    # Named `end_scroll` rather than upstream's `end`: `end` is a Ruby keyword.
    def end_scroll
      @scrolled_window.remove_tick_callback(@tick_callback_id)
      @started = false
    end

    private

      # The first tick is when the frame clock's notion of "now" is first
      # available, so the animation's window is anchored there rather than at
      # construction time.
      def tick(widget, frame_clock)
        now = frame_clock.frame_time
        unless @setup
          @start_time = now
          @end_time = now + @duration
          @setup = true
        end

        if now < @end_time
          progress = (now - @start_time).to_f / (@end_time - @start_time)
        else
          progress = 1
          end_scroll
        end

        widget.vadjustment.value =
          @source_pos + (ease_out_cubic(progress) * (@target_pos - @source_pos))
        true
      end

      def ease_out_cubic(value) = ((value - 1)**3) + 1
  end
end
