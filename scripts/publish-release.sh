#!/bin/bash
set -euo pipefail

# Publish a notarized macOS release to Cloudflare R2.
#
# Usage:
#   ./scripts/publish-release.sh <zip-path>
#
# The script reads MARKETING_VERSION and CURRENT_PROJECT_VERSION from
# project.yml so you don't have to pass them manually.
#
# Prerequisites:
#   - wrangler logged in (wrangler whoami)
#   - Sparkle EdDSA private key at ~/.wuhu/keys/sparkle_eddsa_key.priv
#   - A notarized .zip (from build-notarized-mac.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_YML="$PROJECT_ROOT/WuhuApp/project.yml"

# R2 config
export CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-476ba1878542c080b6bf4a771719d1fd}"
BUCKET="wuhu-site"
RELEASES_PREFIX="releases/macos"
APPCAST_KEY="releases/appcast.xml"

# Sparkle signing key
SPARKLE_PRIV_KEY="$HOME/.wuhu/keys/sparkle_eddsa_key.priv"
SIGN_UPDATE="$SCRIPT_DIR/sign_update"

# Parse args
if [ $# -lt 1 ]; then
  echo "Usage: $0 <zip-path>"
  echo ""
  echo "Example:"
  echo "  $0 ./build-mac/Wuhu.zip"
  exit 1
fi

ZIP_PATH="$1"

if [ ! -f "$ZIP_PATH" ]; then
  echo "Error: zip not found at $ZIP_PATH"
  exit 1
fi

if [ ! -f "$SPARKLE_PRIV_KEY" ]; then
  echo "Error: Sparkle private key not found at $SPARKLE_PRIV_KEY"
  exit 1
fi

if [ ! -x "$SIGN_UPDATE" ]; then
  echo "Error: sign_update not found at $SIGN_UPDATE"
  exit 1
fi

# Read version from project.yml
MARKETING_VERSION=$(grep 'MARKETING_VERSION:' "$PROJECT_YML" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
BUILD_NUMBER=$(grep 'CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | head -1 | sed 's/.*: *"\(.*\)"/\1/')

if [ -z "$MARKETING_VERSION" ] || [ -z "$BUILD_NUMBER" ]; then
  echo "Error: Could not parse version from $PROJECT_YML"
  exit 1
fi

DEST_NAME="Wuhu-${MARKETING_VERSION}-${BUILD_NUMBER}.zip"
FILE_SIZE=$(stat -f%z "$ZIP_PATH")
PUB_DATE=$(date -R)

echo "🚀 Publishing Wuhu macOS v${MARKETING_VERSION} (build ${BUILD_NUMBER})"
echo "   Zip: $ZIP_PATH ($FILE_SIZE bytes)"
echo "   Dest: $BUCKET/$RELEASES_PREFIX/$DEST_NAME"
echo ""

# Step 1: Sign the zip with EdDSA using Sparkle's official sign_update
echo "🔏 Signing with EdDSA..."
SIGNATURE=$("$SIGN_UPDATE" "$ZIP_PATH" --ed-key-file "$SPARKLE_PRIV_KEY" -p)
echo "   Signature: ${SIGNATURE:0:20}..."

# Step 2: Upload the zip to R2
echo "📤 Uploading zip to R2..."
wrangler r2 object put "$BUCKET/$RELEASES_PREFIX/$DEST_NAME" \
    --file="$ZIP_PATH" \
    --content-type="application/zip" \
    --remote 2>&1 | tail -1

# Also upload as "latest" for the download page
wrangler r2 object put "$BUCKET/$RELEASES_PREFIX/Wuhu-latest.zip" \
    --file="$ZIP_PATH" \
    --content-type="application/zip" \
    --remote 2>&1 | tail -1

# Step 3: Generate appcast.xml
echo "📝 Generating appcast.xml..."
APPCAST_TMP=$(mktemp)
cat > "$APPCAST_TMP" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Wuhu Updates</title>
    <link>https://wuhu.ai/releases/appcast.xml</link>
    <description>Most recent updates for Wuhu</description>
    <language>en</language>
    <item>
      <title>Version ${MARKETING_VERSION}</title>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${MARKETING_VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure
        url="https://wuhu.ai/${RELEASES_PREFIX}/${DEST_NAME}"
        length="${FILE_SIZE}"
        type="application/octet-stream"
        sparkle:edSignature="${SIGNATURE}" />
    </item>
  </channel>
</rss>
EOF

# Step 4: Upload appcast.xml to R2
echo "📤 Uploading appcast.xml..."
wrangler r2 object put "$BUCKET/$APPCAST_KEY" \
    --file="$APPCAST_TMP" \
    --content-type="application/xml" \
    --remote 2>&1 | tail -1

rm -f "$APPCAST_TMP"

echo ""
echo "✅ Published Wuhu macOS v${MARKETING_VERSION} (build ${BUILD_NUMBER})"
echo "   Download: https://wuhu.ai/$RELEASES_PREFIX/$DEST_NAME"
echo "   Latest:   https://wuhu.ai/$RELEASES_PREFIX/Wuhu-latest.zip"
echo "   Appcast:  https://wuhu.ai/$APPCAST_KEY"
