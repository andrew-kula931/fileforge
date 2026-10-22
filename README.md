# FileForge

This repository presents a CLI tool that performs operations on files.

## Features

- Reads PDF, DOCX, and Markdown (`.md` or `.markdown`) files.
- Writes UTF-8 text (`.txt`), DOCX, and Markdown files.
- Preserves supported document structure with `--formatted`, or flattens the
  content to plain text without it.

## Usage

```sh
# Plain text (defaults to report.txt)
cabal run fileforge -- -i report.pdf

# Preserve headings, emphasis, lists, and paragraphs when converting documents
cabal run fileforge -- -i report.docx -o report.md --formatted
cabal run fileforge -- -i notes.md -o notes.docx --formatted

# Flatten Markdown into unformatted text
cabal run fileforge -- -i notes.markdown -o notes.txt
```

Formats are selected by file extension, case-insensitively. Omitting `--output`
(`-o`) defaults to the input path with a `.txt` extension. Input and output must be
different files.

Without `--formatted`, whitespace is collapsed and source formatting is removed,
including for DOCX and Markdown output. With `--formatted`, text output retains
paragraph structure; DOCX and Markdown retain the structure supported by Pandoc.
Conversion does not reproduce exact page layout, fonts, or styling.

PDF input requires Poppler's `pdftotext` executable on `PATH`. Its extracted text
is processed through Pandoc, as before; PDF structure preservation is limited to
what that extraction retains. PDF output and OCR of scanned PDFs are not supported.

## Tests

```sh
cabal test fileforge-cli --test-show-details=direct
```