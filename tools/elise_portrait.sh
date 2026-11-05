#!/usr/bin/env bash
# Convert Elise's painted portrait (master data/icons/elise/portrait.png, not in git) into the addon's texture:
# 256x256 uncompressed 32-bit TGA, bottom-left origin like tools/make_icons.py (media/elise.tga), shown in place of a
# model in the player window (ui/player_frame.lua, PORTRAIT).
# Master: OpenRouter skill openrouter-images, model google/gemini-3.1-flash-image-preview, 1:1, 1024x1024, variant 3
# of 3 (2026-10-15; the others: portrait-variant-<n>.png). Prompt: a night elf Sentinel, calm, shy, mysterious and
# wise, a faint half-smile, moonlight, desert dunes and the Scarab Wall behind her (D9, D17).
#   tools/elise_portrait.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/data/icons/elise/portrait.png"
TGA="$ROOT/addon/ForeverSpeech/media/elise.tga"

# ffmpeg writes top-left rows (descriptor 0x28): flip the rows, then mark the origin bottom-left (0x08)
ffmpeg -loglevel error -y -i "$SRC" -vf "scale=256:256:flags=lanczos,vflip,format=bgra" -rle 0 "$TGA"
printf '\x08' | dd of="$TGA" bs=1 seek=17 conv=notrunc status=none
echo "wrote $TGA"
