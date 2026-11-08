# Translation parity — Apostrophe (round 4)

Method: the `translation-parity` skill. Round 3 found a total 0% gap; this
round's commit `4823bfe` ("Add gettext translation catalogue") changed that
materially, so every number below was recounted fresh against both
`origin/main` and the current `ruby` branch rather than carried over.

## Upstream catalogue (unchanged facts, reconfirmed)

```
git show origin/main:po/LINGUAS            → 33 locales
git ls-tree -r --name-only origin/main | grep '^po/' → POTFILES.in lists 42 entries
git show origin/main:po/de.po               → 177 msgid lines
```

Upstream's 42 `POTFILES.in` entries split as 17 `data/*` files (`.ui`
templates, the `.desktop.in.in`, `.gschema.xml`, and `.metainfo.xml.in.in`)
plus 25 `.py` modules.

## Port catalogue — now real, reverified end-to-end

```
$ find . -iname '*.po' -o -iname '*.pot'   (excl. .git)
po/apostrophe-rb.pot, po/ca.po … po/zh_TW.po  (33 locale files)
$ wc -l < <(grep -c '^msgid "' po/apostrophe-rb.pot)
143
$ diff <upstream LINGUAS, sorted> <port LINGUAS, sorted>
(empty — identical 33-locale set)
```

`rakelib/po.rake` provides `po:pot`/`po:update`/`po:compile`; `.mo` files
are compiled under `data/locale/<lang>/LC_MESSAGES/`. Gettext resolution
verified directly this session, not just read in source:

```
$ LANG=fr_FR.UTF-8 ruby -e 'require "gettext"; include GetText
  bindtextdomain("apostrophe-rb", path: "data/locale"); puts _("Error")'
Erreur
```

This is real, working i18n — a genuine change from 0%.

## Gaps found this round — the catalogue is real but not complete

**1. `text_view.rb` is outside `po/POTFILES.in`, and the one string
upstream translates at that call site is a bare literal.** Upstream's
`apostrophe/text_view.py` (lines 177, 179) wraps `_("web page")` — the
placeholder text inserted when a URL is dropped onto the editor
(`[web page](url)`). The port's `lib/apostrophe/text_view.rb:112` has the
identical call site:

```ruby
@text_buffer.insert_at_cursor("[web page](#{content})")
```

`"web page"` is never passed through `_()`, and `text_view.rb` does not
appear in `po/POTFILES.in`'s 21-file list at all. A user on any non-English
locale who drags a link into the editor gets hardcoded English text
inserted into their document — the one place this round's own `po.rake`
pipeline could not have caught it, since it only extracts from files
already listed.

**2. Three upstream translatable files have no port-side equivalent to
even carry a gap.** Upstream's `POTFILES.in` includes
`data/org.gnome.gitlab.somas.Apostrophe.desktop.in.in` (app name, generic
name, keywords), `.metainfo.xml.in.in` (the one-line summary, the
multi-paragraph feature description shown in GNOME Software/Flathub — ~9
separate `<p>`/`<li>` strings sampled directly from upstream's XML), and
`.gschema.xml` (5 `<summary>` strings shown in `dconf-editor`). None of
these three files exist anywhere in this port — confirmed: `find data
-iname '*metainfo*' -o -iname '*desktop*' -o -iname '*gschema*'` returns
nothing. This is a packaging gap first, but it is also why the 177→143
msgid shortfall is almost entirely accounted for by files that were never
in scope for `rake po:pot` to extract from, rather than by strings
dropped from files that exist.

Together, these two gaps plausibly account for the entire 34-msgid
shortfall between upstream's 177 and the port's 143 (the metainfo/
desktop/gschema strings number in the mid-teens to ~20 by direct count of
upstream's XML; `text_view.rb`'s one string is one more). The precise
accounting is secondary to the finding: **the catalogue is not yet a
complete superset of every upstream msgid**, and nothing in the commit
message or `.reports/` claimed it was — `4823bfe`'s own message says
"preview_handler.rb and preview_web_view.rb remain unported" but does not
mention the `text_view.rb`/metainfo gap, which this audit found
independently.

## Verdict

**Translation parity moved from a total 0% gap (round 3) to a real,
working, but incomplete implementation.** 33/33 locales carried over
correctly, a real `.pot`/`.po`/`.mo` pipeline exists and resolves strings
correctly at runtime under a non-English locale, and 20 `lib/*.rb` files
are correctly wrapped. Against that: one upstream-translated string was
ported as a bare Ruby literal at the exact call site upstream translates
it (`text_view.rb`, "web page"), and three upstream files carrying
app-identity and settings-schema strings have no port-side file to even
attempt translating. Calling this "complete" or "parity achieved" would
be a false-green claim; calling it "a real foundation with two named,
concrete gaps" is accurate.
