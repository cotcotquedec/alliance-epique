"""Elise's companion lines (D18, 2026-10-14): when a companion reaches a friendship tier, Elise says one of the
tier's 10 lines. Written by hand (no generator), versioned: data/zones/@elise/companions/scripts.json, with the
tiers in order ("tiers") and the lines ("lines", keyed "good_friend-03": {tier, variant, text}), all said by Elise
(top-level npc_id NARRATOR_ID). Each line has a numeric ID, the one of the addon's index (v8): its tier's place
(1 = encounter) times 100, plus its variant (401: good friend, line 1). The Elise loop reads them there
(tools/elise/frame.py, kind "companion", line ID "<ID>_companion") and keeps their audio in audio.json, section
"companion", keyed by that ID.
"""

from pipeline import narrator
from pipeline.storage import ZONES_DIR

KEY = "@elise/companions"  # loop key of the folder (in no group nor category: covered by --all)
SECTION = "lines"  # scripts.json section


def folder():
    return ZONES_DIR / KEY


def keys(zones_dir=None) -> list[str]:
    """[KEY] once its scripts.json exists, else []."""
    return [KEY] if ((zones_dir or ZONES_DIR) / KEY / "scripts.json").exists() else []


def line_id(tier_place: int, variant: int) -> int:
    """The ID of a line: its tier's place (1 = encounter) times 100, plus its variant."""
    return tier_place * 100 + variant


def lines(scripts: dict | None) -> list[dict]:
    """The lines with a text of a companions scripts.json, in ID order: [{id, key, tier, name, text}] ("name": the
    tier's name and the variant, "Bon ami 3"); [] for any other scripts.json, or one not said by Elise."""
    scripts = scripts or {}
    tiers = scripts.get("tiers") or []
    if not tiers or not narrator.is_narrator(scripts.get("npc_id")):
        return []
    place = {t["key"]: (i, t.get("name_m") or t["key"]) for i, t in enumerate(tiers, 1)}
    out = []
    for key, line in (scripts.get(SECTION) or {}).items():
        if line.get("text") and line.get("tier") in place:
            n, name = place[line["tier"]]
            out.append({"id": line_id(n, int(line["variant"])), "key": key, "tier": line["tier"],
                        "name": f"{name} {int(line['variant'])}", "text": line["text"]})
    return sorted(out, key=lambda line: line["id"])
