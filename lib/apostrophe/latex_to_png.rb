# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'

module Apostrophe
  # LatexToPng renders a LaTeX formula to a transparent PNG, which the inline
  # preview popover shows when the cursor is inside `$maths$`.
  #
  # Ported from apostrophe/latex_to_PNG.py, which is in turn based on Stuart
  # Rackham's latex2png.py.
  #
  # The pipeline is the same two programs upstream drives: `latex` writes a DVI
  # from a minimal document, then `dvipng` crops it tight and renders it at the
  # requested resolution. When `latex` produces no DVI its own error lines —
  # the ones starting "! " — are what comes back, because those name the
  # mistake in the formula.
  class LatexToPng
    TEX_HEADER = <<~'LATEX'
      \documentclass{article}
      \usepackage{amsmath}
      \usepackage{amsthm}
      \usepackage{amssymb}
      \usepackage{bm}
      \newcommand{\mx}[1]{\mathbf{\bm{#1}}} % Matrix command
      \newcommand{\vc}[1]{\mathbf{\bm{#1}}} % Vector command
      \newcommand{\T}{\text{T}}             % Transpose
      \pagestyle{empty}
      \begin{document}
    LATEX

    TEX_FOOTER = '\end{document}'

    DEFAULT_DPI = 300

    # Raised when `latex` rejects the formula. The message is LaTeX's own
    # complaint, which is what the popover shows in place of the image.
    class RenderError < StandardError; end

    # Renders `formula` as inline maths and returns the path of a PNG that
    # lives until this renderer is asked for another one. Upstream returns a
    # (success, value) pair; here a failure raises, so the caller cannot use an
    # error message as a file name by accident.
    def generate_png(formula, dpi: DEFAULT_DPI)
      discard_previous
      @directory = Dir.mktmpdir('apostrophe-latex')
      File.join(@directory, 'formula.png').then do |outfile|
        latex_to_png("$#{formula}$", outfile, dpi)
        outfile
      end
    end

    # Removes the directory holding the last render. Called when the popover
    # closes, and before each new render.
    def discard_previous
      if @directory && File.directory?(@directory)
        FileUtils.remove_entry(@directory)
      end
      @directory = nil
    end

    private

      def latex_to_png(tex, outfile, dpi)
        directory = File.dirname(outfile)
        texfile = File.join(directory, 'formula.tex')
        dvifile = File.join(directory, 'formula.dvi')

        File.write(texfile, "#{TEX_HEADER}\n#{tex.strip}\n#{TEX_FOOTER}\n")

        # `latex` resolves its own auxiliary files relative to the working
        # directory, so it is run with the temporary directory as its cwd
        # rather than with chdir around the whole process, which upstream does
        # and which is not safe with a UI running.
        output, = Open3.capture2e(
          'latex',
          '-halt-on-error',
          File.basename(texfile),
          chdir: directory,
        )

        unless File.file?(dvifile)
          raise RenderError, latex_errors(output)
        end

        dvi_to_png(dvifile, outfile, dpi)
      end

      def dvi_to_png(dvifile, outfile, dpi)
        Open3.capture2e(

          'dvipng',
          '-D',

          dpi.to_s,
          '-T',

          'tight',
          '-x',

          '1000',
          '-z',

          '9',
          '-bg',

          'Transparent',
          '-o',

          outfile,
          dvifile,

        ).then do |output, status|
          unless status.success?
            raise RenderError, output.strip
          end
        end
      end

      # LaTeX prefixes each complaint with "! "; stripping that off and joining
      # them is the message upstream builds.
      def latex_errors(output)
        output.lines.select { |line| line.start_with?('!') }
          .map { |line| line[2..].to_s }
          .join
          .chomp
          .then { |message| message.empty? ? 'latex produced no output' : message }
      end
  end
end
