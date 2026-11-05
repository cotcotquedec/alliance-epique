#!/usr/bin/env bash
# Readings loop: reruns the readings pass category by category until every quest text whose NPC has a model voice has its
# audio, or was not found after 5 failed takes in this run, tools/readings/constitution.md. Each run first gives
# the readings not found 5 more takes (tools/readings/reopen.py). Keeps the Mac awake meanwhile (caffeinate).
# Where it stands: tools/loop/status.sh readings ; tools/report.sh
#   tools/readings/run.sh (--all | --group eastern-kingdoms [--category elwynn-forest]...)
#       [--npc 823]... [--parallel 8] [--max-attempts 1000] [--reset-ratchet]
# --parallel: takes generated together on the GPU (default 8 on CUDA, 1 elsewhere). Follow: tools/loop/dashboard.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
.venv/bin/python -m tools.loop check readings "$@"  # wrong arguments: stop before reopening anything
if pgrep -f "tools[.]loop run elise" >/dev/null; then
  echo "the Elise loop is running: both write the categories' audio.json, wait for it to finish" >&2
  exit 1
fi
if pgrep -f "tools[.]loop run dialogues" >/dev/null; then
  echo "the dialogues loop is running: one GPU, wait for it to finish" >&2
  exit 1
fi
.venv/bin/python -m pipeline.review apply  # the control page's decisions waiting for this moment
.venv/bin/python -m tools.readings.reopen
PY=(.venv/bin/python -m tools.loop run readings "$@")
if command -v caffeinate >/dev/null; then exec caffeinate -i "${PY[@]}"; fi
exec "${PY[@]}"
