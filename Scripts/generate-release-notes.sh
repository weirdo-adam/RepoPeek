#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

source "$ROOT/version.env"

VERSION=${1:-$MARKETING_VERSION}
OUT=${2:-}

python3 - "$VERSION" "$ROOT/CHANGELOG.md" "$OUT" <<'PY'
import pathlib
import re
import sys

version, changelog_path, out_path = sys.argv[1:4]
text = pathlib.Path(changelog_path).read_text()
pattern = re.compile(rf"^##\s+\[?{re.escape(version)}\]?.*$", re.M)
match = pattern.search(text)
if not match:
    sys.exit(f"changelog section not found for {version}")

start = text.find("\n", match.end())
if start == -1:
    sys.exit(f"changelog section for {version} is empty")
start += 1
next_match = re.search(r"^##\s+", text[start:], re.M)
end = start + next_match.start() if next_match else len(text)
notes = text[start:end].strip() + "\n"
if notes.strip() == "":
    sys.exit(f"changelog section for {version} is empty")

if out_path:
    pathlib.Path(out_path).write_text(notes)
else:
    sys.stdout.write(notes)
PY
