#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CACHE_PATH="${HOME}/Library/Caches/RepoPeek/swiftpm"
mkdir -p "${CACHE_PATH}"

./Scripts/swiftpm_sanitize.sh

# When using CommandLineTools (no Xcode), the Swift Testing framework may
# not be in the default compiler search path. Derive the frameworks directory
# from the active toolchain so `import Testing` resolves correctly.
TOOLS_DIR="$(xcode-select -p)"
FRAMEWORKS_DIR="${TOOLS_DIR}/Library/Developer/Frameworks"

echo "==> swift test"
if [ -d "${FRAMEWORKS_DIR}/Testing.framework" ]; then
    swift test -q --enable-swift-testing --cache-path "${CACHE_PATH}" -Xswiftc "-F${FRAMEWORKS_DIR}" "$@"
else
    swift test -q --enable-swift-testing --cache-path "${CACHE_PATH}" "$@"
fi
