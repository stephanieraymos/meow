#!/usr/bin/env bash
# Meowdoku — local TestFlight upload (iOS). Run: make ship
#
# Signing model (matches Glade/Horizon): this account's cloud-managed signing is
# disabled, so we use MANUAL signing with a distribution profile installed at
# ~/Library/MobileDevice/Provisioning Profiles ("Meowdoku App Store CLI"). The
# archive step authenticates with the account-wide App Store Connect API key to
# register the App ID / capabilities; export signs locally with the installed
# profile + Apple Distribution cert; altool uploads with the same key.
#
# Prerequisites (one-time):
#   1. App record for com.stephanieraymos.meowdoku exists in App Store Connect.
#   2. "Meowdoku App Store CLI" distribution profile installed (scripts/mint-profile.py).
#   3. "Apple Distribution: Stephanie Raymos" cert in the login Keychain.

set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="Meowdoku"
PROJECT="Meowdoku.xcodeproj"
TEAM="FZ5HL2XU6U"
ARCHIVE_PATH="build/Meowdoku.xcarchive"
EXPORT_PATH="build/export"
PROFILE_NAME="Meowdoku App Store CLI"
ASC_KEY_ID="RJ7CKLZFFX"
ASC_ISSUER_ID="4e55d966-9145-4f15-bfc6-c698befe9a66"
ASC_KEY="$HOME/.private_keys/AuthKey_${ASC_KEY_ID}.p8"

[ -f "$ASC_KEY" ] || { echo "❌ Missing ASC API key: $ASC_KEY"; exit 1; }

# Ensure the distribution profile is installed; mint it if missing.
if ! grep -qrl "$PROFILE_NAME" "$HOME/Library/MobileDevice/Provisioning Profiles/" 2>/dev/null; then
  echo "▶  Distribution profile not found — minting it..."
  python3 scripts/mint-profile.py
fi

echo "▶  Regenerating Xcode project..."
xcodegen generate >/dev/null

BUILD_NUMBER=$(date +%s)
echo "▶  Archiving (build $BUILD_NUMBER)..."
rm -rf build
xcodebuild archive \
  -scheme "$SCHEME" -project "$PROJECT" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  DEVELOPMENT_TEAM="$TEAM" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -quiet

echo "▶  Exporting IPA (manual signing)..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist ExportOptions.plist \
  -quiet

IPA=$(find "$EXPORT_PATH" -name '*.ipa' | head -1)
[ -n "$IPA" ] || { echo "❌ No IPA produced"; exit 1; }
echo "▶  IPA ready: $IPA"

echo "▶  Uploading to TestFlight..."
xcrun altool --upload-app --type ios \
  --file "$IPA" \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID" \
  --verbose

echo ""
echo "✅ Build $BUILD_NUMBER uploaded. Appears in TestFlight in ~5–10 min."
