#!/usr/bin/env bash
# Voice loop: reruns the voice pass category by category until every NPC who speaks has a validated voice, or was not
# found after 5 failed takes in this run, tools/voices/constitution.md. Each run first gives the NPCs without a
# voice 5 more takes (tools/voices/reopen.py). Keeps the Mac awake meanwhile (caffeinate).
# Where it stands: tools/loop/status.sh voices
#   tools/voices/run.sh (--all | --group eastern-kingdoms [--category elwynn-forest]...)
#       [--npc 823]... [--parallel 8] [--max-attempts 1000] [--reset-ratchet]
# --parallel: takes generated together on the GPU (default 8 on CUDA, 1 elsewhere). Follow: tools/loop/dashboard.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
.venv/bin/python -m tools.loop check voices "$@"  # wrong arguments: stop before reopening anything
if pgrep -f "tools[.]loop run dialogues" >/dev/null; then
  echo "the dialogues loop is running: one GPU, wait for it to finish" >&2
  exit 1
fi
.venv/bin/python -m pipeline.review apply  # the control page's decisions waiting for this moment
.venv/bin/python -m tools.voices.reopen
PY=(.venv/bin/python -m tools.loop run voices "$@")
if command -v caffeinate >/dev/null; then exec caffeinate -i "${PY[@]}"; fi
exec "${PY[@]}"
