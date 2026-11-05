#!/usr/bin/env bash
# Actor of the dialogues pass: one round over the categories the loop gives (one candidate take per dialogue reading
# still to do, judged as soon as it is generated). Exit 77: the voice environment is missing.
#   tools/dialogues/actor.sh <zone>...       (FS_NPCS="823 197": only these NPCs)
set -euo pipefail
cd "$(dirname "$0")/../.."
if [ ! -x .venv-voices/bin/python ]; then
  echo "voice environment missing: tools/voices/setup.sh" >&2
  exit 77
fi
exec .venv-voices/bin/python -m tools.dialogues.act "$@"
