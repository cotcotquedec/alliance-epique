#!/usr/bin/env bash
# Is there a newer Forever Database release (tag) than our build? Read-only (pipeline/foreverdb/release.py).
#   tools/db_check.sh       exit 0: up to date, 10: newer release (or nothing built), 2: cannot tell
set -euo pipefail
cd "$(dirname "$0")/.."
exec .venv/bin/python -m pipeline.foreverdb.release check
