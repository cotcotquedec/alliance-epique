#!/usr/bin/env bash
# Shortcut for the zone-by-zone data commands: tools/zone.sh list | plan elwynn-forest | fetch 12 ...
set -euo pipefail
cd "$(dirname "$0")/.."
exec .venv/bin/python -m pipeline.zones "$@"
