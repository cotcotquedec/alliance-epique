#!/usr/bin/env bash
# Text loop: reruns the text pass category by category until every category has its text (tools/loop/README.md).
# Keeps the Mac awake meanwhile (caffeinate). Where it stands: tools/loop/status.sh text
#   tools/text/run.sh (--all | --group eastern-kingdoms [--category elwynn-forest]...) [--max-attempts 1000]
set -euo pipefail
cd "$(dirname "$0")/../.."
PY=(.venv/bin/python -m tools.loop run text "$@")
if command -v caffeinate >/dev/null; then exec caffeinate -i "${PY[@]}"; fi
exec "${PY[@]}"
