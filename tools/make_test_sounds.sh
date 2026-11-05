#!/usr/bin/env bash
# Generate the phase-1 test sounds with macOS `say` + ffmpeg (Ogg Vorbis, stereo, 44.1 kHz).
# Homebrew ffmpeg ships without libvorbis: the native (experimental) Vorbis encoder is used,
# which only supports 2 channels. Good enough for test sounds; revisit for phase 3.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=addon/ForeverSpeech/audio/test
VOICE="${VOICE:-Thomas}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

gen() { # name text
  say -v "$VOICE" -o "$TMP/$1.aiff" "$2"
  ffmpeg -loglevel error -y -i "$TMP/$1.aiff" -ac 2 -ar 44100 -c:a vorbis -strict experimental -q:a 6 "$OUT/$1.ogg"
  printf '%s.ogg\t%ss\n' "$1" "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/$1.ogg")"
}

gen test_1 "ForeverSpeech. Test numéro un."
gen test_2 "Test numéro deux. Ceci est un son plus long, d'environ dix secondes, qui sert à vérifier l'arrêt de la lecture et la détection de fin. Fin du test numéro deux."
