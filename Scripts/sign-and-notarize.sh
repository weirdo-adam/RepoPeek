#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${REPOPEEK_APP_NAME:-RepoPeek}"
ARTIFACT_NAME="${REPOPEEK_ARTIFACT_NAME:-RepoPeek}"
APP_EXECUTABLE_NAME="${REPOPEEK_EXECUTABLE_NAME:-RepoPeek}"
APP_IDENTITY="${REPOPEEK_APP_IDENTITY:-${CODESIGN_IDENTITY:-${CODE_SIGN_IDENTITY:-}}}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"
ZIP_NAME="${ARTIFACT_NAME}-${MARKETING_VERSION}.zip"
DSYM_ZIP="${ARTIFACT_NAME}-${MARKETING_VERSION}.dSYM.zip"

if [[ -z "${APP_STORE_CONNECT_API_KEY_P8:-}" || -z "${APP_STORE_CONNECT_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  echo "Missing APP_STORE_CONNECT_* env vars (API key, key id, issuer id)." >&2
  exit 1
fi
if [[ -z "$APP_IDENTITY" ]]; then
  echo "Set REPOPEEK_APP_IDENTITY, CODESIGN_IDENTITY, or CODE_SIGN_IDENTITY to a Developer ID Application identity." >&2
  exit 1
fi
if [[ -z "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  echo "SPARKLE_PRIVATE_KEY_FILE is required for release signing/verification." >&2
  exit 1
fi
if [[ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
  echo "Sparkle key file not found: $SPARKLE_PRIVATE_KEY_FILE" >&2
  exit 1
fi
key_lines=$(grep -v '^[[:space:]]*#' "$SPARKLE_PRIVATE_KEY_FILE" | sed '/^[[:space:]]*$/d')
if [[ $(printf "%s\n" "$key_lines" | wc -l) -ne 1 ]]; then
  echo "Sparkle key file must contain exactly one base64 line (no comments/blank lines)." >&2
  exit 1
fi

NOTARIZE_ZIP="/tmp/${ARTIFACT_NAME}Notarize.zip"
echo "$APP_STORE_CONNECT_API_KEY_P8" | sed 's/\\n/\n/g' > /tmp/repopeek-api-key.p8
trap 'rm -f /tmp/repopeek-api-key.p8 "$NOTARIZE_ZIP"' EXIT

swift build -c release --arch arm64 --arch x86_64
SKIP_BUILD=1 ./Scripts/package_app.sh release

# SwiftPM output locations vary (Xcode toolchain + SwiftPM version).
# Resolve the produced app bundle explicitly instead of assuming `./RepoPeek.app`.
APP_BUNDLE=""
for candidate in \
  ".build/apple/Products/Release/${APP_NAME}.app" \
  ".build/release/${APP_NAME}.app" \
  ".build/arm64-apple-macosx/release/${APP_NAME}.app" \
  ".build/x86_64-apple-macosx/release/${APP_NAME}.app"; do
  if [[ -d "$candidate" ]]; then
    APP_BUNDLE="$candidate"
    break
  fi
done
if [[ -z "$APP_BUNDLE" ]]; then
  echo "ERROR: app bundle not found (looked in common SwiftPM release locations)" >&2
  exit 1
fi

echo "Signing with $APP_IDENTITY"
export REPOPEEK_SKIP_KEYCHAIN_GROUPS="${REPOPEEK_SKIP_KEYCHAIN_GROUPS:-1}"
./Scripts/codesign_app.sh "$APP_BUNDLE" "$APP_IDENTITY"

DITTO_BIN=${DITTO_BIN:-/usr/bin/ditto}
"$DITTO_BIN" -c -k --keepParent --sequesterRsrc "$APP_BUNDLE" "$NOTARIZE_ZIP"

echo "Submitting for notarization"
xcrun notarytool submit "$NOTARIZE_ZIP" \
  --key /tmp/repopeek-api-key.p8 \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait

echo "Stapling ticket"
xcrun stapler staple "$APP_BUNDLE"

"$DITTO_BIN" -c -k --keepParent --sequesterRsrc "$APP_BUNDLE" "$ZIP_NAME"

spctl -a -t exec -vv "$APP_BUNDLE"
stapler validate "$APP_BUNDLE"

echo "Packaging dSYM"
DSYM_PATH=".build/apple/Products/Release/${APP_EXECUTABLE_NAME}.dSYM"
if [[ ! -d "$DSYM_PATH" ]]; then
  DSYM_PATH=".build/release/${APP_EXECUTABLE_NAME}.dSYM"
fi
if [[ ! -d "$DSYM_PATH" ]]; then
  DSYM_PATH=".build/arm64-apple-macosx/release/${APP_EXECUTABLE_NAME}.dSYM"
fi
if [[ ! -d "$DSYM_PATH" ]]; then
  DSYM_PATH=".build/x86_64-apple-macosx/release/${APP_EXECUTABLE_NAME}.dSYM"
fi
if [[ ! -d "$DSYM_PATH" ]]; then
  echo "Missing dSYM at $DSYM_PATH" >&2
  exit 1
fi
"$DITTO_BIN" -c -k --keepParent "$DSYM_PATH" "$DSYM_ZIP"

echo "Done: $ZIP_NAME"
