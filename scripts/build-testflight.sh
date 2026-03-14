#!/bin/bash
set -euo pipefail

# TestFlight Build Script for Wuhu
# Usage: ./scripts/build-testflight.sh [--no-upload]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"

# ASC API credentials
ASC_KEY_ID="3U39ZA4G2A"
ASC_ISSUER_ID="d782de6f-d166-4df4-8124-a96926af646b"
ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"

# Version overrides (set by CI from git tag, optional for local builds)
VERSION_OVERRIDES=()
if [ -n "${MARKETING_VERSION:-}" ]; then
    VERSION_OVERRIDES+=("MARKETING_VERSION=$MARKETING_VERSION")
fi
if [ -n "${BUILD_NUMBER:-}" ]; then
    VERSION_OVERRIDES+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
fi

# Parse args
NO_UPLOAD=false
for arg in "$@"; do
    case $arg in
        --no-upload) NO_UPLOAD=true ;;
    esac
done

echo "🚀 Wuhu TestFlight Build"
echo "========================"

# Step 1: Generate Xcode project
echo "📦 Installing Tuist dependencies..."
cd "$PROJECT_ROOT"
tuist install
echo "📦 Generating Xcode project..."
tuist generate --cache-profile none

# Step 2: Clean build directory
echo "🧹 Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 3: Archive
echo "🔨 Archiving..."
cd "$PROJECT_ROOT"
xcodebuild archive \
    -workspace WuhuApp.xcworkspace \
    -scheme WuhuApp \
    -destination "generic/platform=iOS" \
    -archivePath "$BUILD_DIR/WuhuApp.xcarchive" \
    -quiet \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=97W7A3Y9GD \
    "${VERSION_OVERRIDES[@]}"

# Step 4: Export IPA
echo "📤 Exporting IPA..."
cat > "$BUILD_DIR/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>export</string>
    <key>teamID</key>
    <string>97W7A3Y9GD</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$BUILD_DIR/WuhuApp.xcarchive" \
    -exportPath "$BUILD_DIR/Export" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -quiet \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"

if [ "$NO_UPLOAD" = true ]; then
    echo "⏭️  Skipping upload (--no-upload)"
    echo "✅ IPA exported to: $BUILD_DIR/Export/"
    exit 0
fi

# Step 5: Upload to TestFlight
echo "☁️  Uploading to TestFlight..."
xcrun altool --upload-app \
    --type ios \
    --file "$BUILD_DIR/Export/WuhuApp.ipa" \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" \
    2>&1 | tee "$BUILD_DIR/upload.log"

echo ""
echo "✅ Build uploaded to TestFlight!"
echo "   Run './scripts/check-testflight.sh' to monitor processing status."
