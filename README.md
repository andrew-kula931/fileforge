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

# Export Markdown to PDF (defaulting to pdflatex)
cabal run fileforge -- -i notes.md -o notes.pdf --formatted

# Export to PDF using a specific engine (e.g. tectonic, xelatex)
cabal run fileforge -- -i notes.md -o notes.pdf --pdf-engine tectonic --formatted

# Use a custom folder containing helper tools (pdftotext, magick, etc.)
cabal run fileforge -- -i report.pdf -o report.txt -T tools/

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

## External Tool Dependencies & Resolution

FileForge invokes external tools for specific operations:
- **PDF Input**: requires Poppler's `pdftotext`.
- **PDF Asset Extraction (`--assets`)**: requires ImageMagick's `magick` (with a PDF delegate such as Ghostscript).
- **PDF Output**: uses Pandoc's PDF generator with a LaTeX engine (`pdflatex` by default, or an alternative specified via `--pdf-engine`, e.g. `tectonic`, `xelatex`, or `lualatex`).

### Portable Discovery Order
Instead of requiring executables to be manually configured in the system `PATH`, FileForge resolves each tool using a prioritized 4-tier lookup:
1. **CLI Flag**: `--tools-dir DIR` (or `-T DIR`) or direct executable via `--pdf-engine`.
2. **Environment Variables**: Tool-specific (`PDFTOTEXT_PATH`, `MAGICK_PATH`, `PDF_ENGINE_PATH`) or `FILEFORGE_TOOLS_DIR`.
3. **Application Sibling Directories**: Checks `<exe_dir>/tools/`, `<exe_dir>/bin/`, and `<exe_dir>/` relative to the running binary.
4. **System `PATH`**: Standard system path lookup via OS environment.

---

## Platform Setup & Installation

### Windows (x86_64)

#### Primary: Zero-Install Portable Setup (Recommended)
FileForge can run completely standalone without installing packages or modifying system environment variables.
Run the bundled PowerShell script:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/fetch-tools.ps1
```
This automatically downloads standalone Windows builds of `pdftotext.exe`, `magick.exe`, and `tectonic.exe` directly into the `tools/` directory.

Alternatively, you can manually place `pdftotext.exe` and `magick.exe` inside a `tools/` folder next to `fileforge.exe`.

#### Alternative: Windows Package Manager (Winget)
If you prefer installing tools system-wide:
```powershell
winget install poppler ImageMagick.ImageMagick

# For PDF export:
winget install Tectonic.Tectonic
# or
winget install MiKTeX.MiKTeX
```

---

### Linux (Arch Linux)

Install the dependencies using `pacman`:
```sh
sudo pacman -S poppler imagemagick texlive-basic
```
*(Optional) If you prefer using Tectonic for standalone PDF generation:*
```sh
sudo pacman -S tectonic
```

---

## Tests

```sh
cabal test fileforge-cli --test-show-details=direct
```
