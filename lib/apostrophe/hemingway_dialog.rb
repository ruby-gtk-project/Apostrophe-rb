# frozen_string_literal: true

require 'adwaita'

module Apostrophe
  # HemingwayDialog explains Hemingway mode: text can be added but never
  # removed, which is the point of the exercise.
  #
  # Ported from data/ui/AboutHemingway.ui, an AdwMessageDialog with a single
  # "Close" response.
  class HemingwayDialog
    BODY = <<~BODY.freeze
      The Hemingway Mode mimics the experience of writing on a typewriter, not allowing you to delete any text or doing any kind of editing.

      Only being able to move forward may be frustrating, but can be an interesting exercise for improving your writing skills, gaining focus or facing the task on hand with a different mindset.
    BODY

    def present(parent)
      dialog(parent).present
    end

    private

      def dialog(parent)
        Adwaita::MessageDialog.new(parent, 'Hemingway Mode', BODY).tap do |dialog|
          dialog.add_response('cancel', 'Close')
          dialog.close_response = 'cancel'
        end
      end
  end
end
