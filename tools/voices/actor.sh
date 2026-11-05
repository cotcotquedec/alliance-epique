#!/usr/bin/env bash
# Actor of the voice pass: one task, one zone (one candidate take per NPC still without a voice, then the
# judge, then the zone's listening page). Called by the loop with the zone the oracle names next; exit 77: the
# voice environment is missing (tools/voices/setup.sh).
#   tools/voices/actor.sh <zone>...          (a round: one or more categories, chosen by tools/loop/engine.py)
set -euo pipefail
cd "$(dirname "$0")/../.."
if [ ! -x .venv-voices/bin/python ]; then
  echo "voice environment missing: tools/voices/setup.sh" >&2
  exit 77
fi
exec .venv-voices/bin/python -m tools.voices.act "$@"
