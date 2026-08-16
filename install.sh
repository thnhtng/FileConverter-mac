#!/usr/bin/env bash
# One-command installer for File Converter (macOS).
#
#   curl -fsSL https://raw.githubusercontent.com/thnhtng/FileConverter-mac/main/install.sh | bash
#
# What this does, in order:
#   1. Installs Homebrew if it isn't already present.
#   2. Installs the conversion backends: ffmpeg, ImageMagick (formulae) and
#      LibreOffice (cask, for Office-document presets) via brew.
#   3. Downloads the latest signed .app build from this repo's GitHub
#      Releases and installs it to /Applications.
#   4. Clears the quarantine flag (defensive — files fetched via curl
#      aren't quarantined by Gatekeeper the way browser downloads are, but
#      this is a no-op safety net in case some proxy/AV in between tags it).
#   5. Registers + explicitly approves the Quick Action with PlugInKit and
#      nudges Finder so "Convert with File Converter…" shows up in the
#      right-click menu right away.
#
# Safe to re-run any time to update to the latest release.

set -euo pipefail

# Guard against a stale/deleted working directory in the invoking shell
# (e.g. a cloud/CI terminal whose cwd was removed out from under it) — every
# subsequent command here (brew, curl, mktemp, ...) would otherwise fail at
# startup with "getcwd: cannot access parent directories". A fresh `cd` in
# THIS subshell recovers cleanly even when the parent shell is already
# broken, since it doesn't need to read the old cwd, only replace it.
cd "$HOME" 2>/dev/null || cd /tmp

REPO="thnhtng/FileConverter-mac"
APP_NAME="File Converter.app"
RELEASE_ASSET="FileConverter.zip"

log() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

if [[ "$(uname)" != "Darwin" ]]; then
    die "This installer is for macOS only."
fi

# --- 1. Homebrew -------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
    log "Homebrew not found — installing it (this can take a few minutes)…"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
else
    log "Homebrew already installed."
fi

# --- 2. Conversion backends ---------------------------------------------
log "Installing ffmpeg + ImageMagick…"
brew install ffmpeg imagemagick

if [[ -d "/Applications/LibreOffice.app" ]]; then
    log "LibreOffice already installed (Office-document presets enabled)."
else
    log "Installing LibreOffice (for Word/Excel/PowerPoint -> PDF presets — this is a large download)…"
    brew install --cask libreoffice || log "LibreOffice install failed/skipped — Office presets will be disabled until it's installed manually."
fi

# --- 3. Download + install the app --------------------------------------
log "Downloading the latest File Converter build…"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

curl -fsSL "https://github.com/${REPO}/releases/latest/download/${RELEASE_ASSET}" -o "$TMP_DIR/app.zip" \
    || die "Download failed. Check https://github.com/${REPO}/releases for the latest release."

log "Installing to /Applications…"
unzip -q -o "$TMP_DIR/app.zip" -d "$TMP_DIR"
[[ -d "$TMP_DIR/$APP_NAME" ]] || die "Unexpected archive contents — couldn't find '$APP_NAME'."

if [[ -d "/Applications/$APP_NAME" ]]; then
    rm -rf "/Applications/$APP_NAME"
fi
mv "$TMP_DIR/$APP_NAME" "/Applications/$APP_NAME"

# --- 4. Clear quarantine (defensive) -------------------------------------
xattr -cr "/Applications/$APP_NAME" 2>/dev/null || true

# --- 5. Register + approve the Quick Action --------------------------------
QUICK_ACTION_ID="io.file-converter.mac.QuickAction"
QUICK_ACTION_PATH="/Applications/$APP_NAME/Contents/PlugIns/File Converter Quick Action.appex"

# A plain launch is enough for Launch Services to discover the bundled
# .appex; quit it right back out since File Converter is meant to be
# launched per-conversion, not left open.
open -a "/Applications/$APP_NAME" 2>/dev/null || true
sleep 2
osascript -e 'tell application "File Converter" to quit' 2>/dev/null || true

# If a previous dev/debug build of the extension was ever registered from a
# different path, PlugInKit can end up with multiple physical copies under
# the same identifier, which confuses discovery. Force a clean single
# registration for the real /Applications copy.
pluginkit -D -m -v -i "$QUICK_ACTION_ID" 2>/dev/null | awk -F'\t' 'NF>1{print $NF}' | while IFS= read -r existing; do
    [[ "$existing" == "$QUICK_ACTION_PATH" ]] || pluginkit -r "$existing" 2>/dev/null || true
done
pluginkit -a "$QUICK_ACTION_PATH" 2>/dev/null || true

# Discovery alone isn't enough — PlugInKit tracks a separate per-extension
# "user election" state (visible as a +/-/? prefix in `pluginkit -m -v`)
# that gates whether it actually shows up in Finder's Quick Actions menu.
# Without this, colleagues installing via this script would need to find
# and flip "System Settings → General → Login Items & Extensions →
# Finder Extensions" themselves before the Quick Action appears.
pluginkit -e use -i "$QUICK_ACTION_ID" 2>/dev/null || true

killall Finder 2>/dev/null || true

log "Done. Right-click any supported file in Finder → Quick Actions → \"Convert with File Converter…\""
log "(If it still doesn't show up, check System Settings → General → Login Items & Extensions →"
log " Finder Extensions, and make sure \"File Converter\" is toggled on.)"
