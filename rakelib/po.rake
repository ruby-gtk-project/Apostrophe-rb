# frozen_string_literal: true

require 'fileutils'

# Translation tasks for po/. Ported in spirit from upstream's
# po/update_translations.sh and meson's i18n module, rebuilt around the
# `gettext` Ruby gem's rxgettext/rmsgfmt and GNU gettext's msgmerge rather
# than meson/ninja, since this port has no meson build.
#
# rake po:pot      # (re)generate po/apostrophe-rb.pot from po/POTFILES.in
# rake po:update   # msgmerge every po/<lang>.po in po/LINGUAS against the pot
# rake po:compile  # rmsgfmt every po/<lang>.po into data/locale/<lang>/LC_MESSAGES
#
# `rake po:update` then `rake po:compile` is upstream's "pull translations,
# build the catalogue" pair, run after `rake po:pot` whenever a translatable
# string is added, changed or removed.
module Po
  ROOT = File.expand_path('..', __dir__)
  DOMAIN = 'apostrophe-rb'
  POT_FILE = File.join(ROOT, 'po', "#{DOMAIN}.pot")
  LOCALE_DIR = File.join(ROOT, 'data', 'locale')

  module_function

  def linguas
    File.readlines(File.join(ROOT, 'po', 'LINGUAS'), chomp: true).reject(&:empty?)
  end

  def potfiles
    File.readlines(File.join(ROOT, 'po', 'POTFILES.in'), chomp: true)
      .reject { |line| line.empty? || line.start_with?('#') }
  end
end

namespace :po do
  desc 'Generate po/apostrophe-rb.pot from the files listed in po/POTFILES.in'
  task :pot do
    sh(
      'rxgettext',
      '--package-name', Po::DOMAIN,
      '--copyright-holder', 'ruby-gtk-project',
      '--sort-by-msgid',
      '-o', Po::POT_FILE,
      *Po.potfiles,
    )
  end

  desc 'Merge po/apostrophe-rb.pot into every po/<lang>.po in po/LINGUAS'
  task update: :pot do
    Po.linguas.each do |lang|
      po_file = File.join(Po::ROOT, 'po', "#{lang}.po")
      if File.exist?(po_file)
        sh('msgmerge', '--update', '--backup=none', po_file, Po::POT_FILE)
      else
        warn("po/#{lang}.po does not exist; skipping (run `rake po:new[#{lang}]` first)")
      end
    end
  end

  desc 'Compile every po/<lang>.po into data/locale/<lang>/LC_MESSAGES/apostrophe-rb.mo'
  task :compile do
    Po.linguas.each do |lang|
      po_file = File.join(Po::ROOT, 'po', "#{lang}.po")
      next unless File.exist?(po_file)

      mo_dir = File.join(Po::LOCALE_DIR, lang, 'LC_MESSAGES')
      FileUtils.mkdir_p(mo_dir)
      sh('rmsgfmt', po_file, '-o', File.join(mo_dir, "#{Po::DOMAIN}.mo"))
    end
  end

  desc 'Create a new po/<lang>.po from the current .pot (rake "po:new[xx]")'
  task :new, [:lang] => :pot do |_task, args|
    lang = args.fetch(:lang) { abort('usage: rake "po:new[xx]"') }
    po_file = File.join(Po::ROOT, 'po', "#{lang}.po")
    if File.exist?(po_file)
      abort("po/#{lang}.po already exists")
    end

    sh('rmsginit', '--input', Po::POT_FILE, '--output', po_file, '--locale', lang)
  end
end

desc 'Update and compile every translation catalogue (po:update + po:compile)'
task po: ['po:update', 'po:compile']
