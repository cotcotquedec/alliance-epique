"""Quest giver records of a zone registry (data/zones/<zone>/npcs.json)."""

from __future__ import annotations

SCHEMA = 1


def npc_record(parsed: dict, voice: dict, voice_source: str | None,
               wowhead: dict, wowhead_classic: dict | None) -> dict:
    name = parsed.get("name")
    if name and name.startswith("[") and name.endswith("]"):
        name = None  # untranslated, French only
    record = {
        "id": parsed["id"],
        "name": name,
        "title": parsed.get("tag"),
        "type": parsed.get("type"),
        "classification": parsed.get("classification"),
        "react": {"alliance": parsed.get("react_alliance"), "horde": parsed.get("react_horde")},
        "zones": parsed.get("zones", []),
        "coords": parsed.get("coords", {}),
        "levels": [parsed.get("minlevel"), parsed.get("maxlevel")],
        "display_id": parsed.get("display_id"),
        "quests_started": parsed.get("starts", []),
        "quests_ended": parsed.get("ends", []),
        "forever": {"status": parsed.get("env_status")},
        "voice": {"source": voice_source, **voice},
        "wowhead": wowhead,
        "wowhead_classic": wowhead_classic,
    }
    record["missing"] = [f for f in ("name", "display_id") if not record[f]]
    if voice.get("kind") in ("unknown", "none"):
        record["missing"].append("voice")
    return record


def unavailable_record(npc_id: int, wowhead: dict) -> dict:
    return {"id": npc_id, "name": None, "display_id": None, "voice": {"kind": "unknown", "reason": "no_page"},
            "wowhead": wowhead, "wowhead_classic": None, "missing": ["name", "display_id", "voice"]}


def summarize(npcs: dict) -> dict:
    records = list(npcs.values())
    kinds: dict[str, int] = {}
    for r in records:
        kind = r["voice"]["kind"]
        kinds[kind] = kinds.get(kind, 0) + 1
    return {
        "npcs": len(records),
        "with_display_id": sum(1 for r in records if r.get("display_id")),
        "with_title": sum(1 for r in records if r.get("title")),
        "new_in_forever": sum(1 for r in records if (r.get("forever") or {}).get("status") == "new"),
        "voices": dict(sorted(kinds.items())),
    }
