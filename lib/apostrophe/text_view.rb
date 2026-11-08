# frozen_string_literal: true

require 'adwaita'
require 'uri'
require_relative 'helpers'
require_relative 'text_buffer'

module Apostrophe
  # TextView is the editor widget: a Gtk::TextView married to its own buffer,
  # with the vertical margins focus mode needs and a drop target that turns a
  # dropped file or web address into a markdown link.
  #
  # Ported from apostrophe/text_view.py and data/ui/TextView.ui. Upstream also
  # recomputes its left/right margin and font size off the view's allocated
  # width on every resize, and exposes a `scroll-scale` GObject property the
  # preview's scroll position is bound to; the Ruby TextView vfunc override
  # needed for the first is not reachable from this binding (confirmed by
  # testing `do_size_allocate`, which is never invoked), and nothing in this
  # round of the port reads the second, so the view keeps the fixed
  # horizontal margins Style already gives it through CSS and leaves both out
  # rather than ship a resize hook that does not fire.
  #
  # The format-insertion shortcuts, the markup highlighting and the window
  # actions upstream wires onto this widget stay on Application for now,
  # which already reaches them through plain window actions.
  class TextView < Gtk::TextView
    Helpers.bind_gettext(self)

    attr_accessor :scroller, :focus_mode
    attr_reader :text_buffer

    def initialize(on_attempted_hemingway: nil)
      super()
      @focus_mode = false
      @text_buffer = TextBuffer.new(on_attempted_hemingway: on_attempted_hemingway)
      self.buffer = @text_buffer
      self.wrap_mode = :word_char
      self.monospace = true
      self.pixels_above_lines = 4
      self.pixels_below_lines = 4
      self.pixels_inside_wrap = 8
      self.left_margin = 24
      self.right_margin = 24
      add_css_class('apostrophe-editor')
      update_vertical_margin
      add_controller(drop_target)
    end

    def text = @text_buffer.get_text(@text_buffer.start_iter, @text_buffer.end_iter, false)

    # Upstream's set_text: replaces the text and clears the undo history.
    def text=(value)
      @text_buffer.begin_irreversible_action
      Helpers.user_action(@text_buffer) { @text_buffer.text = value }
      @text_buffer.end_irreversible_action
    end

    def clear = self.text = ''

    # Upstream's update_vertical_margin: in focus mode the margins grow to
    # push the current line to the centre of the view; otherwise they are the
    # fixed sizes upstream hardcodes. `extra_top` is the height of whatever is
    # overlaid above the view (the search bar), so the text does not slide
    # underneath it.
    def update_vertical_margin(extra_top = 0)
      if @focus_mode
        height = allocated_height + extra_top
        self.top_margin = (height / 2) + extra_top
        self.bottom_margin = height / 2
      else
        self.top_margin = 80 + extra_top
        self.bottom_margin = 64
      end
    end

    # Upstream's smooth_scroll_to: scrolls the cursor (or `mark`) back into
    # view once the layout the caller just triggered has settled.
    def smooth_scroll_to(mark = nil)
      if @scroller
        target = mark || @text_buffer.get_mark('insert')
        GLib::Idle.add do
          @scroller.smooth_scroll_to_mark(target, @focus_mode)
          false
        end
      end
    end

    private

      def drop_target
        Gtk::DropTarget.new(String, Gdk::DragAction::COPY).tap do |target|
          target.signal_connect('drop') { |_t, value, _x, _y| on_drop(value) }
        end
      end

      # Upstream's on_drop: a dropped local file becomes a markdown image
      # link when it is an image, a plain link otherwise; a dropped http(s)
      # address becomes a plain link too. Anything else is plain text GTK has
      # already inserted on its own, so there is nothing further to do.
      def on_drop(value)
        content = value.to_s
        if content.start_with?('file://')
          path = content.strip.delete_prefix('file://')
          name = File.basename(URI.decode_www_form_component(path))
          mime, = Gio::ContentType.guess(path, nil)
          if mime.to_s.start_with?('image/')
            link = "![#{name}](#{path})"
          else
            link = "[#{name}](#{path})"
          end
          @text_buffer.insert_at_cursor(link)
          true
        elsif content.start_with?('http://', 'https://')
          @text_buffer.insert_at_cursor("[#{_('web page')}](#{content})")
          true
        else
          false
        end
      end
  end
end
