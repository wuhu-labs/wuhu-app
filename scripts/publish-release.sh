#!/bin/bash
set -euo pipefail

# Publish a notarized macOS release to Cloudflare R2.
#
# Usage:
#   ./scripts/publish-release.sh <zip-path> [--local-only]
#
# The script reads local fallback versions from Project.swift so you don't have
# to pass them manually.
#
# Prerequisites:
#   - wrangler logged in (wrangler whoami), unless using --local-only
#   - Sparkle EdDSA private key at ~/.wuhu/keys/sparkle_eddsa_key.priv
#   - A notarized .zip (from build-notarized-mac.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_SWIFT="$PROJECT_ROOT/Project.swift"

# R2 config
export CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-476ba1878542c080b6bf4a771719d1fd}"
BUCKET="wuhu-site"
RELEASES_PREFIX="releases/macos"
APPCAST_KEY="releases/appcast.xml"

# Sparkle signing key
SPARKLE_PRIV_KEY="$HOME/.wuhu/keys/sparkle_eddsa_key.priv"
SIGN_UPDATE_SWIFT="$SCRIPT_DIR/sign-update.swift"
LOCAL_ONLY=false

# Parse args
if [ $# -lt 1 ]; then
  echo "Usage: $0 <zip-path> [--local-only]"
  echo ""
  echo "Example:"
  echo "  $0 ./build-mac/Wuhu.zip"
  echo "  $0 ./build-mac/Wuhu.zip --local-only"
  exit 1
fi

ZIP_PATH="$1"
shift

for arg in "$@"; do
  case "$arg" in
    --local-only) LOCAL_ONLY=true ;;
    *)
      echo "Error: unknown argument: $arg"
      exit 1
      ;;
  esac
done

if [ ! -f "$ZIP_PATH" ]; then
  echo "Error: zip not found at $ZIP_PATH"
  exit 1
fi

if [ ! -f "$SPARKLE_PRIV_KEY" ]; then
  echo "Error: Sparkle private key not found at $SPARKLE_PRIV_KEY"
  exit 1
fi

if [ ! -f "$SIGN_UPDATE_SWIFT" ]; then
  echo "Error: sign-update.swift not found at $SIGN_UPDATE_SWIFT"
  exit 1
fi

# Read version from env vars (set by CI) or fall back to Project.swift
if [ -z "${MARKETING_VERSION:-}" ] || [ -z "${BUILD_NUMBER:-}" ]; then
  MARKETING_VERSION=$(sed -n 's/^let marketingVersion = "\(.*\)"/\1/p' "$PROJECT_SWIFT" | head -1)
  BUILD_NUMBER=$(sed -n 's/^let currentProjectVersion = "\(.*\)"/\1/p' "$PROJECT_SWIFT" | head -1)
fi

if [ -z "$MARKETING_VERSION" ] || [ -z "$BUILD_NUMBER" ]; then
  echo "Error: Could not determine version. Set MARKETING_VERSION and BUILD_NUMBER env vars or check $PROJECT_SWIFT"
  exit 1
fi

DEST_NAME="Wuhu-${MARKETING_VERSION}-${BUILD_NUMBER}.zip"
FILE_SIZE=$(stat -f%z "$ZIP_PATH")
PUB_DATE=$(date -R)

echo "🚀 Publishing Wuhu macOS v${MARKETING_VERSION} (build ${BUILD_NUMBER})"
echo "   Zip: $ZIP_PATH ($FILE_SIZE bytes)"
echo "   Dest: $BUCKET/$RELEASES_PREFIX/$DEST_NAME"
echo ""

# Step 1: Sign the zip with EdDSA
echo "🔏 Signing with EdDSA..."
SIGNATURE=$(swift "$SIGN_UPDATE_SWIFT" "$ZIP_PATH" "$SPARKLE_PRIV_KEY")
echo "   Signature: ${SIGNATURE:0:20}..."

# Step 2: Generate appcast.xml
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

APPCAST_OUTPUT="$PROJECT_ROOT/build-mac/appcast.xml"
cp "$APPCAST_TMP" "$APPCAST_OUTPUT"

if [ "$LOCAL_ONLY" = false ]; then
  # Step 3: Upload the zip to R2
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

  # Step 4: Upload appcast.xml to R2
  echo "📤 Uploading appcast.xml..."
  wrangler r2 object put "$BUCKET/$APPCAST_KEY" \
      --file="$APPCAST_TMP" \
      --content-type="application/xml" \
      --remote 2>&1 | tail -1
else
  echo "⏭️  Skipping R2 upload (--local-only)"
fi

rm -f "$APPCAST_TMP"

echo ""
if [ "$LOCAL_ONLY" = false ]; then
  echo "✅ Published Wuhu macOS v${MARKETING_VERSION} (build ${BUILD_NUMBER})"
  echo "   Download: https://wuhu.ai/$RELEASES_PREFIX/$DEST_NAME"
  echo "   Latest:   https://wuhu.ai/$RELEASES_PREFIX/Wuhu-latest.zip"
  echo "   Appcast:  https://wuhu.ai/$APPCAST_KEY"
else
  echo "✅ Generated local Sparkle artifacts for v${MARKETING_VERSION} (build ${BUILD_NUMBER})"
  echo "   Zip:     $ZIP_PATH"
  echo "   Appcast: $APPCAST_OUTPUT"
fi
