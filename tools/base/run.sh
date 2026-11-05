#!/usr/bin/env bash
# Base loop: builds the Forever Database and imports the zone registries from it, until every zone is
# imported from the current version (tools/loop/README.md). First of the three loops: base, text, audio.
# Where it stands: tools/loop/status.sh base
#   tools/base/run.sh (--all | --group eastern-kingdoms [--category elwynn-forest]...) [--max-attempts 1000]
set -euo pipefail
cd "$(dirname "$0")/../.."
exec .venv/bin/python -m tools.loop run base "$@"
