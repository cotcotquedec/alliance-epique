#!/usr/bin/env bash
# Elise loop: reruns the Elise pass category by category until every line of Elise has its audio, or was not found
# after 5 failed takes in this run (tools/elise/constitution.md). Each run first writes the zone introductions still
# without a text (Claude, pipeline/zone_intros; never one already written), then gives the lines not found 5 more
# takes (tools/elise/reopen.py). Waits when the ElevenLabs credits are spent. Never beside the readings loop: both
# write the categories' audio.json.
#   tools/elise/run.sh (--all | --group eastern-kingdoms [--category elwynn-forest]...) [--kind zone|quest]
#       [--max-attempts 1000] [--reset-ratchet]   (--kind zone|level|companion|quest)
#   --kind zone: only her zone introductions (--all, or --group G: that continent's); --kind quest: only her quest
#   lines; --kind level: only her level-up lines (--all only). Each run also writes her level-up story if missing.
#   --kind companion: only her companion lines (D18, written by hand: nothing to write before the run; --all only).
# Follow it: tools/loop/dashboard.sh elise ; tools/loop/status.sh elise
set -euo pipefail
cd "$(dirname "$0")/../.."
.venv/bin/python -m tools.loop check elise "$@"  # wrong arguments: stop before reopening anything
if pgrep -f "tools[.]loop run readings" >/dev/null; then
  echo "the readings loop is running: both write the categories' audio.json, wait for it to finish" >&2
  exit 1
fi
if pgrep -f "tools[.]loop run books" >/dev/null; then
  echo "the books loop is running: both spend the same ElevenLabs credits, wait for it to finish" >&2
  exit 1
fi
kind=""
prev=""
for arg in "$@"; do
  [[ "$prev" == "--kind" ]] && kind=$arg
  [[ "$arg" == --kind=* ]] && kind=${arg#--kind=}
  prev=$arg
done
if [[ -z "$kind" || "$kind" == "zone" ]]; then  # the zone introductions still without a text (Claude; not fatal)
  .venv/bin/python -m pipeline.zone_intros generate \
    || echo "zone introductions: some texts could not be written (Claude): the loop goes on without them" >&2
fi
if [[ -z "$kind" || "$kind" == "level" ]]; then  # her level-up story, if not written yet (Claude; not fatal)
  .venv/bin/python -m pipeline.level_lines generate \
    || echo "level-up lines: the story could not be written (Claude): the loop goes on without it" >&2
fi
.venv/bin/python -m pipeline.review apply  # the control page's decisions waiting for this moment
.venv/bin/python -m tools.elise.reopen
PY=(.venv/bin/python -m tools.loop run elise "$@")
if command -v caffeinate >/dev/null; then exec caffeinate -i "${PY[@]}"; fi
exec "${PY[@]}"
