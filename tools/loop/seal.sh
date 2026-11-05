#!/usr/bin/env bash
# After reviewing a pass's read-only objects (constitution, oracle, arbiter...): seal them.
#   tools/loop/seal.sh base|text|voices|readings
set -euo pipefail
cd "$(dirname "$0")/../.."
exec .venv/bin/python -m tools.loop seal "$@"
