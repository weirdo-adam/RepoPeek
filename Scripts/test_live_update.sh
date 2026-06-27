#!/usr/bin/env bash
set -euo pipefail

PREV_TAG=${1:?'pass previous release tag (e.g. v0.1.0)'}
CUR_TAG=${2:?'pass current release tag (e.g. v0.1.1)'}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PREV_VER=${PREV_TAG#v}
APP_NAME="${REPOPEEK_APP_NAME:-RepoPeek}"
ARTIFACT_NAME="${REPOPEEK_ARTIFACT_NAME:-RepoPeek}"

ZIP_URL="${REPOPEEK_RELEASE_BASE_URL:-https://github.com/weirdo-adam/RepoPeek/releases/download}/${PREV_TAG}/${ARTIFACT_NAME}-${PREV_VER}.zip"
TMP_DIR=$(mktemp -d /tmp/repopeek-live.XXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading previous release $PREV_TAG from $ZIP_URL"
curl -L -o "$TMP_DIR/prev.zip" "$ZIP_URL"

echo "Installing previous release to /Applications/${APP_NAME}.app"
rm -rf "/Applications/${APP_NAME}.app"
ditto -x -k "$TMP_DIR/prev.zip" "$TMP_DIR"
SOURCE_APP="$TMP_DIR/${APP_NAME}.app"
if [ ! -d "$SOURCE_APP" ] && [ -d "$TMP_DIR/RepoPeek.app" ]; then
  SOURCE_APP="$TMP_DIR/RepoPeek.app"
fi
ditto "$SOURCE_APP" "/Applications/${APP_NAME}.app"

echo "Launching previous build…"
open -n "/Applications/${APP_NAME}.app"
sleep 4

cat <<'MSG'
Manual step: trigger "Check for Updates…" in the app and install the update.
Expect to land on the newly released version. When done, confirm below.
MSG

read -rp "Did the update succeed from ${PREV_TAG} to ${CUR_TAG}? (y/N) " answer
if [[ ! "$answer" =~ ^[Yy]$ ]]; then
  echo "Live update test NOT confirmed; failing per RUN_SPARKLE_UPDATE_TEST." >&2
  exit 1
fi

echo "Live update test confirmed."
