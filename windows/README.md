# File Converter for Windows — right-click menu

Right-click a file in Explorer → **Convert with File Converter** → pick a
format. The converted file is written next to the original
(`clip.mov` → `clip.mp4`, or `clip (1).mp4` if that name is taken); the
original is never changed. A notification says when it's done; errors show
the tool's message.

| Right-click on | Offered formats |
|---|---|
| Video (mp4, mov, mkv, avi, webm, wmv, …) | MP4 · MKV · WEBM · AVI · OGV · GIF · MP3 · AAC · OGG · FLAC · WAV |
| Audio (mp3, wav, m4a, flac, ogg, …) | MP3 · AAC · OGG · FLAC · WAV |
| Image (jpg, png, webp, heic, tiff, bmp, …) | GIF · JPG · PNG · WEBP · AVIF · ICO · PDF |
| GIF | MP4 · MKV · WEBM · AVI · OGV · GIF · JPG · PNG · WEBP · AVIF · ICO |
| Word / Excel / PowerPoint / OpenDocument | PDF (only when LibreOffice is installed) |

Formats and quality defaults come from `shared/formats.json`, the same
table the macOS app, the web converter and the browser extension use.

## Install

In PowerShell (no admin rights needed):

```powershell
irm https://raw.githubusercontent.com/thnhtng/FileConverter-mac/main/windows/install.ps1 | iex
```

It installs ffmpeg and ImageMagick with winget (if missing), copies the
converter to `%LOCALAPPDATA%\FileConverter`, and registers the menu under
`HKCU\Software\Classes` (per user). On **Windows 11** the classic menu is
under **Show more options** (or Shift+F10).

From a clone: `powershell -ExecutionPolicy Bypass -File windows\install.ps1`.
Set `$env:FC_SKIP_TOOLS = '1'` to skip winget.

Uninstall: `powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\FileConverter\uninstall.ps1"`.

## Files

- `FileConverter.psm1` — pure logic: format lookup, conversion plans
  (ffmpeg / ImageMagick / LibreOffice command lines), the registry layout
  for the menu. Works on Windows PowerShell 5.1 and PowerShell 7.
- `fc-convert.ps1` — what the menu runs: `fc-convert.ps1 -To mp4 "<file>"`.
- `install.ps1`, `uninstall.ps1`, `FileConverter.ico`.
- `tests/run-tests.ps1` — 42 checks; the conversion ones run real
  ffmpeg/ImageMagick when installed (`pwsh windows/tests/run-tests.ps1`).
  CI runs them on Windows (PowerShell 5.1 and 7) and installs/uninstalls
  the menu in the registry: `.github/workflows/windows.yml`.
