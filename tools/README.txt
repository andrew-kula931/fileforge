FileForge Portable Tools Directory
----------------------------------

This directory ('tools') is automatically checked by FileForge when resolving
external helper tools on Windows and Linux before searching the system PATH.

Supported Helper Tools:
-----------------------
1. pdftotext.exe (Poppler)
   Required for reading and converting PDF input files.

2. magick.exe (ImageMagick)
   Required when extracting PDF pages as assets (--assets).

3. pdflatex.exe / tectonic.exe / xelatex.exe (LaTeX Engine)
   Required when exporting documents to PDF (--pdf-engine).

Automatic Setup (Windows):
--------------------------
To automatically download and populate these portable binaries, run:
  powershell -ExecutionPolicy Bypass -File ..\scripts\fetch-tools.ps1

System-Wide Alternative (Winget):
---------------------------------
If you prefer installing tools system-wide via Windows Package Manager:
  winget install poppler ImageMagick.ImageMagick
  # For PDF export:
  winget install Tectonic.Tectonic
  # or winget install MiKTeX.MiKTeX

Arch Linux:
-----------
On Arch Linux, install system packages via pacman:
  sudo pacman -S poppler imagemagick texlive-basic
