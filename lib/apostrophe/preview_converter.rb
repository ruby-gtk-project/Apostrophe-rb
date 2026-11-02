# frozen_string_literal: true

require 'adwaita'
require_relative 'helpers'
require_relative 'theme'

module Apostrophe
  # PreviewConverter turns the document's markdown into the standalone HTML the
  # preview renders, off the main thread.
  #
  # Ported from apostrophe/preview_converter.py.
  #
  # The Pandoc arguments are rebuilt for every conversion rather than held, so
  # a theme change is picked up by the next preview without the converter being
  # told about it — which is how upstream's worker gets the current stylesheet.
  class PreviewConverter
    def initialize
      @queue = Thread::Queue.new
      @worker = start_worker
    end

    # Converts `text` to HTML and calls `callback` with the result on the main
    # loop. A conversion already queued behind a newer one is dropped.
    def convert(text, &callback)
      @queue.push([text, callback])
    end

    # Ends the worker thread. The converter is not usable afterwards.
    def stop
      @queue.close
      @worker.join(1)
    end

    # The Pandoc arguments the preview is rendered with: a standalone document
    # titled nothing, maths through MathJax, the current theme's stylesheet,
    # and the two Lua filters that absolutise relative links and render task
    # lists.
    def self.args
      [
        '--metadata=pagetitle:""',
        '--standalone',
        '--mathjax',
        "--css=#{Theme.current.web_css}",
        "--lua-filter=#{Helpers.media_path('/lua/relative_to_absolute.lua')}",
        "--lua-filter=#{Helpers.media_path('/lua/task-list.lua')}",
      ]
    end

    private

      def start_worker
        Thread.new do
          while (job = next_job)
            text, callback = job
            deliver(callback, convert_text(text))
          end
        end
      end

      # A failed conversion is delivered as the error's message wrapped in a
      # paragraph, so a document Pandoc cannot read shows why in the preview
      # instead of leaving the last good render in place.
      def convert_text(text)
        Helpers.pandoc_convert(text, to: 'html5', args: self.class.args)
      rescue StandardError => e
        "<html><body><p>#{GLib.markup_escape_text(e.message)}</p></body></html>"
      end

      def deliver(callback, html)
        GLib::Idle.add do
          callback&.call(html)
          false
        end
      end

      # Takes the most recent job in the queue and drops the ones behind it:
      # converting a document the user has already typed past is wasted work.
      def next_job
        @queue.pop.then do |job|
          until @queue.empty?
            job = @queue.pop
          end
          job
        end
      end
  end
end
