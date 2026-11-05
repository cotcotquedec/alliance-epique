"""Quest records of a zone registry (data/zones/<zone>/quests.json).

French only (decided 2026-10-05): a text that is missing, untranslated or still in English is
not kept but listed in `missing`, so that an in-game capture can fill it later (D1). The
companion stores captures under `capture`, which a refetch preserves.
"""

from __future__ import annotations

from pipeline.text import looks_english
from pipeline.wowhead.parse import placeholders

SCHEMA = 1
TEXT_FIELDS = ("name", "objectives", "description", "progress", "completion")
# What the narration needs (D6: acceptance text = description then objectives) and who says it.
REQUIRED = ("name", "objectives", "description", "giver")
SIDES = {1: "alliance", 2: "horde", 3: "both"}


def quest_record(parsed: dict, http: int, fetched_at: str | None) -> dict:
    texts = {}
    not_french = []
    for field in TEXT_FIELDS:
        value = parsed.get(field)
        english = (field == "name" and parsed.get("untranslated")) or looks_english(value)
        if value and english:
            not_french.append(field)
            value = None
        texts[field] = value
    record = {
        "id": parsed["id"],
        **texts,
        "starters": parsed.get("starters", []),
        "enders": parsed.get("enders", []),
        "zone_id": parsed.get("zone_id"),
        "level": parsed.get("level"),
        "reqlevel": parsed.get("reqlevel"),
        "side": SIDES.get(parsed.get("side")),
        "xp": parsed.get("xp"),
        "money": parsed.get("money"),
        "forever": {"status": parsed.get("env_status"), "patch": parsed.get("added_patch")},
        "placeholders": sorted(set(placeholders(texts["description"]) + placeholders(texts["objectives"]))),
        "not_french": not_french,
        "wowhead": {"http": http, "fetched_at": fetched_at},
        "capture": None,
    }
    record["missing"] = missing_fields(record)
    record["status"] = quest_status(record)
    return record


def unavailable_record(quest_id: int, http: int, fetched_at: str | None) -> dict:
    """A quest listed by the category but whose page is missing."""
    record = {"id": quest_id, **dict.fromkeys(TEXT_FIELDS), "starters": [], "enders": [],
              "not_french": [], "wowhead": {"http": http, "fetched_at": fetched_at}, "capture": None}
    record["missing"] = list(REQUIRED)
    record["status"] = "unavailable"
    return record


def missing_fields(record: dict) -> list[str]:
    missing = [f for f in REQUIRED if f != "giver" and not record.get(f)]
    if not record.get("starters"):
        missing.append("giver")  # item-started or unknown (S6): narrator voice unless a capture says otherwise
    return missing


def quest_status(record: dict) -> str:
    if record["wowhead"]["http"] != 200:
        return "unavailable"
    return "incomplete" if record["missing"] else "complete"


def merge_previous(new: dict[int, dict], previous: dict[str, dict]) -> dict[int, dict]:
    """Keep what the companion added: captures, and quests only known from a capture."""
    merged = dict(new)
    for key, old in previous.items():
        qid = int(key)
        if qid in merged:
            merged[qid]["capture"] = old.get("capture")
        elif old.get("status") == "capture_only":
            merged[qid] = old
    return merged


def summarize(quests: dict) -> dict:
    records = list(quests.values())

    def count(pred) -> int:
        return sum(1 for r in records if pred(r))

    return {
        "quests": len(records),
        "complete": count(lambda r: r["status"] == "complete"),
        "incomplete": count(lambda r: r["status"] == "incomplete"),
        "unavailable": count(lambda r: r["status"] == "unavailable"),
        "missing_description": count(lambda r: "description" in r["missing"]),
        "missing_giver": count(lambda r: "giver" in r["missing"]),
        "new_in_forever": count(lambda r: (r.get("forever") or {}).get("status") == "new"),
        "gendered": count(lambda r: any("/" in p for p in r.get("placeholders", []))),
    }
