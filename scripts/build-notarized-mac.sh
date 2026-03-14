#!/bin/bash
set -euo pipefail

# Notarized macOS Build Script for Wuhu
# Usage: ./scripts/build-notarized-mac.sh [--skip-gen] [--no-upload]
#
# Produces a notarized, stapled .app inside a zip. By default copies
# the result to iCloud Desktop.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build-mac"

# Signing & notarization
TEAM_ID="97W7A3Y9GD"
SIGNING_IDENTITY="Developer ID Application: Hangzhou Hu Di Shen Shan Technology Co., Ltd (97W7A3Y9GD)"
ASC_KEY_ID="3U39ZA4G2A"
ASC_ISSUER_ID="d782de6f-d166-4df4-8124-a96926af646b"
ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"

# The macOS target product name is "Wuhu", so the .app is Wuhu.app
APP_NAME="Wuhu"

# Output
ICLOUD_DESKTOP="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Desktop"
OUTPUT_NAME="${APP_NAME}.zip"

# Version overrides (set by CI from git tag, optional for local builds)
VERSION_OVERRIDES=()
if [ -n "${MARKETING_VERSION:-}" ]; then
    VERSION_OVERRIDES+=("MARKETING_VERSION=$MARKETING_VERSION")
fi
if [ -n "${BUILD_NUMBER:-}" ]; then
    VERSION_OVERRIDES+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
fi

# Parse args
SKIP_GEN=false
NO_UPLOAD=false
for arg in "$@"; do
    case $arg in
        --skip-gen) SKIP_GEN=true ;;
        --no-upload) NO_UPLOAD=true ;;
    esac
done

echo "🚀 Wuhu macOS Notarized Build"
echo "=============================="

# Step 1: Generate Xcode project
if [ "$SKIP_GEN" = false ]; then
    echo "📦 Installing Tuist dependencies..."
    cd "$PROJECT_ROOT"
    tuist install
    echo "📦 Generating Xcode project..."
    tuist generate --cache-profile none
else
    echo "⏭️  Skipping tuist install/generate (--skip-gen)"
fi

# Step 2: Clean build directory
echo "🧹 Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 3: Archive
echo "🔨 Archiving..."
cd "$PROJECT_ROOT"
xcodebuild archive \
    -workspace WuhuApp.xcworkspace \
    -scheme WuhuAppMac \
    -destination "generic/platform=macOS" \
    -archivePath "$BUILD_DIR/${APP_NAME}.xcarchive" \
    -quiet \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    "${VERSION_OVERRIDES[@]}"

# Step 4: Export
echo "📤 Exporting app..."
cat > "$BUILD_DIR/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$BUILD_DIR/${APP_NAME}.xcarchive" \
    -exportPath "$BUILD_DIR/Export" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -quiet \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"

# Step 5: Create zip for notarization
echo "📦 Creating zip for notarization..."
cd "$BUILD_DIR/Export"
/usr/bin/ditto -c -k --keepParent --norsrc "${APP_NAME}.app" "$BUILD_DIR/${APP_NAME}-unsigned.zip"

# Step 6: Notarize
echo "🔏 Submitting for notarization..."
xcrun notarytool submit "$BUILD_DIR/${APP_NAME}-unsigned.zip" \
    --key "$ASC_KEY_PATH" \
    --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" \
    --wait

# Step 7: Staple
echo "📎 Stapling notarization ticket..."
xcrun stapler staple "$BUILD_DIR/Export/${APP_NAME}.app"

# Step 8: Verify
echo "✅ Verifying notarization..."
spctl --assess --type exec -vv "$BUILD_DIR/Export/${APP_NAME}.app" 2>&1

# Step 9: Create final zip with stapled ticket
echo "📦 Creating final zip..."
cd "$BUILD_DIR/Export"
/usr/bin/ditto -c -k --keepParent --norsrc "${APP_NAME}.app" "$BUILD_DIR/$OUTPUT_NAME"

if [ "$NO_UPLOAD" = true ]; then
    echo "⏭️  Skipping iCloud copy (--no-upload)"
    echo "✅ Notarized build at: $BUILD_DIR/$OUTPUT_NAME"
    exit 0
fi

# Step 10: Copy to iCloud Desktop
echo "☁️  Copying to iCloud Desktop..."
cp "$BUILD_DIR/$OUTPUT_NAME" "$ICLOUD_DESKTOP/$OUTPUT_NAME"

echo ""
echo "✅ Notarized build deployed!"
echo "   Local: $BUILD_DIR/$OUTPUT_NAME"
echo "   iCloud: $ICLOUD_DESKTOP/$OUTPUT_NAME"
