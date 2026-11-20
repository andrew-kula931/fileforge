# FileForge

This repository presents a CLI tool that performs operations/conversions on files.

## Features

- Reads PDF, DOCX, Latex, JSON, XML, and Markdown (`.md` or `.markdown`) files.
- Writes to any of the aforementioned formats, including PDF.
- Preserves supported document structure with `--formatted`, or flattens the
  content to plain text without it.
- Supports custom LaTeX templates when converting to LaTeX with `--template` (`-t`).

## Usage

```sh
# Plain text (defaults to report.txt)
cabal run fileforge -- -i report.pdf

# Preserve headings, emphasis, lists, and paragraphs when converting documents
cabal run fileforge -- -i report.docx -o report.md --formatted
cabal run fileforge -- -i notes.md -o notes.docx --formatted

# Convert Markdown to LaTeX with a template
cabal run fileforge -- -i notes.md -o paper.tex --template app/examples/some_template.tex --formatted

# Export Markdown to PDF
cabal run fileforge -- -i notes.md -o notes.pdf --formatted

# Flatten Markdown into unformatted text
cabal run fileforge -- -i notes.markdown -o notes.txt

# Render each PDF page into assets/ next to the output file
cabal run fileforge -- -i report.pdf -o report.md --assets
```

Formats are selected by file extension, case-insensitively. Omitting `--output`
(`-o`) defaults to the input path with a `.txt` extension. Input and output must be
different files.

Without `--formatted`, whitespace is collapsed and source formatting is removed,
including for DOCX, Markdown, and PDF output. With `--formatted`, text output retains
paragraph structure; DOCX, Markdown, and PDF retain the structure supported by Pandoc.
Conversion does not reproduce exact page layout, fonts, or styling.

With `--assets` on PDF input, each page is rendered as `assets/page-NNN.png`
beside the output file using ImageMagick's `magick` command. `--assets` is
rejected for non-PDF inputs.

With `--template` (`-t`), you can provide a custom LaTeX template when converting
to LaTeX (`.tex`). It supports Pandoc template variables (`$body$`, `$title$`, etc.)
and automatically injects `$body$` before `\end{document}` if omitted. `--template`
is rejected for non-LaTeX outputs. An example IEEE conference template is available
at `app/examples/ieee_template.tex`.

PDF input requires Poppler's `pdftotext` executable on `PATH`. Its extracted text
is processed through Pandoc, as before; PDF structure preservation is limited to
what that extraction retains. PDF asset extraction additionally requires
ImageMagick (`magick`) with a PDF delegate (typically Ghostscript). PDF output
uses Pandoc with `pdflatex` on `PATH`. OCR of scanned PDFs is not supported.

## Tests

```sh
cabal test fileforge-cli --test-show-details=direct
```
