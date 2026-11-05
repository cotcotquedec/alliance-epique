#!/usr/bin/env bash
# Convert the side tab icons (painted masters, data/icons/tabs/<key>.png, not in git) into the addon's textures:
# 64x64 uncompressed 32-bit TGA, bottom-left origin like tools/make_icons.py (media/tabs/<key>.tga).
# Masters: OpenRouter skill openrouter-images, model google/gemini-3-pro-image, 1:1, 1K (2026-10-15).
#   tools/tab_icons.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/data/icons/tabs"
OUT="$ROOT/addon/ForeverSpeech/media/tabs"
mkdir -p "$OUT"

for png in "$SRC"/*.png; do
  tga="$OUT/$(basename "$png" .png).tga"
  # ffmpeg writes top-left rows (descriptor 0x28): flip the rows, then mark the origin bottom-left (0x08)
  ffmpeg -loglevel error -y -i "$png" -vf "scale=64:64:flags=lanczos,vflip,format=bgra" -rle 0 "$tga"
  printf '\x08' | dd of="$tga" bs=1 seek=17 conv=notrunc status=none
  echo "wrote $tga"
done
