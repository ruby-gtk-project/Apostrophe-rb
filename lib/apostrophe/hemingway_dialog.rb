# frozen_string_literal: true

require 'adwaita'
require_relative 'helpers'

module Apostrophe
  # HemingwayDialog explains Hemingway mode: text can be added but never
  # removed, which is the point of the exercise.
  #
  # Ported from data/ui/AboutHemingway.ui, an AdwMessageDialog with a single
  # "Close" response.
  class HemingwayDialog
    Helpers.bind_gettext(self)

    def present(parent)
      dialog(parent).present
    end

    private

      def body
        _(
          "The Hemingway Mode mimics the experience of writing on a typewriter, not allowing you to delete any text or doing any kind of editing.\n\n" \
          'Only being able to move forward may be frustrating, but can be an interesting exercise for improving your writing skills, gaining focus or facing the task on hand with a different mindset.',
        )
      end

      def dialog(parent)
        Adwaita::MessageDialog.new(parent, _('Hemingway Mode'), body).tap do |dialog|
          dialog.add_response('cancel', _('Close'))
          dialog.close_response = 'cancel'
        end
      end
  end
end
