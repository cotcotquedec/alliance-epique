#!/usr/bin/env bash
# Where a loop stands: its last attempt (data/cache/loops/<pass>/last.json) and its backlog.
#   tools/loop/status.sh base|text|voices|readings
set -euo pipefail
cd "$(dirname "$0")/../.."
exec .venv/bin/python -m tools.loop status "$@"
