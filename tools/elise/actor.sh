#!/usr/bin/env bash
# Actor of the Elise pass: one round over the categories the loop gives (ElevenLabs reads each of her lines still to
# do, Whisper judges it, then the addon's index is rebuilt). Exit 75: ElevenLabs credits spent; 77: halt.
#   tools/elise/actor.sh <zone>...
set -euo pipefail
cd "$(dirname "$0")/../.."
if [ ! -x .venv-voices/bin/python ]; then
  echo "voice environment missing: tools/voices/setup.sh" >&2
  exit 77
fi
exec .venv-voices/bin/python -m tools.elise.act "$@"
