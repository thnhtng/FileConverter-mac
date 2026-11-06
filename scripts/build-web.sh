#!/usr/bin/env bash
# Builds the static web converter into dist/web (deployable as-is, e.g. to
# GitHub Pages) and vendors ffmpeg.wasm from npm. The extension build
# (scripts/build-extension.sh) reuses the same output.
#
#   scripts/build-web.sh            # -> dist/web
#   python3 -m http.server -d dist/web 8080   # ES modules need http://, not file://
set -euo pipefail
cd "$(dirname "$0")/.."

FFMPEG_VERSION="0.12.15"   # @ffmpeg/ffmpeg (JS wrapper + worker)
CORE_VERSION="0.12.10"     # @ffmpeg/core (single-threaded wasm, no COOP/COEP needed)

OUT="dist/web"
CACHE=".cache/npm"
mkdir -p "$CACHE"

fetch_pkg() { # name version -> unpacked dir
  local name="$1" version="$2" dir="$CACHE/$(echo "$1" | tr '/@' '__')-$2"
  if [[ ! -d "$dir/package" ]]; then
    mkdir -p "$dir"
    local tgz
    tgz="$(cd "$dir" && npm pack --silent "$name@$version")"
    tar -xzf "$dir/$tgz" -C "$dir"
  fi
  echo "$dir/package"
}

FF="$(fetch_pkg @ffmpeg/ffmpeg "$FFMPEG_VERSION")"
CORE="$(fetch_pkg @ffmpeg/core "$CORE_VERSION")"

rm -rf "$OUT"
mkdir -p "$OUT/vendor/ffmpeg" "$OUT/vendor/core"
cp web/*.html web/*.js web/*.css "$OUT"/ 2>/dev/null || true
cp shared/formats.json "$OUT/formats.json"
cp "$FF"/dist/esm/*.js "$OUT/vendor/ffmpeg/"
cp "$CORE"/dist/esm/ffmpeg-core.js "$CORE"/dist/esm/ffmpeg-core.wasm "$OUT/vendor/core/"
cp "$FF/LICENSE" "$OUT/vendor/ffmpeg/LICENSE" 2>/dev/null || true
cp "$CORE/LICENSE" "$OUT/vendor/core/LICENSE" 2>/dev/null || true

echo "Built $OUT ($(du -sh "$OUT" | cut -f1))"
