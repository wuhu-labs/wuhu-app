#!/bin/bash
set -euo pipefail

# Download the Sparkle xcframework if it's not already present.
# Called by build scripts before xcodegen generate.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FRAMEWORKS_DIR="$PROJECT_ROOT/WuhuApp/Frameworks"
SPARKLE_DIR="$FRAMEWORKS_DIR/Sparkle.xcframework"

SPARKLE_VERSION="2.9.0"
SPARKLE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip"

if [ -d "$SPARKLE_DIR" ]; then
    echo "✅ Sparkle.xcframework already present"
    exit 0
fi

echo "📦 Downloading Sparkle ${SPARKLE_VERSION}..."
mkdir -p "$FRAMEWORKS_DIR"

TMP_DIR=$(mktemp -d)
curl -sL "$SPARKLE_URL" -o "$TMP_DIR/Sparkle-SPM.zip"
unzip -q "$TMP_DIR/Sparkle-SPM.zip" -d "$TMP_DIR/Sparkle-SPM"

# Copy the xcframework (preserving symlinks and attributes)
/usr/bin/ditto "$TMP_DIR/Sparkle-SPM/Sparkle.xcframework" "$SPARKLE_DIR"

# Remove the dSYMs to save space (not needed for builds)
rm -rf "$SPARKLE_DIR"/*/dSYMs

# Remove the DebugSymbolsPath from Info.plist since we stripped dSYMs
/usr/bin/plutil -remove 'AvailableLibraries.0.DebugSymbolsPath' "$SPARKLE_DIR/Info.plist" 2>/dev/null || true

# Also grab the sign_update tool for release signing
if [ ! -f "$SCRIPT_DIR/sign_update" ]; then
    cp "$TMP_DIR/Sparkle-SPM/bin/sign_update" "$SCRIPT_DIR/sign_update"
    chmod +x "$SCRIPT_DIR/sign_update"
    echo "   Copied sign_update to scripts/"
fi

rm -rf "$TMP_DIR"
echo "✅ Sparkle ${SPARKLE_VERSION} installed to WuhuApp/Frameworks/"
