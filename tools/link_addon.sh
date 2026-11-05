#!/usr/bin/env bash
# Symlink addon/ForeverSpeech into the game's AddOns folder (dev setup): the game loads the working copy.
# Usage: tools/link_addon.sh [game_flavor_dir]
#   Mac (default): /Volumes/Games/Battle.net/World of Warcraft/_forever_ (Battle.net product "wowf", the stress
#   test then the release; since 2026-10-21, before: _classic_beta_; external disk "Games", 2026-10-16)
#   WSL2 on the Windows PC (default): /mnt/d/Games/World of Warcraft/_forever_ (not checked on the PC) ; the game runs on Windows, so
#   the link is a Windows directory symlink (mklink /D, Windows developer mode) to \\wsl.localhost\<distro>\...:
#   Ubuntu must be running while the game plays (it is as long as a WSL terminal is open). 2026-10-12.
set -euo pipefail
cd "$(dirname "$0")/.."
WSL=0
if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then WSL=1; fi
if [[ $WSL -eq 1 ]]; then
  GAME="${1:-/mnt/d/Games/World of Warcraft/_forever_}"
else
  GAME="${1:-/Volumes/Games/Battle.net/World of Warcraft/_forever_}"
fi
if [ ! -d "$GAME" ]; then
  echo "game folder not found: $GAME (external disk not mounted?)" >&2
  exit 1
fi
ADDONS="$GAME/Interface/AddOns"
TARGET="$ADDONS/ForeverSpeech"
mkdir -p "$ADDONS"
if [ -L "$TARGET" ] || { [[ $WSL -eq 1 ]] && [ -e "$TARGET" ] && [ -f "$TARGET/ForeverSpeech.toc" ] \
    && cmd.exe /c dir /AL "$(wslpath -w "$ADDONS")" 2>/dev/null | grep -q ForeverSpeech; }; then
  echo "already linked: $TARGET"
elif [ -e "$TARGET" ]; then
  echo "refusing: $TARGET exists and is not a symlink" >&2
  exit 1
elif [[ $WSL -eq 1 ]]; then
  SOURCE="\\\\wsl.localhost\\$WSL_DISTRO_NAME$(echo "$PWD/addon/ForeverSpeech" | tr / '\\')"
  (cd /mnt/c && cmd.exe /c mklink /D "$(wslpath -w "$ADDONS")\\ForeverSpeech" "$SOURCE") | tr -d '\r'
else
  ln -s "$PWD/addon/ForeverSpeech" "$TARGET"
  echo "linked: $TARGET -> $PWD/addon/ForeverSpeech"
fi
[ -f addon/ForeverSpeech/data/game_voices.lua ] || \
  echo "warning: addon/ForeverSpeech/data/game_voices.lua missing (not versioned): .venv/bin/python -m pipeline.game_voices" >&2
