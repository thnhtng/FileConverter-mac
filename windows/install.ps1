# File Converter for Windows - installer.
#
#   irm https://raw.githubusercontent.com/thnhtng/FileConverter-mac/main/windows/install.ps1 | iex
#
# or, from a clone:  powershell -ExecutionPolicy Bypass -File windows\install.ps1
#
# 1. Installs ffmpeg and ImageMagick with winget (skipped if already present).
# 2. Copies the converter to %LOCALAPPDATA%\FileConverter.
# 3. Adds "Convert with File Converter" > MP4 / MP3 / JPG / ... to the
#    Explorer right-click menu, per file type, for the current user only
#    (HKCU - no admin rights). Office files get "PDF" if LibreOffice is
#    installed. On Windows 11 the menu is under "Show more options".
#
# Options (environment variables, since `irm | iex` can't take parameters):
#   $env:FC_SKIP_TOOLS = '1'   don't run winget
#   $env:FC_BRANCH     = 'main' branch to download from
# Uninstall: %LOCALAPPDATA%\FileConverter\uninstall.ps1

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # makes Invoke-WebRequest much faster on 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Write-FcStep([string]$Text) { Write-Host "==> $Text" -ForegroundColor Cyan }

if ($env:OS -ne 'Windows_NT') { throw 'This installer is for Windows. On a Mac, use install.sh.' }

$repo = 'thnhtng/FileConverter-mac'
$branch = if ($env:FC_BRANCH) { $env:FC_BRANCH } else { 'main' }
$installDir = Join-Path $env:LOCALAPPDATA 'FileConverter'
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

# --- files -----------------------------------------------------------------
$files = @{
    'FileConverter.psm1' = 'windows/FileConverter.psm1'
    'fc-convert.ps1'     = 'windows/fc-convert.ps1'
    'uninstall.ps1'      = 'windows/uninstall.ps1'
    'FileConverter.ico'  = 'windows/FileConverter.ico'
    'formats.json'       = 'shared/formats.json'
}
$localRoot = $null
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'FileConverter.psm1'))) { $localRoot = Split-Path -Parent $PSScriptRoot }
Write-FcStep ("Copying File Converter to {0}" -f $installDir)
foreach ($name in $files.Keys) {
    $target = Join-Path $installDir $name
    if ($localRoot) {
        Copy-Item -LiteralPath (Join-Path $localRoot ($files[$name] -replace '/', '\')) -Destination $target -Force
    } else {
        Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/$repo/$branch/$($files[$name])" -OutFile $target
    }
}
Import-Module (Join-Path $installDir 'FileConverter.psm1') -Force

# --- tools -----------------------------------------------------------------
$tools = Find-FcTools
if (-not $env:FC_SKIP_TOOLS) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    $wanted = @(@{ Tool = 'ffmpeg'; Id = 'Gyan.FFmpeg' }, @{ Tool = 'magick'; Id = 'ImageMagick.ImageMagick' })
    foreach ($w in $wanted) {
        if ($tools[$w.Tool]) { Write-FcStep ("{0} found: {1}" -f $w.Tool, $tools[$w.Tool]); continue }
        if (-not $winget) { Write-Warning ("winget isn't available - install {0} yourself (winget id {1})." -f $w.Tool, $w.Id); continue }
        Write-FcStep ("Installing {0} with winget..." -f $w.Id)
        & $winget.Source install --id $w.Id -e --silent --accept-source-agreements --accept-package-agreements | Out-Host
    }
    $tools = Find-FcTools
}
foreach ($t in @('ffmpeg', 'magick')) {
    if (-not $tools[$t]) { Write-Warning ("{0} not found - conversions that need it will fail until it's installed. Re-run this installer afterwards." -f $t) }
}
$tools | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $installDir 'tools.json') -Encoding UTF8

# --- right-click menu ------------------------------------------------------
Write-FcStep 'Adding the right-click menu'
$formats = Get-FcFormats -Path (Join-Path $installDir 'formats.json')
foreach ($key in (Get-FcMenuRoots -Formats $formats)) {
    if (Test-Path "HKCU:\$key") { Remove-Item -Path "HKCU:\$key" -Recurse -Force }
}
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$entries = Get-FcMenuEntries -Formats $formats -ScriptPath (Join-Path $installDir 'fc-convert.ps1') `
    -IconPath (Join-Path $installDir 'FileConverter.ico') -IncludeOffice:([bool]$tools['soffice']) -PowerShellExe ('"{0}"' -f $psExe)
foreach ($entry in $entries) {
    $path = "HKCU:\$($entry.Key)"
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    foreach ($name in $entry.Values.Keys) {
        if ($name -eq '(default)') { Set-Item -Path $path -Value $entry.Values[$name] }
        else { New-ItemProperty -Path $path -Name $name -Value $entry.Values[$name] -PropertyType String -Force | Out-Null }
    }
}

Write-Host ''
Write-Host 'Done. Right-click a video, audio file or image in Explorer -> "Convert with File Converter" -> pick a format.' -ForegroundColor Green
Write-Host 'Windows 11: the menu is under "Show more options" (or Shift+F10).'
Write-Host ("Uninstall: powershell -ExecutionPolicy Bypass -File `"{0}`"" -f (Join-Path $installDir 'uninstall.ps1'))
