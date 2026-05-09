#!/usr/bin/env bash
# Build a macOS light/dark dynamic wallpaper (.heic) from two PNGs.
# Requires: imagemagick, libheif, exiftool  (brew install imagemagick libheif exiftool)
#
# Usage: ./build.sh [name]
#   Reads  src/<name>/light.png and src/<name>/dark.png
#   Writes dist/<name>.heic

set -euo pipefail

NAME="${1:-ponor-brush}"
LIGHT="src/$NAME/light.png"
DARK="src/$NAME/dark.png"
OUT="dist/$NAME.heic"
LIGHT_OUT="dist/$NAME-light.jpg"
DARK_OUT="dist/$NAME-dark.jpg"

# Max width for the standalone JPEGs. 3840 covers 4K displays with headroom and
# keeps the file in the low-MBs at q88 instead of the 50MB+ source PNGs.
JPG_MAX_WIDTH=3840
JPG_QUALITY=88

mkdir -p "$(dirname "$OUT")"

# Match the light image's resolution to the dark image so both frames are the
# same size in the HEIC. macOS stretches whichever frame it shows, so identical
# dimensions keep the transition seamless.
read -r W H < <(sips -g pixelWidth -g pixelHeight "$DARK" \
  | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w, h}')

TMP_LIGHT="$(mktemp -t ponor-light).png"
TMP_CONFIG="$(mktemp -t apple-desktop)"
trap 'rm -f "$TMP_LIGHT" "$TMP_CONFIG"' EXIT

magick "$LIGHT" -resize "${W}x${H}!" -strip "$TMP_LIGHT"

# Combine both images into a single HEIC. Order matters: index 0 = light, 1 = dark.
heif-enc -q 90 -o "$OUT" "$TMP_LIGHT" "$DARK"

# Apple's appearance metadata is a base64-encoded binary plist {l: 0, d: 1}
# stored under XMP key apple_desktop:apr.
APR_B64="$(python3 -c "
import plistlib, base64
print(base64.b64encode(plistlib.dumps({'l': 0, 'd': 1}, fmt=plistlib.FMT_BINARY)).decode())
")"

# exiftool doesn't know the apple_desktop namespace out of the box, so feed it
# a minimal config that registers apr/solar/h24 tags.
cat > "$TMP_CONFIG" <<'PERL'
%Image::ExifTool::UserDefined = (
  'Image::ExifTool::XMP::Main' => {
    apple_desktop => {
      SubDirectory => { TagTable => 'Image::ExifTool::UserDefined::apple_desktop' },
    },
  },
);
%Image::ExifTool::UserDefined::apple_desktop = (
  GROUPS    => { 0 => 'XMP', 1 => 'XMP-apple_desktop', 2 => 'Image' },
  NAMESPACE => { 'apple_desktop' => 'http://ns.apple.com/namespace/1.0/' },
  WRITABLE  => 'string',
  apr   => { },
  solar => { },
  h24   => { },
);
1;
PERL

exiftool -config "$TMP_CONFIG" -overwrite_original \
  -XMP-apple_desktop:apr="$APR_B64" "$OUT" >/dev/null

echo "Wrote $OUT"

# Standalone JPEGs for Linux / non-macOS use. Resize only if the source is
# wider than JPG_MAX_WIDTH; progressive + 4:2:0 keeps file size down without
# visible quality loss at wallpaper viewing distance.
for pair in "$LIGHT:$LIGHT_OUT" "$DARK:$DARK_OUT"; do
  src="${pair%%:*}"
  dst="${pair##*:}"
  magick "$src" \
    -resize "${JPG_MAX_WIDTH}x>" \
    -strip \
    -interlace Plane \
    -sampling-factor 4:2:0 \
    -quality "$JPG_QUALITY" \
    "$dst"
  echo "Wrote $dst"
done
