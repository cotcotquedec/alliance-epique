#!/usr/bin/env bash
# Completion table by quest category, from the data files only: NPCs, personas, voices, quests, start and end
# scripts, start and end audio. Always says what it covers: every group, a group, or categories of a group.
#   tools/report.sh --all
#   tools/report.sh --group classes
#   tools/report.sh --group eastern-kingdoms --category elwynn-forest [--full] [--json]
set -euo pipefail
cd "$(dirname "$0")/.."
exec .venv/bin/python -m pipeline.zones report "$@"
