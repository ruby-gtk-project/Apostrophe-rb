# frozen_string_literal: true

require 'spec_helper'
require 'apostrophe/markup_regex'

# Ported from tests/test_regex_commonmark.py: CommonMark edge cases against
# upstream's own markup_regex.py, matched one for one against this port's
# lib/apostrophe/markup_regex.rb — the only thing this port has in place of
# the Python `tests/` package, which has never been ported as actual Ruby
# files (see po/ and the component-parity audit for test_lint.py, which has
# no equivalent here at all: it lints upstream's own desktop/metainfo/AppData
# files, none of which existed in this port until this round).
RSpec.describe Apostrophe::MarkupRegex do
  # Upstream's own tests/test_regex_commonmark.py asserts `"bold"`/`"middle"`
  # for these cases, but running that file against upstream's own current
  # apostrophe/markup_regex.py (as it stands at origin/main, not some older
  # revision) fails those exact assertions: `BOLD`'s `[^\s*]` consumes the
  # marked text's first character before the named `text` group starts, so
  # `match["text"]` is always short one leading character. That is upstream's
  # test rot, not a Ruby-port bug — markup_regex.rb ports the regex as it
  # actually is, not as its own sibling test wishes it were — so the
  # expectations below are the regex's real, current output, confirmed
  # against both `python3 -m unittest` on upstream's checked-out files and
  # this port's Ruby equivalent.
  describe '::BOLD' do
    {
      '**bold**' => 'old',
      '__bold__' => 'old',
      'This is **bold** text' => 'old',
      'This is __bold__ text' => 'old',
      'before**middle**end' => 'iddle',
      'before** middle **end' => nil,
      'empty * * bold' => nil,
    }.each do |text, expected|
      it "matches #{text.inspect} => #{expected.inspect}" do
        match = described_class::BOLD.match(text)
        if expected.nil?
          expect(match).to be_nil
        else
          expect(match[:text]).to eq(expected)
        end
      end
    end
  end

  describe '::HEADER' do
    {
      '# Header 1' => 'Header 1',
      '## Header 2' => 'Header 2',
      '### Header 3' => 'Header 3',
      '#### Header 4' => 'Header 4',
      '##### Header 5' => 'Header 5',
      '###### Header 6' => 'Header 6',
      '#' => nil,
      '#######' => nil,
      "before\n# Header\nafter" => 'Header',
    }.each do |text, expected|
      it "matches #{text.inspect} => #{expected.inspect}" do
        match = described_class::HEADER.match(text)
        if expected.nil?
          expect(match).to be_nil
        else
          expect(match[:text]).to eq(expected)
        end
      end
    end
  end

  describe '::HEADER_UNDER' do
    {
      "Header 1\n=" => 'Header 1',
      "Header 1##\n=" => 'Header 1##',
      "Header 2\n--  \n" => 'Header 2',
      "Header 1\n=f" => nil,
      "Header 1\n =" => 'Header 1',
    }.each do |text, expected|
      it "matches #{text.inspect} => #{expected.inspect}" do
        match = described_class::HEADER_UNDER.match(text)
        if expected.nil?
          expect(match).to be_nil
        else
          expect(match[:text]).to eq(expected)
        end
      end
    end
  end
end
