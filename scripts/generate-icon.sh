#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_IMAGE="$ROOT_DIR/Resources/5a66d4f93f99d724718cca5919aecc1c.jpg"
ICONSET_DIR="$ROOT_DIR/Resources/AppIcon.iconset"
BASE_ICON="$ICONSET_DIR/icon_512x512@2x.png"
OUTPUT_ICON="$ROOT_DIR/Resources/AppIcon.icns"

mkdir -p "$ICONSET_DIR"

magick "$SOURCE_IMAGE" \
  -crop 282x270+20+26 +repage \
  -resize 1024x1024\! \
  \( -size 1024x1024 xc:none -fill white -draw "roundrectangle 0,0 1023,1023 190,190" \) \
  -alpha set -compose DstIn -composite \
  "PNG32:$BASE_ICON"

for size in 16 32 128 256 512; do
  magick "$BASE_ICON" -resize "${size}x${size}" "PNG32:$ICONSET_DIR/icon_${size}x${size}.png"
  magick "$BASE_ICON" -resize "$((size * 2))x$((size * 2))" "PNG32:$ICONSET_DIR/icon_${size}x${size}@2x.png"
done

python3 - "$ICONSET_DIR" "$OUTPUT_ICON" <<'PY'
import pathlib
import struct
import sys

iconset = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
chunks = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
]

body = bytearray()
for code, name in chunks:
    data = (iconset / name).read_bytes()
    body.extend(code.encode("ascii"))
    body.extend(struct.pack(">I", len(data) + 8))
    body.extend(data)

output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
PY

echo "Generated $OUTPUT_ICON"
