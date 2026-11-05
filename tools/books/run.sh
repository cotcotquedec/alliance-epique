#!/usr/bin/env bash
# Books loop (D19): reruns the books pass until every page of every book of the Alliance scope has Elise's audio, or
# was not found after 5 failed takes in this run (tools/books/constitution.md). Each run first gives the pages not
# found 5 more takes (tools/books/reopen.py). Waits when the ElevenLabs credits are spent; stops when the run's budget
# is spent. Never beside the Elise loop (same ElevenLabs credits, same Whisper).
#   tools/books/run.sh --all [--budget 100000] [--round 100] [--max-attempts 1000] [--reset-ratchet]
#   tools/books/run.sh --dry-run [--budget N]    what a run would read and spend (offline: no ElevenLabs call)
#   tools/books/run.sh --help
# Before the first run: python -m pipeline.books extract && python -m pipeline.books scripts, then review and seal
# (tools/loop/seal.sh books). Follow it: tools/loop/dashboard.sh books ; tools/loop/status.sh books
set -euo pipefail
cd "$(dirname "$0")/../.."
for arg in "$@"; do
  case "$arg" in
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --dry-run) exec .venv/bin/python -m tools.books.plan "$@" ;;
  esac
done
.venv/bin/python -m tools.loop check books "$@"  # wrong arguments: stop before reopening anything
if pgrep -f "tools[.]loop run elise" >/dev/null; then
  echo "the Elise loop is running: both spend the same ElevenLabs credits, wait for it to finish" >&2
  exit 1
fi
.venv/bin/python -m pipeline.review apply --kind book  # the control page's decisions waiting for this moment
.venv/bin/python -m tools.books.reopen
PY=(.venv/bin/python -m tools.loop run books "$@")
if command -v caffeinate >/dev/null; then exec caffeinate -i "${PY[@]}"; fi
exec "${PY[@]}"
