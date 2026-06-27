#!/usr/bin/env bash
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "gh is required" >&2
  exit 1
fi

REPO=${REPOPEEK_GITHUB_REPOSITORY:-weirdo-adam/RepoPeek}
TAG=${1:-$(git describe --tags --abbrev=0)}
ARTIFACT_PREFIX=${2:-RepoPeek-}

assets=$(gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[].name')

zip_asset=$(printf "%s\n" "$assets" | grep -E "${ARTIFACT_PREFIX}"'[0-9.]+\.zip$' || true)
dsym_asset=$(printf "%s\n" "$assets" | grep -E "${ARTIFACT_PREFIX}"'[0-9.]+\.dSYM\.zip$' || true)

if [[ -z "$zip_asset" ]]; then
  echo "ERROR: app zip missing on release $TAG" >&2
  exit 1
fi

if [[ -z "$dsym_asset" ]]; then
  echo "ERROR: dSYM zip missing on release $TAG" >&2
  exit 1
fi

echo "Release $TAG has zip ($zip_asset) and dSYM ($dsym_asset)."
