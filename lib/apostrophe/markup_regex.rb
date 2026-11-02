# frozen_string_literal: true

module Apostrophe
  # MarkupRegex is the markdown grammar the editor highlights, the statistics
  # counter strips and the text buffer uses to continue lists.
  #
  # Ported from apostrophe/markup_regex.py.
  #
  # Three systematic differences between Python's `re` and Ruby's Onigmo had to
  # be worked through rather than copied across:
  #
  # * Python's `^`/`$` anchor the whole string unless `re.M` is passed, while
  #   Ruby's always anchor a line. The patterns upstream compiles without
  #   `re.M` therefore use `\A`/`\Z` here; only the ones compiled with `re.M`
  #   keep `^`/`$`.
  # * `re.S` (dot matches newline) is Ruby's `/m`, which is why some patterns
  #   below carry an `m` flag upstream does not spell the same way.
  # * Onigmo disables numbered backreferences in a pattern that also has named
  #   groups, so upstream's `\1`/`\2` repeats become named groups referenced
  #   through `\k<name>`. Every group name upstream reads back — `text`, `url`,
  #   `title`, `indent`, `symbol`, `prefix`, `number`, `delimiter`, `level`,
  #   `symbols`, `content`, `block`, `id`, `ticks` — is preserved.
  #
  # `#` is escaped throughout: an unescaped `#{` inside a Ruby regex literal is
  # string interpolation, not a quantified literal.
  module MarkupRegex
    ITALIC_ASTERISK = /(?<!\\)\*[^\s*](?<text>.*?\S?.*?)(?<!\\)\*/
    ITALIC_UNDERSCORE = /(?<!(\\|\S))_[^\s_](?<text>.*?\S?.*?)(?<!\\)_/
    BOLD = /(?<marker>\*\*|__)[^\s*](?<text>.*?\S.*?)\k<marker>/
    BOLD_ITALIC = /(?:(?<bold_open>\*\*|__)(?<italic_open>[*_])|(?<italic_open2>[*_])(?<bold_open2>\*\*|__))[^\s*](?<text>.*?\S.*?)(?:\k<bold_open2>\k<italic_open2>|\k<italic_open>\k<bold_open>)/
    STRIKETHROUGH = /~~(?<text>.*?\S.*?)~~/
    CODE = /(?<!`)(?<ticks>`+)(?!`)(?<content>.+?)(?<!`)\k<ticks>(?!`)/
    LINK = /\[(?<text>.*?)\]\((?<url>.+?)(?: "(?<title>.+)")?\)/
    LINK_ALT = /<(?<text>(?<url>[A-Za-z][A-Za-z0-9.+-]{1,31}:[^<>\x00-\x20]*|(?:[a-zA-Z0-9.!\#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*)))>/
    IMAGE = /!\[(?<text>.*)\]\((?<url>.+?)(?: "(?<title>.+)")?\)/
    HORIZONTAL_RULE = /(?:\A|\n{2,})(?<symbols> {0,3}[*\-_]{3,} *)(?:\n{2,}|\Z)/
    LIST = /(?:\A|\n)(?<content>(?<indent>(?:\t| {4})*)(?<symbol>(?:[\-*+])) (?:\t| {4})*(?<text>.+(?:\n+ \k<indent>.+)*)?)/
    ORDERED_LIST = /(?:\A|\n)(?<content>(?<indent>(?:\t| {4})*)(?<prefix>(?:(?<number>\d)|(?:[a-z]))+(?<delimiter>[.)]))(?:\t| {4}| )(?<text>.+(?:\n+ {2}\k<indent>.+)*)?)/
    BLOCK_QUOTE = /^ {0,3}(?:> ?)+(?<text>.+)/
    HEADER = /^ {0,3}(?<level>\#{1,6}) (?<text>[^\n]+)/
    HEADER_UNDER = /(?:\A\n*|\n\n)(?<text>[^\s].+)\n {0,3}[=\-]+(?: +?\n|\Z)/
    CODE_BLOCK = /^ {0,3}(?<block>(?<ticks>[`~]{3})(?<text>.+?)(?<! ) {0,3}\k<ticks>)(?:\s+?$|$)/m
    TABLE = /\A[\-+]{5,}\n(?<text>.+?)\n[\-+]{5,}\n/m
    MATH = /(?<delimiter>[$]{1,2})(?<text>[^`\\ ]{1,2}|[^` ].+?[^`\\ ])\k<delimiter>/m
    FOOTNOTE_ID = /[^\s]+\[\^(?<id>(?<text>[^\s]+))\]/
    FOOTNOTE = /(?:^\n*|\n\n)\[\^(?<id>[^\s]+)\]: (?<text>(?:[^\n]+|\n+(?=(?:\t| {4})))+)(?:\n+|$)/
  end
end
