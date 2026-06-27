#!/usr/bin/env bash
set -euo pipefail

ICON_FILE=${1:-Icon.icon}
BASENAME=${2:-Icon}
OUT_ROOT=${3:-build/icon}
XCODE_APP=${XCODE_APP:-/Applications/Xcode.app}
PNG_SOURCE="${ICON_PNG_SOURCE:-${ICON_FILE}/Assets/repopeekicon.png}"

generate_iconset_from_png() {
  local source_png="$1"
  local iconset_dir="$2"
  mkdir -p "$iconset_dir"

  sips -z 16 16 "$source_png" --out "$iconset_dir/icon_16x16.png" >/dev/null
  sips -z 32 32 "$source_png" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$source_png" --out "$iconset_dir/icon_32x32.png" >/dev/null
  sips -z 64 64 "$source_png" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$source_png" --out "$iconset_dir/icon_128x128.png" >/dev/null
  sips -z 256 256 "$source_png" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$source_png" --out "$iconset_dir/icon_256x256.png" >/dev/null
  sips -z 512 512 "$source_png" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$source_png" --out "$iconset_dir/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$source_png" --out "$iconset_dir/icon_512x512@2x.png" >/dev/null
}

pack_icns_from_iconset() {
  local iconset_dir="$1"
  local icns_out="$2"

  if ! command -v node >/dev/null 2>&1; then
    echo "node is unavailable for ICNS generation." >&2
    exit 1
  fi

  ICNS_ICONSET_DIR="$iconset_dir" ICNS_OUT="$icns_out" node <<'NODE'
const fs = require("fs");
const dir = process.env.ICNS_ICONSET_DIR;
const outPath = process.env.ICNS_OUT;
const chunks = [
  ["icp4", "icon_16x16.png"],
  ["icp5", "icon_32x32.png"],
  ["icp6", "icon_32x32@2x.png"],
  ["ic07", "icon_128x128.png"],
  ["ic08", "icon_256x256.png"],
  ["ic09", "icon_512x512.png"],
  ["ic10", "icon_512x512@2x.png"],
].map(([type, name]) => {
  const data = fs.readFileSync(`${dir}/${name}`);
  const chunk = Buffer.alloc(8 + data.length);
  chunk.write(type, 0, "ascii");
  chunk.writeUInt32BE(chunk.length, 4);
  data.copy(chunk, 8);
  return chunk;
});
const total = 8 + chunks.reduce((sum, chunk) => sum + chunk.length, 0);
const output = Buffer.alloc(total);
output.write("icns", 0, "ascii");
output.writeUInt32BE(total, 4);
let offset = 8;
for (const chunk of chunks) {
  chunk.copy(output, offset);
  offset += chunk.length;
}
fs.writeFileSync(outPath, output);
NODE
}

if [[ -f "$PNG_SOURCE" ]]; then
  ICONSET_DIR="$OUT_ROOT/${BASENAME}.iconset"
  generate_iconset_from_png "$PNG_SOURCE" "$ICONSET_DIR"
  pack_icns_from_iconset "$ICONSET_DIR" "${BASENAME}.icns"
  echo "${BASENAME}.icns generated at $(pwd)/${BASENAME}.icns"
  exit 0
fi

ICTOOL="$XCODE_APP/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
if [[ ! -x "$ICTOOL" ]]; then
  ICTOOL="$XCODE_APP/Contents/Applications/Icon Composer.app/Contents/Executables/icontool"
fi
if [[ ! -x "$ICTOOL" ]]; then
  SVG_SOURCE="Resources/AppIcon.svg"
  if [[ ! -f "$SVG_SOURCE" ]]; then
    echo "ictool/icontool not found, and $SVG_SOURCE is missing. Set XCODE_APP if Xcode is elsewhere." >&2
    exit 1
  fi
  if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "ictool/icontool not found, and rsvg-convert is unavailable for SVG fallback." >&2
    exit 1
  fi
  ICONSET_DIR="$OUT_ROOT/${BASENAME}.iconset"
  mkdir -p "$ICONSET_DIR"
  rsvg-convert -w 16 -h 16 "$SVG_SOURCE" -o "$ICONSET_DIR/icon_16x16.png"
  rsvg-convert -w 32 -h 32 "$SVG_SOURCE" -o "$ICONSET_DIR/icon_32x32.png"
  rsvg-convert -w 64 -h 64 "$SVG_SOURCE" -o "$ICONSET_DIR/icon_32x32@2x.png"
  rsvg-convert -w 128 -h 128 "$SVG_SOURCE" -o "$ICONSET_DIR/icon_128x128.png"
  rsvg-convert -w 256 -h 256 "$SVG_SOURCE" -o "$ICONSET_DIR/icon_256x256.png"
  rsvg-convert -w 512 -h 512 "$SVG_SOURCE" -o "$ICONSET_DIR/icon_512x512.png"
  rsvg-convert -w 1024 -h 1024 "$SVG_SOURCE" -o "$ICONSET_DIR/icon_512x512@2x.png"

  pack_icns_from_iconset "$ICONSET_DIR" "${BASENAME}.icns"
  echo "${BASENAME}.icns generated at $(pwd)/${BASENAME}.icns"
  exit 0
fi

ICONSET_DIR="$OUT_ROOT/${BASENAME}.iconset"
TMP_DIR="$OUT_ROOT/tmp"
mkdir -p "$ICONSET_DIR" "$TMP_DIR"

MASTER_ART="$TMP_DIR/icon_art_824.png"
MASTER_1024="$TMP_DIR/icon_1024.png"

# Render inner art (no margin) with macOS Default appearance
"$ICTOOL" "$ICON_FILE" \
  --export-preview macOS Default 824 824 1 -45 "$MASTER_ART"

# Pad to 1024x1024 with transparent border
sips --padToHeightWidth 1024 1024 "$MASTER_ART" --out "$MASTER_1024" >/dev/null

# Generate required sizes
sizes=(16 32 64 128 256 512 1024)
for sz in "${sizes[@]}"; do
  out="$ICONSET_DIR/icon_${sz}x${sz}.png"
  sips -z "$sz" "$sz" "$MASTER_1024" --out "$out" >/dev/null
  if [[ "$sz" -ne 1024 ]]; then
    dbl=$((sz*2))
    out2="$ICONSET_DIR/icon_${sz}x${sz}@2x.png"
    sips -z "$dbl" "$dbl" "$MASTER_1024" --out "$out2" >/dev/null
  fi
done

# 512x512@2x already covered by 1024; ensure it exists
cp "$MASTER_1024" "$ICONSET_DIR/icon_512x512@2x.png"

pack_icns_from_iconset "$ICONSET_DIR" "${BASENAME}.icns"

echo "${BASENAME}.icns generated at $(pwd)/${BASENAME}.icns"
