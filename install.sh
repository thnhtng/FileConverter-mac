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
#   5. Installs a small Automator "Quick Action" service that shells out to
#      the app, and nudges Finder so "Convert with File Converter" shows up
#      in the right-click menu right away. (Not the app's own bundled
#      Action Extension — see the comment at step 5 for why: Finder only
#      loads compiled App Extensions from an Apple-issued signing identity,
#      which this unsigned/ad-hoc build doesn't have. An Automator Service
#      is plain interpreted script, no code-loading trust boundary, no
#      signing required — and needs zero setup on your end.)
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

# --- 5. Install the Finder Quick Action -------------------------------------
#
# The app also bundles a proper NSExtension-based Action Extension
# (Contents/PlugIns/File Converter Quick Action.appex). It's registered
# below too (harmless, and it'll start working on its own if this Mac ever
# gets a real Apple Developer ID signing identity) — but Finder silently
# refuses to load App Extensions that aren't signed with an Apple-issued
# identity, which an ad-hoc/self-signed build doesn't have. Free personal
# Apple ID signing doesn't clear that bar either; only Developer ID
# (paid Program) or the App Store does.
#
# So the thing that actually shows up in the right-click menu today is a
# small Automator "Quick Action" Service (~/Library/Services/) that just
# shells out to the app binary with the selected files as arguments.
# Automator Services run as plain interpreted actions hosted by Apple's own
# (already-trusted) Automator runner — there's no third-party compiled code
# being loaded into Finder's process, so none of the above signing
# requirement applies.
QUICK_ACTION_ID="io.file-converter.mac.QuickAction"
QUICK_ACTION_PATH="/Applications/$APP_NAME/Contents/PlugIns/File Converter Quick Action.appex"

pluginkit -D -m -v -i "$QUICK_ACTION_ID" 2>/dev/null | awk -F'\t' 'NF>1{print $NF}' | while IFS= read -r existing; do
    [[ "$existing" == "$QUICK_ACTION_PATH" ]] || pluginkit -r "$existing" 2>/dev/null || true
done
pluginkit -a "$QUICK_ACTION_PATH" 2>/dev/null || true
pluginkit -e use -i "$QUICK_ACTION_ID" 2>/dev/null || true

# Writes one Automator Service. $1 = menu title, $2 = bundle id,
# $3 = extra CLI args for the app (e.g. "--check "), placed before the files.
install_service() {
    local title="$1" bundle_id="$2" extra_args="$3"
    local workflow="$HOME/Library/Services/$title.workflow"
    rm -rf "$workflow"
    mkdir -p "$workflow/Contents"


cat > "$workflow/Contents/Info.plist" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>$title</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSSendFileTypes</key>
			<array>
				<string>public.item</string>
			</array>
			<key>NSRequiredContext</key>
			<dict>
				<key>NSApplicationIdentifier</key>
				<string>com.apple.finder</string>
			</dict>
		</dict>
	</array>
	<key>CFBundleIdentifier</key>
	<string>$bundle_id</string>
	<key>CFBundleName</key>
	<string>$title</string>
</dict>
</plist>
PLIST_EOF

cat > "$workflow/Contents/document.wflow" <<WFLOW_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>523</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Optional</key>
					<true/>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.path</string>
					</array>
				</dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>AMApplication</key>
				<array>
					<string>Automator</string>
				</array>
				<key>AMParameterProperties</key>
				<dict>
					<key>COMMAND_STRING</key>
					<dict/>
					<key>CheckedForUserDefaultShell</key>
					<dict/>
					<key>inputMethod</key>
					<dict/>
					<key>shell</key>
					<dict/>
					<key>source</key>
					<dict/>
				</dict>
				<key>AMProvides</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string>"/Applications/File Converter.app/Contents/MacOS/File Converter" $extra_args"\$@"</string>
					<key>CheckedForUserDefaultShell</key>
					<true/>
					<key>inputMethod</key>
					<integer>1</integer>
					<key>shell</key>
					<string>/bin/bash</string>
					<key>source</key>
					<string></string>
				</dict>
				<key>BundleIdentifier</key>
				<string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Category</key>
				<array>
					<string>AMCategoryUtilities</string>
				</array>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>InputUUID</key>
				<string>11111111-1111-1111-1111-111111111111</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
				<key>OutputUUID</key>
				<string>22222222-2222-2222-2222-222222222222</string>
				<key>UUID</key>
				<string>33333333-3333-3333-3333-333333333333</string>
				<key>UnlocalizedApplications</key>
				<array>
					<string>Automator</string>
				</array>
				<key>arguments</key>
				<dict>
					<key>0</key>
					<dict>
						<key>default value</key>
						<integer>0</integer>
						<key>name</key>
						<string>inputMethod</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>0</string>
					</dict>
					<key>1</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>source</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>1</string>
					</dict>
				</dict>
				<key>isViewVisible</key>
				<true/>
				<key>location</key>
				<string>309.000000:253.000000</string>
				<key>nibPath</key>
				<string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
			</dict>
			<key>isViewVisible</key>
			<true/>
		</dict>
	</array>
	<key>connectors</key>
	<dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>serviceInputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject</string>
		<key>serviceOutputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceProcessesInput</key>
		<integer>0</integer>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
WFLOW_EOF
}

log "Installing the Quick Actions…"
install_service "Convert with File Converter" "io.file-converter.mac.quickaction-workflow" ""
# Spec Check: opens the selected files in the Spec Check tab instead of
# converting them (LaunchRequest --check).
install_service "Check with File Converter" "io.file-converter.mac.check-workflow" "--check "

/System/Library/CoreServices/pbs -flush 2>/dev/null || true
killall Finder 2>/dev/null || true

log "Done. Right-click any supported file in Finder → Quick Actions → \"Convert with File Converter\" or \"Check with File Converter\""
