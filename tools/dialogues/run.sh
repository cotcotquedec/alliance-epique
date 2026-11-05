#!/usr/bin/env bash
# Dialogues loop: reruns the dialogues pass category by category until every dialogue page whose NPC has a model
# voice has its audio, or was not found after 5 failed takes in this run (tools/dialogues/constitution.md). Each run
# first gives the readings not found 5 more takes (tools/dialogues/reopen.py). One GPU: never beside the voice or
# readings loop.
#   tools/dialogues/run.sh (--all | --group eastern-kingdoms [--category elwynn-forest]...)
#       [--npc 823]... [--parallel 8] [--max-attempts 1000] [--reset-ratchet]
# Follow it: tools/loop/dashboard.sh dialogues ; tmux: tools/dialogues/start.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
.venv/bin/python -m tools.loop check dialogues "$@"
if pgrep -f "tools[.]loop run (voices|readings)" >/dev/null; then
  echo "the voice or readings loop is running: one GPU, wait for it to finish" >&2
  exit 1
fi
.venv/bin/python -m pipeline.review apply  # the control page's decisions waiting for this moment
.venv/bin/python -m tools.dialogues.reopen
PY=(.venv/bin/python -m tools.loop run dialogues "$@")
if command -v caffeinate >/dev/null; then exec caffeinate -i "${PY[@]}"; fi
exec "${PY[@]}"
