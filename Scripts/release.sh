#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

source "$ROOT/version.env"

APPCAST="$ROOT/appcast.xml"
APP_NAME="${REPOPEEK_APP_NAME:-RepoPeek}"
ARTIFACT_NAME="${REPOPEEK_ARTIFACT_NAME:-RepoPeek}"
ARTIFACT_PREFIX="${ARTIFACT_NAME}-"
BUNDLE_ID="${REPOPEEK_BUNDLE_IDENTIFIER:-com.weirdoadam.repopeek}"
GITHUB_REPOSITORY="${REPOPEEK_GITHUB_REPOSITORY:-weirdo-adam/RepoPeek}"
TAG="v${MARKETING_VERSION}"

err() { echo "ERROR: $*" >&2; exit 1; }

require_clean_worktree() {
  git diff --quiet || err "worktree has unstaged changes"
  git diff --cached --quiet || err "worktree has staged changes"
  [[ -z "$(git status --porcelain)" ]] || err "worktree has untracked files"
}

ensure_changelog_finalized() {
  local version=$1
  grep -Eq "^## ${version}$" "$ROOT/CHANGELOG.md" || \
    err "CHANGELOG.md top section must include '## ${version}'"
}

ensure_appcast_monotonic() {
  local appcast=$1
  local version=$2
  local build=$3
  python3 - "$appcast" "$version" "$build" <<'PY'
import sys
import xml.etree.ElementTree as ET

appcast, version, build = sys.argv[1:4]
tree = ET.parse(appcast)
root = tree.getroot()
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}

for item in root.findall("./channel/item"):
    short_version = item.findtext("sparkle:shortVersionString", default="", namespaces=ns)
    if short_version == version:
        sys.exit(f"appcast already has an entry for {version}")
    build_text = item.findtext("sparkle:version", default="", namespaces=ns)
    if build_text.isdigit() and build.isdigit() and int(build_text) >= int(build):
        sys.exit(f"appcast build {build_text} is not older than {build}")
PY
}

clean_sparkle_key() {
  local source_file=$1
  local tmp key_lines line_count
  [[ -f "$source_file" ]] || err "Sparkle key file not found: $source_file"
  key_lines=$(grep -v '^[[:space:]]*#' "$source_file" | sed '/^[[:space:]]*$/d')
  line_count=$(printf "%s\n" "$key_lines" | wc -l | tr -d ' ')
  [[ "$line_count" == "1" ]] || err "Sparkle key file must contain exactly one base64 line"
  tmp=$(mktemp /tmp/repopeek-sparkle-key.XXXX)
  printf "%s" "$key_lines" >"$tmp"
  echo "$tmp"
}

clear_sparkle_caches() {
  local bundle_id=$1
  rm -rf "${HOME}/Library/Caches/${bundle_id}" \
    "${HOME}/Library/Caches/${bundle_id}.Sparkle" \
    "${HOME}/Library/Application Support/${bundle_id}/Sparkle" 2>/dev/null || true
}

require_clean_worktree
ensure_changelog_finalized "$MARKETING_VERSION"
ensure_appcast_monotonic "$APPCAST" "$MARKETING_VERSION" "$BUILD_NUMBER"

pnpm check
pnpm build

# Note: run this script in the foreground; do not background it so it waits to completion.
"$ROOT/Scripts/sign-and-notarize.sh"

[[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]] || err "SPARKLE_PRIVATE_KEY_FILE is required"
KEY_FILE=$(clean_sparkle_key "$SPARKLE_PRIVATE_KEY_FILE")
clear_sparkle_caches "$BUNDLE_ID"

NOTES_MD=$(mktemp /tmp/repopeek-notes.XXXX.md)
"$ROOT/Scripts/generate-release-notes.sh" "$MARKETING_VERSION" "$NOTES_MD"
trap 'rm -f "$KEY_FILE" "$NOTES_MD"' EXIT

git tag -f "$TAG" -m "${APP_NAME} ${MARKETING_VERSION}"
git push -f origin "$TAG"

gh release create "$TAG" "${ARTIFACT_NAME}-${MARKETING_VERSION}.zip" "${ARTIFACT_NAME}-${MARKETING_VERSION}.dSYM.zip" \
  --repo "$GITHUB_REPOSITORY" \
  --title "${APP_NAME} ${MARKETING_VERSION}" \
  --notes-file "$NOTES_MD"

SPARKLE_PRIVATE_KEY_FILE="$KEY_FILE" \
  "$ROOT/Scripts/make_appcast.sh" \
  "${ARTIFACT_NAME}-${MARKETING_VERSION}.zip" \
  "${REPOPEEK_SPARKLE_FEED_URL:-https://raw.githubusercontent.com/weirdo-adam/RepoPeek/main/appcast.xml}"

SPARKLE_PRIVATE_KEY_FILE="$KEY_FILE" "$ROOT/Scripts/verify_appcast.sh" "$MARKETING_VERSION"

git add "$APPCAST"
git commit -m "docs: update appcast for ${MARKETING_VERSION}"
git push origin main

if [[ "${RUN_SPARKLE_UPDATE_TEST:-0}" == "1" ]]; then
  PREV_TAG=$(git tag --sort=-v:refname | sed -n '2p')
  [[ -z "$PREV_TAG" ]] && err "RUN_SPARKLE_UPDATE_TEST=1 set but no previous tag found"
  "$ROOT/Scripts/test_live_update.sh" "$PREV_TAG" "v${MARKETING_VERSION}"
fi

"$ROOT/Scripts/check-release-assets.sh" "$TAG" "$ARTIFACT_PREFIX"

git push origin --tags

echo "Release ${MARKETING_VERSION} complete."
