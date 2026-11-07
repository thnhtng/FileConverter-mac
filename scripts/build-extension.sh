#!/usr/bin/env bash
# Builds the browser extension into dist/extension (load it unpacked from
# chrome://extensions) and dist/FileConverter-extension.zip.
# The extension bundles the web converter (dist/web) as web/, so the
# conversion engine, formats table and ffmpeg.wasm are identical.
#
# Safari (on a Mac with Xcode):
#   xcrun safari-web-extension-converter dist/extension --app-name "File Converter"
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f dist/web/vendor/core/ffmpeg-core.wasm ]] || scripts/build-web.sh

OUT="dist/extension"
rm -rf "$OUT"
mkdir -p "$OUT"
cp -R extension/. "$OUT/"
cp -R dist/web "$OUT/web"

VERSION="$(python3 -c 'import json;print(json.load(open("extension/manifest.json"))["version"])')"
( cd "$OUT" && zip -qr ../FileConverter-extension.zip . )
echo "Built $OUT (v$VERSION, $(du -sh "$OUT" | cut -f1)) and dist/FileConverter-extension.zip ($(du -sh dist/FileConverter-extension.zip | cut -f1))"
