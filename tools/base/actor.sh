#!/usr/bin/env bash
# Actor of the base pass: one task, the whole base. Builds the Forever Database if needed (.data/,
# tools/prepare_db.sh), then imports every zone registry from it (tools/zone.sh import). The zone argument
# the loop passes ("all") is not used.
#   tools/base/actor.sh [all]
set -euo pipefail
cd "$(dirname "$0")/../.."
tools/prepare_db.sh
tools/zone.sh import
