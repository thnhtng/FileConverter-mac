# Removes the File Converter right-click menu and %LOCALAPPDATA%\FileConverter.
# ffmpeg / ImageMagick installed by winget are left in place (other apps may
# use them): `winget uninstall Gyan.FFmpeg ImageMagick.ImageMagick`.
$ErrorActionPreference = 'Stop'
$installDir = Join-Path $env:LOCALAPPDATA 'FileConverter'
$module = Join-Path $installDir 'FileConverter.psm1'
if (-not (Test-Path $module)) { $module = Join-Path $PSScriptRoot 'FileConverter.psm1' }
Import-Module $module -Force
$formatsPath = Join-Path (Split-Path -Parent $module) 'formats.json'
if (-not (Test-Path $formatsPath)) { $formatsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'shared\formats.json' }
$formats = Get-FcFormats -Path $formatsPath
$removed = 0
foreach ($key in (Get-FcMenuRoots -Formats $formats)) {
    if (Test-Path "HKCU:\$key") { Remove-Item -Path "HKCU:\$key" -Recurse -Force; $removed++ }
}
Write-Host ("Removed {0} menu entries." -f $removed)
if ((Split-Path -Parent $module) -eq $installDir) {
    Set-Location $env:TEMP
    Remove-Item -LiteralPath $installDir -Recurse -Force
    Write-Host "Removed $installDir"
}
