#!/usr/bin/env bash
# Actor of the books pass: one round (ElevenLabs reads up to FS_ROUND_TAKES book pages still to do in Elise's voice,
# Whisper judges each take, then the addon's index is rebuilt). Exit 75: ElevenLabs credits spent; 76: the run's
# budget is spent; 77: halt.
#   tools/books/actor.sh @books
set -euo pipefail
cd "$(dirname "$0")/../.."
if [ ! -x .venv-voices/bin/python ]; then
  echo "voice environment missing: tools/voices/setup.sh" >&2
  exit 77
fi
exec .venv-voices/bin/python -m tools.books.act "$@"
