# frozen_string_literal: true

require 'adwaita'
require_relative 'markup_regex'

module Apostrophe
  # StatsCounter counts characters, words, sentences and paragraphs in the
  # document, and estimates how long it takes to read, off the main thread.
  #
  # Ported from apostrophe/stats_counter.py.
  #
  # The markdown is stripped before anything is counted: the patterns in
  # REPLACE collapse to their "text" group, so `**bold**` counts as four
  # characters rather than eight, and the ones in REMOVE drop out entirely.
  # Order matters in both lists, which is why they are written out rather than
  # derived.
  #
  # Upstream counts in a worker process over a pipe; the port uses a thread and
  # a queue, with the result delivered on the main loop through
  # `GLib::Idle.add`. The counting is pure string work, so nothing in the
  # worker touches GTK.
  class StatsCounter
    # Any character except newlines and the spaces that follow whitespace.
    CHARACTERS = /[^\s]|(?:[^\S\n](?!\s))/

    # Asian letters, general symbols and hieroglyphs, or a run of word
    # characters possibly holding non-word characters in between. `[[:word:]]`
    # rather than `\w`: Ruby's `\w` is ASCII-only, where Python's is Unicode
    # under `re.UNICODE`.
    WORDS = /[\u3040-\uffff]|(?:[[:word:]]+\S?[[:word:]]*)+/

    # Sentence-ending punctuation, in every script upstream lists.
    SENTENCES = /[^\n][.。।෴۔።?՞;⸮؟？፧꘏⳺⳻⁇﹖⁈⁉‽!﹗！՜߹႟᥄\n]+/

    # Anything separated by at least two newlines.
    PARAGRAPHS = /[^\n]+(\n{2,}|\Z)/

    # Words a reader gets through in a minute, the divisor behind the read time.
    WORDS_PER_MINUTE = 200

    REPLACE = [
      MarkupRegex::BOLD_ITALIC,
      MarkupRegex::ITALIC_ASTERISK,
      MarkupRegex::ITALIC_UNDERSCORE,
      MarkupRegex::BOLD,
      MarkupRegex::STRIKETHROUGH,
      MarkupRegex::IMAGE,
      MarkupRegex::LINK,
      MarkupRegex::LINK_ALT,
      MarkupRegex::LIST,
      MarkupRegex::ORDERED_LIST,
      MarkupRegex::BLOCK_QUOTE,
      MarkupRegex::HEADER,
      MarkupRegex::HEADER_UNDER,
      MarkupRegex::CODE_BLOCK,
      MarkupRegex::TABLE,
      MarkupRegex::MATH,
      MarkupRegex::FOOTNOTE_ID,
      MarkupRegex::FOOTNOTE,
    ].freeze

    REMOVE = [
      MarkupRegex::HORIZONTAL_RULE,
    ].freeze

    # One count's result: four tallies and a read time broken into hours,
    # minutes and seconds.
    Result = Data.define(
      :characters,
      :words,
      :sentences,
      :paragraphs,
      :read_time,
    )

    # `callback` is handed a Result on the main loop each time a count lands.
    def initialize(&callback)
      @callback = callback
      @counting = false
      @pending_text = nil
      @queue = Thread::Queue.new
      @worker = start_worker
    end

    # Counts the stats for `text`. While a count is running the text is held
    # back and counted once that one lands, so a burst of keystrokes never
    # queues up a count per key.
    def count(text)
      if @counting
        @pending_text = text
      else
        @counting = true
        @pending_text = nil
        @queue.push(text)
      end
    end

    # Ends the worker thread. The counter is not usable afterwards.
    def stop
      @queue.close
      @worker.join(1)
    end

    # The counting itself, exposed because it is a pure function of the text
    # and is worth being able to call without a main loop.
    def self.count_text(text)
      stripped = strip_markup(text)
      words = stripped.scan(WORDS).length
      new_result(stripped, words)
    end

    def self.strip_markup(text)
      REPLACE.inject(text) { |stripped, regexp| stripped.gsub(regexp, '\k<text>') }
        .then { |stripped| REMOVE.inject(stripped) { |acc, regexp| acc.gsub(regexp, '') } }
    end

    def self.new_result(stripped, words)
      Result.new(
        characters: stripped.scan(CHARACTERS).length,
        words:      words,
        sentences:  stripped.scan(SENTENCES).length,
        paragraphs: stripped.scan(PARAGRAPHS).length,
        read_time:  read_time(words),
      )
    end

    # Hours, minutes and seconds, each truncated the way upstream's repeated
    # divmod truncates them.
    def self.read_time(words)
      (words.to_f / WORDS_PER_MINUTE * 60).then do |seconds|
        [(seconds / 3600).to_i, (seconds % 3600 / 60).to_i, (seconds % 60).to_i]
      end
    end

    private

      def start_worker
        Thread.new do
          while (text = next_text)
            self.class.count_text(text).then do |result|
              GLib::Idle.add do
                @counting = false
                if @pending_text
                  count(@pending_text)
                end
                @callback&.call(result)
                false
              end
            end
          end
        end
      end

      # Takes the most recent text in the queue and drops the ones behind it.
      def next_text
        @queue.pop.then do |text|
          until @queue.empty?
            text = @queue.pop
          end
          text
        end
      end
  end
end
