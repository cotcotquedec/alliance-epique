#!/usr/bin/env bash
# Actor of the text pass: one task, one zone (fetch -> personas -> scripts). Called by the loop with the
# zone the oracle names next; its exit code is the one of the failed step (75 Claude limit, 69 Wowhead block).
#   tools/text/actor.sh <zone>
set -euo pipefail
cd "$(dirname "$0")/../.."
exec tools/all_zones.sh text "$1"
