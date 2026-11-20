<#
.SYNOPSIS
    Downloads and sets up portable third-party binaries (Poppler, ImageMagick, Tectonic)
    into the 'tools' folder for FileForge on Windows.

.DESCRIPTION
    FileForge requires external helper tools for certain document operations:
      - pdftotext (Poppler): for reading PDF files
      - magick (ImageMagick): for extracting PDF page assets (--assets)
      - tectonic (Tectonic LaTeX engine): lightweight standalone PDF generator (--pdf-engine tectonic)

    This script automatically downloads standalone Windows builds and places the required
    executables and libraries directly into FileForge's 'tools' directory.
#>

[CmdletBinding()]
param (
    [switch]$IncludeTectonic = $true,
    [switch]$IncludeImageMagick = $true,
    [string]$TargetDir
)

$ErrorActionPreference = "Stop"

# Determine target tools directory
if (-not $TargetDir) {
    if (Test-Path (Join-Path $PSScriptRoot "..\tools")) {
        $TargetDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\tools"))
    } elseif (Test-Path (Join-Path $PSScriptRoot "tools")) {
        $TargetDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "tools"))
    } else {
        $TargetDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\tools"))
    }
}

if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("fileforge_tools_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  FileForge Windows Portable Tools Installer" -ForegroundColor Cyan
Write-Host "  Target directory: $TargetDir" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

try {
    # 1. Poppler for Windows (pdftotext.exe)
    Write-Host "`n[1/3] Downloading Poppler (pdftotext)..." -ForegroundColor Yellow
    $popplerZip = Join-Path $tempDir "poppler.zip"
    $popplerUrl = "https://github.com/oschwartz10612/poppler-windows/releases/download/v24.08.0-0/Release-24.08.0-0.zip"
    
    Invoke-WebRequest -Uri $popplerUrl -OutFile $popplerZip -UseBasicParsing
    
    $popplerExtract = Join-Path $tempDir "poppler_extracted"
    Expand-Archive -Path $popplerZip -DestinationPath $popplerExtract -Force
    
    # Locate Library/bin or bin directory inside archive
    $binDir = Get-ChildItem -Path $popplerExtract -Recurse -Directory -Filter "bin" | Select-Object -First 1
    if ($binDir) {
        Get-ChildItem -Path $binDir.FullName -File | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $TargetDir -Force
        }
        Write-Host "  [OK] Copied pdftotext and Poppler DLLs to: $TargetDir" -ForegroundColor Green
    } else {
        Write-Warning "Could not find bin directory in Poppler archive."
    }

    # 2. ImageMagick Portable (magick.exe)
    if ($IncludeImageMagick) {
        Write-Host "`n[2/3] Downloading ImageMagick Portable..." -ForegroundColor Yellow
        $imZip = Join-Path $tempDir "imagemagick.zip"
        $imUrl = "https://imagemagick.org/archive/binaries/ImageMagick-7.1.1-43-portable-Q16-x64.zip"
        
        try {
            Invoke-WebRequest -Uri $imUrl -OutFile $imZip -UseBasicParsing
            $imExtract = Join-Path $tempDir "im_extracted"
            Expand-Archive -Path $imZip -DestinationPath $imExtract -Force

            Get-ChildItem -Path $imExtract -Filter "magick*.exe" | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $TargetDir -Force
            }
            Get-ChildItem -Path $imExtract -Filter "*.dll" | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $TargetDir -Force
            }
            Write-Host "  [OK] Copied magick.exe and ImageMagick DLLs to: $TargetDir" -ForegroundColor Green
        } catch {
            Write-Warning "Direct portable ImageMagick download failed ($($_.Exception.Message))."
            Write-Host "  Alternative: run 'winget install ImageMagick.ImageMagick'" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host "`n[2/3] Skipping ImageMagick (not requested)." -ForegroundColor Gray
    }

    # 3. Tectonic Portable LaTeX Engine (tectonic.exe)
    if ($IncludeTectonic) {
        Write-Host "`n[3/3] Downloading Tectonic (Portable LaTeX Engine for PDF Export)..." -ForegroundColor Yellow
        $tectonicZip = Join-Path $tempDir "tectonic.zip"
        $tectonicUrl = "https://github.com/tectonic-typesetting/tectonic/releases/download/tectonic%400.15.0/tectonic-0.15.0-x86_64-pc-windows-msvc.zip"
        
        try {
            Invoke-WebRequest -Uri $tectonicUrl -OutFile $tectonicZip -UseBasicParsing
            $tectonicExtract = Join-Path $tempDir "tectonic_extracted"
            Expand-Archive -Path $tectonicZip -DestinationPath $tectonicExtract -Force

            $tectonicExe = Get-ChildItem -Path $tectonicExtract -Filter "tectonic.exe" -Recurse | Select-Object -First 1
            if ($tectonicExe) {
                Copy-Item -Path $tectonicExe.FullName -Destination $TargetDir -Force
                Write-Host "  [OK] Copied tectonic.exe to: $TargetDir" -ForegroundColor Green
            }
        } catch {
            Write-Warning "Tectonic download failed ($($_.Exception.Message))."
            Write-Host "  Alternative: run 'winget install Tectonic.Tectonic' or use standard MiKTeX/TeX Live." -ForegroundColor DarkYellow
        }
    } else {
        Write-Host "`n[3/3] Skipping Tectonic (not requested)." -ForegroundColor Gray
    }

    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host "  Portable tools setup completed successfully!" -ForegroundColor Green
    Write-Host "  FileForge can now be run without configuring PATH." -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
}
finally {
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
