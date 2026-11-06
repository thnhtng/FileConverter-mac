# File Converter for macOS (native rewrite)

Native macOS rewrite of [Tichau/FileConverter](https://github.com/Tichau/FileConverter)
(Windows-only WPF app + Explorer shell extension): a Finder Quick Action +
companion SwiftUI app that converts files via ffmpeg, ImageMagick, and
LibreOffice. Built from scratch in Swift — WPF, COM, and the Windows
Registry have no macOS equivalent — reusing only the original project's
domain knowledge (supported formats, exact ffmpeg quality/bitrate formulas,
preset data model). Licensed GPL-3.0, same as the original (see `LICENSE.md`).

This is an internal/unofficial build, not affiliated with the upstream
project. No notarized/Developer-ID release — see "Install" below for what
that means in practice.

## Use it everywhere

One converter, four front ends, all driven by the same format table
(`shared/formats.json`, kept in sync with the Swift engine by
`SharedFormatsTests`):

| Where | How | Code |
|---|---|---|
| **Web** | Drop files on a page, pick a format, download. Runs in the browser (canvas for images, ffmpeg.wasm for audio/video/GIF) — nothing is uploaded. | `web/`, `scripts/build-web.sh`, deployed by `.github/workflows/pages.yml` |
| **Browser extension** | Right-click an image/video/audio on any page → *Download as MP4 / GIF / MP3 / JPG / PNG / WEBP…*; popup lists every media file on the page. Chrome/Edge/Brave/Arc/Opera; Safari via Xcode. Protected streams (YouTube etc.) are deliberately not supported. | `extension/` — see `extension/README.md` |
| **macOS** | Right-click in Finder → Quick Actions → *Convert to MP4 / MP3 / JPG…* (one click), *Convert with File Converter* (preset picker), *Check with File Converter* (Spec Check). | this app + `install.sh` |
| **Windows** | Right-click in Explorer → *Convert with File Converter* → format. `irm https://raw.githubusercontent.com/thnhtng/FileConverter-mac/main/windows/install.ps1 \| iex` | `windows/` — see `windows/README.md` |

## Install

One command installs Homebrew (if needed), ffmpeg/ImageMagick/LibreOffice,
and the app itself:

```sh
curl -fsSL https://raw.githubusercontent.com/thnhtng/FileConverter-mac/main/install.sh | bash
```

Then right-click any supported file in Finder → **Quick Actions** →
**"Convert with File Converter…"**.

**Why no Gatekeeper "unidentified developer" warning?** This build is
ad-hoc signed, not notarized with a paid Apple Developer ID — Gatekeeper
normally blocks that on files downloaded through a browser/AirDrop/etc.
`curl` in a terminal doesn't set the quarantine flag those channels do, so
a file fetched via the install script above just runs. If you instead
download the release zip by hand from a browser, macOS will quarantine it
and refuse to open it until you right-click → Open once (or run
`xattr -cr "/Applications/File Converter.app"`).

## Spec Check (find what's wrong before you deliver)

Before a video or image goes to an ad network, a store listing or a
partner, someone usually opens it and checks size, aspect ratio,
duration, frame rate, codec, audio and file size by hand — then guesses
which conversion settings will fix whatever is off. Spec Check does that
part:

1. **Drop files** (or right-click in Finder → Quick Actions →
   **"Check with File Converter"**).
2. **Pick a delivery spec** — a few generic examples ship with the app
   (vertical/landscape/square video ad, store screenshot, ≤ 25 MB
   attachment); duplicate one and adjust it to your partner's real spec.
3. **Read only the red rows.** Every rule shows *expected* vs *actual*
   (e.g. `Dimensions — expected 1080 × 1920, has 1920 × 1080`). Values
   that couldn't be read show as "to review", never as a silent pass.
4. **Fix.** The app shows what the fix will do ("Resize to 1080 × 1920,
   adding black bars", "Add a silent audio track", "Cap bitrate at
   1672 kbps to fit 30 MB"…), converts a `_fixed` copy (the original is
   never touched), and **re-checks the copy**. When a fix isn't possible
   by conversion (clip too short, a format File Converter can't produce),
   it says why instead of guessing.
5. **Export a report** (HTML for Slack/email, CSV for spreadsheets).

**AI spec import (optional).** In *Manage Specs… → + → Draft from Text with
AI*, paste the requirements you were sent (email, help-center page, PDF
excerpt). Claude (`claude-opus-5-5`, structured JSON output) drafts the
spec; it opens flagged for review so a person confirms every field before
it's used. Only the pasted text is sent — never your files. Needs a Claude
API key (Settings → AI spec import, stored in the Keychain). Everything
else in Spec Check runs fully offline.

Code: `Packages/FileConverterKit/Sources/FileConverterKit/SpecCheck/`
(`MediaProbe` → `SpecChecker` → `SpecFixPlanner`, plus
`ClaudeSpecImporter` and `SpecCheckReport`); UI in
`FileConverter/SpecCheckModel.swift` and `FileConverter/Views/Spec*.swift`.

## Project layout

- `project.yml` — [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec.
  The `.xcodeproj` is generated from this file, not hand-edited.
- `Packages/FileConverterKit/` — Swift Package with the conversion engine
  (job model, ffmpeg/ImageMagick/LibreOffice argument builders, preset
  model). Platform-agnostic Swift, testable standalone via `swift test`.
- `FileConverter/` — main SwiftUI app target. Unsandboxed (direct
  distribution, not Mac App Store) so it's free to shell out to ffmpeg/
  ImageMagick/soffice.
- `FileConverterQuickAction/` — Finder Quick Action (`NSExtension`,
  extension point `com.apple.services`). **Sandboxed** — see below.
- `install.sh` — the one-command installer referenced above.

## Building from source

```sh
brew install xcodegen
xcodegen generate
open FileConverterMac.xcodeproj
```

Re-run `xcodegen generate` after editing `project.yml`, `Info.plist`, or
entitlements — it regenerates `FileConverterMac.xcodeproj` from
source-of-truth files on disk without touching them
(`GENERATE_INFOPLIST_FILE: NO` + `INFOPLIST_FILE`/`CODE_SIGN_ENTITLEMENTS`
build settings point at the hand-authored plists in `FileConverter/` and
`FileConverterQuickAction/` — XcodeGen never rewrites their contents this
way, unlike its own managed `info:`/`entitlements:` keys).

To cut a release build:

```sh
xcodebuild -project FileConverterMac.xcodeproj -scheme FileConverter \
  -configuration Release -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" build
cd "$(xcodebuild -showBuildSettings -configuration Release \
  -scheme FileConverter 2>/dev/null | awk -F'= ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
zip -qry FileConverter.zip "File Converter.app"
```

Attach the resulting `FileConverter.zip` to a GitHub Release named after the
tag — `install.sh` always fetches `.../releases/latest/download/FileConverter.zip`.

## Sandbox spike (Phase 0 finding)

Confirmed by building and inspecting the signed binaries: **App Extensions
are sandboxed regardless of distribution channel.** This holds even for a
Developer-ID/non-MAS app — the extension point itself (hosted by Finder)
requires it.

```
$ codesign -d --entitlements - "File Converter Quick Action.appex"
com.apple.security.app-sandbox = true

$ codesign -d --entitlements - "File Converter.app"
com.apple.security.app-sandbox = false
```

**Architectural consequence** (already reflected in the code): the Quick
Action extension (`FileConverterQuickAction/ActionRequestHandler.swift`)
never runs ffmpeg/ImageMagick/soffice itself. It only collects the selected
file URLs, writes them to a temp list file, and opens
`fileconverter://convert?list=<path>` (optionally `&preset=<name>`) to hand
off to the unsandboxed main app — the same shape as the Windows shell
extension's argv/temp-file hand-off (`FileConverterExtension.cs`
`ConvertFiles`).

No manual "register the extension" step is needed either — once the app is
installed to `/Applications` and launched once, Launch Services
auto-discovers the bundled `.appex`:

```
$ pluginkit -m -v -i io.file-converter.mac.QuickAction
io.file-converter.mac.QuickAction(0.1.0)  ...  File Converter.app/Contents/PlugIns/...
```

## Status

- **Phase 0** (scaffolding + sandbox spike): done. Both targets build, sign
  (ad-hoc), embed correctly, and the extension is discoverable.
- **Phase 1** (conversion engine, `FileConverterKit`): done for v1 scope.
  Ported: `OutputType`/`InputCategory` compatibility matrix, per-format
  `Codable` settings, the exact ffmpeg quality/bitrate formulas and
  argument-building switch (all 11 ffmpeg-backed output types + the 2-pass
  GIF palette pipeline), an ImageMagick-CLI argument builder, an Ico
  composite job (ImageMagick clamp -> ffmpeg mux), an Office->PDF->image
  chain via LibreOffice headless, extension-then-output-type dispatch
  (`ConversionJobFactory`), collision/timestamp/cleanup handling
  (`ConversionOutputPlanner`), a `TaskGroup`-based concurrent scheduler
  (`ConversionQueue`), and JSON settings persistence. 40 tests pass
  (`swift test`), including real end-to-end ffmpeg conversions (mp3/mkv/gif)
  run through the full queue — not just argument-builder unit tests.
  Known v1 gaps, called out in code comments rather than silently papered
  over: output filename template only supports `(p)`/`(f)` tokens (not the
  multi-page `(n:i)`/`(n:c)` tokens); no raw-format (`.cr2`/`.dng`/...)
  `MagickFormat` override; no `.cda` extraction.
- **Phase 2** (SwiftUI app): done for v1 scope. `AppModel`/
  `ConversionSessionModel` wire settings persistence + `ConversionQueue` to
  a real UI: a preset manager (`PresetListView`/`PresetEditorView`, grouped
  by the `/`-folder convention, per-format-family settings editor), global
  `SettingsView` (concurrency limit, backend availability), and
  `ConversionProgressView`. Verified end-to-end for real: built the signed
  .app, launched the actual binary against a synthetic ffmpeg-generated
  test video, and confirmed a valid, correctly-timestamped output file came
  out the other end. One real concurrency bug was caught and fixed during
  this verification — see `ConversionSessionModel.start()`'s doc comment.
- **Phase 3** (real Quick Action): done for v1 scope, with one platform
  constraint surfaced and designed around rather than papered over — see
  `LaunchState` in `AppModel.swift`: a macOS Action Extension is one static
  menu entry (`NSExtensionServiceMenuItemTitle`), not a dynamically-built
  submenu of every compatible preset the way the Windows COM shell
  extension is. So `ActionRequestHandler` hands off just the file selection
  (no hardcoded preset), and the app auto-starts if exactly one preset is
  compatible, otherwise shows `PresetPickerView`. `NSExtensionActivationRule`
  was narrowed from "any file" to the real supported categories
  (audio/video, image, PDF, common Office document UTIs). Verified
  end-to-end via the actual `fileconverter://convert?...` hand-off shape.
- **Phase 5** (Spec Check): engine done and tested — 53 new package tests,
  including real ffmpeg round trips (a 640×360 60 fps silent clip fails a
  vertical-ad spec on 5 rules → planned fix → converted → re-check
  passes; crop + size-cap variant too). The package builds and all 93
  tests pass under Swift 6.0.3 on Linux with ffmpeg 6.1. The SwiftUI
  screens (`SpecCheckView`, `SpecLibraryView`, `SpecImportView`) were
  written without a Mac at hand and still need a first build + click-through
  in Xcode. The AI importer's request/response handling is unit-tested
  against recorded shapes, not yet against the live API.
- **Phase 4** (packaging/distribution): done for the "internal use, shared
  with a handful of Macs" scope this repo targets — ad-hoc signed Release
  build + `install.sh` one-liner (Homebrew + backends + app, quarantine-safe
  since it's a `curl` fetch). **Not done, and intentionally out of scope for
  now:** Developer ID signing + notarization for unrestricted public
  distribution — that needs a paid Apple Developer Program membership; if
  this ever needs to reach people outside a small trusted group, do that
  first.
