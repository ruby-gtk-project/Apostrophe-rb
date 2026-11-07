# frozen_string_literal: true

require 'adwaita'
require_relative 'helpers'

module Apostrophe
  # Inhibitor asks the session not to log out while a document has unsaved
  # changes, and withdraws that request once the document is saved.
  #
  # Ported from apostrophe/inhibitor.py. The cookie is held so a second
  # `inhibit` while already inhibiting is a no-op, which is what keeps every
  # keystroke in an unsaved document from registering another inhibitor.
  class Inhibitor
    Helpers.bind_gettext(self)

    def initialize
      @cookie = 0
    end

    # `flags` is a Gtk::ApplicationInhibitFlags value, e.g. :logout.
    def inhibit(flags)
      if @cookie.zero?
        @cookie = Helpers.app.inhibit(
          Helpers.app.active_window,
          flags,
          _('Unsaved documents'),
        )
      end
    end

    def uninhibit
      unless @cookie.zero?
        Helpers.app.uninhibit(@cookie)
        @cookie = 0
      end
    end

    def inhibiting? = !@cookie.zero?
  end
end
