#!/usr/bin/env bash
# Dashboard of a running loop (progress of the run, of the current category, and of each take of the batch),
# redrawn every second. Run it beside the loop: another terminal, or a tmux pane (Ctrl-b % then this command).
#   tools/loop/dashboard.sh [voices|readings|dialogues|elise|text|base] [--once]     (default: the loop updated last)
set -euo pipefail
cd "$(dirname "$0")/../.."
exec .venv/bin/python -m tools.loop.dashboard "$@"
