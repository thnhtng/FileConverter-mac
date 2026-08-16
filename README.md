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
- **Phase 4** (packaging/distribution): done for the "internal use, shared
  with a handful of Macs" scope this repo targets — ad-hoc signed Release
  build + `install.sh` one-liner (Homebrew + backends + app, quarantine-safe
  since it's a `curl` fetch). **Not done, and intentionally out of scope for
  now:** Developer ID signing + notarization for unrestricted public
  distribution — that needs a paid Apple Developer Program membership; if
  this ever needs to reach people outside a small trusted group, do that
  first.
