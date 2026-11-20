# Revision history for fileforge

## 0.1.0.0 -- YYYY-mm-dd

* First version. Released on an unsuspecting world.
* Add DOCX and Markdown inputs and outputs alongside PDF input and text output.
  Formats are selected by file extension; output still defaults to `.txt`.
* Extend `--formatted` to retain supported document structure in DOCX and
  Markdown output; unformatted conversions flatten content to plain text.
* Add `--assets` for PDF input to render each page into an `assets/` directory
  via ImageMagick's `magick` command.
* Add PDF output via Pandoc and `pdflatex`, selected by a `.pdf` output
  extension.
* Add `--template` (`-t`) option for LaTeX output to wrap generated LaTeX in
  custom templates (e.g. `app/examples/ieee_template.tex`), supporting Pandoc
  template variables and auto-injecting `$body$` when omitted.
