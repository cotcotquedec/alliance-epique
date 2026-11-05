#!/usr/bin/env bash
# The text of the game category by category (personas, then scripts), Alliance only, low-level first: the
# actor of the text loop (tools/text/actor.sh). The voices and the audio are the voice and readings loops.
#
#   tools/all_zones.sh text [--dry-run] [zone...]    # personas + scripts, every category
#   tools/all_zones.sh status [--all]                # where each category stands
#
# Order: `tools/zone.sh order --side alliance`, i.e. by median level of the zone's Alliance quests
# (category pages not cached yet are fetched once). With zones given, only those, in that order.
# Quests: those of the Alliance or of both sides, whatever their level; Horde-only quests are left out.
#
# The zone registries come first from the Forever Database (tools/base/run.sh, or tools/prepare_db.sh then
# tools/zone.sh import): no Wowhead crawling any more (2026-10-06).
# text:  personas (Claude) -> scripts (Claude), start and end of quest.
# Progress lives in the data files themselves (each persona and script is saved as soon as it is made), so the
# pass is idempotent: rerunning it skips what is done and resumes where it stopped, e.g. after the Claude usage
# limit (exit 75). `status` reads it back. The script stops at the first error (usage limit, Wowhead block...).
set -euo pipefail
cd "$(dirname "$0")/.."

SIDE=alliance

usage() { sed -n '5,6p' "$0" | sed 's/^# *//'; exit 1; }
MODE="${1:-}"
if [[ "$MODE" == "status" ]]; then shift; exec tools/zone.sh progress --side "$SIDE" "$@"; fi
[[ "$MODE" == "text" ]] || usage
shift
DRY=0
if [[ "${1:-}" == "--dry-run" ]]; then DRY=1; shift; fi

if [[ $# -gt 0 ]]; then
  ZONES=("$@")
else
  ORDER=$(tools/zone.sh order --side "$SIDE")
  echo "Zone order (median level, $SIDE quests, levels):"
  echo "$ORDER" | awk -F'\t' '{ printf "  %3d %-45s %5s %4s  %s\n", NR, $1, $2, $3, $4 }'
  # macOS ships bash 3.2: no mapfile; zone keys have no spaces.
  read -r -a ZONES <<< "$(echo "$ORDER" | cut -f1 | tr '\n' ' ')"
fi

# Runs a step; on failure says where the pass stopped and how to resume, then stops.
run() {
  echo; echo "+ $*"
  local code=0
  "$@" || code=$?
  if [[ $code -ne 0 ]]; then
    echo
    case $code in
      75) echo "STOPPED: Claude usage limit reached, during $zone." ;;
      69) echo "STOPPED: Wowhead refused us (403/429), during $zone." ;;
      76) echo "STOPPED: ElevenLabs credits or voice creations of the month exhausted, during $zone." ;;
      78) echo "STOPPED: not enough free ElevenLabs voice slots, during $zone." ;;
      *) echo "STOPPED: error $code during $zone." ;;
    esac
    echo "Everything generated so far is saved. Resume later with: tools/all_zones.sh $MODE"
    echo "Progress: tools/all_zones.sh status"
    exit "$code"
  fi
}
dry() { if [[ $DRY -eq 1 ]]; then echo "--dry-run"; fi; }

echo "$MODE: ${#ZONES[@]} zone(s)"
for zone in "${ZONES[@]}"; do
  echo; echo "=================== $zone ($MODE) ==================="
  if [[ $DRY -eq 1 ]]; then
    run tools/zone.sh personas "$zone" --side "$SIDE" --dry-run || true
    run tools/zone.sh scripts "$zone" --side "$SIDE" --dry-run || true
    continue
  fi
  run tools/zone.sh personas "$zone" --side "$SIDE"
  run tools/zone.sh scripts "$zone" --side "$SIDE"
done

# The state of every zone, only after a whole pass (not after each zone the loops run one by one).
if [[ $# -eq 0 ]]; then
  echo
  for group in eastern-kingdoms kalimdor dungeons raids battlegrounds world-events classes professions uncategorized; do
    tools/zone.sh list --group "$group" | grep -v " todo " || true
  done
fi
