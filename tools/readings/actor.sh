#!/usr/bin/env bash
# Actor of the readings pass: one task, one zone (one candidate take per reading still to do, judged as soon as it
# is generated, then the addon's index and the zone's listening page). Called by the loop with the zone the oracle
# names next; exit 77: the voice environment is missing (tools/voices/setup.sh).
#   tools/readings/actor.sh <zone>...       (a round: one or more categories; FS_NPCS="823 197": only these NPCs)
set -euo pipefail
cd "$(dirname "$0")/../.."
if [ ! -x .venv-voices/bin/python ]; then
  echo "voice environment missing: tools/voices/setup.sh" >&2
  exit 77
fi
exec .venv-voices/bin/python -m tools.readings.act "$@"
