"""Quest texts captured in game (D1) into the zone registries: the text the game showed fills what the base lacks.

The addon captures the start text at QUEST_DETAIL (`ForeverSpeechCaptures.quests`: title, description, objectives,
giver) and the completion text at QUEST_COMPLETE (`ForeverSpeechCaptures.completions`). For each captured quest that a
registry holds (data/zones/**/quests.json):

- the capture is kept under `capture` (`detail`, `complete`), never the player's name: it proves the quest exists in
  Forever (the sync never retires it, pipeline/foreverdb/sync.py);
- a text the registry lacks (name, description, objectives, completion) is filled from it, channel and origin
  `capture` (`source.texts`, `source.origins`); the base import keeps it (pipeline/foreverdb/importer.py);
- a text the registry already has is never replaced (D13): when the capture differs from it (a quest Forever
  rewrote), it is listed, redoing it is a human decision;
- a quest with no giver (or ender) NPC in the registry gets the captured one, if the game said it is a creature.

The captured text is the one the player saw: their name, class and race were put in by the game. The name becomes
`<nom>` (always a form of address, pipeline/narration.py); the class and the race only when they are a form of
address (", guerrier." / "brave voleur !"), never in a sentence ("un guerrier sans égal"). The gender agreements are
those of the capturing character: no `<m/f>` variant can be rebuilt (D8), the capture records `player_sex`.

    python -m pipeline.captures quests "<SavedVariables>/ForeverSpeech.lua" [--zones DIR] [--dry-run] [--json]
"""

from __future__ import annotations

import collections
import difflib
import re
from pathlib import Path

from pipeline import storage
from pipeline.foreverdb.importer import convert_text
from pipeline.quests import registry as quest_registry
from pipeline.text import looks_english
from pipeline.wowhead.parse import placeholders

SAME = 0.85  # word similarity at or above which a captured text is the registry's (punctuation, spacing, names)
FILLS = {"detail": {"description": "text", "objectives": "objectives"}, "complete": {"completion": "text"}}
SPEAKERS = {"detail": ("starters", "giverID", "giverName", "giverType"),
            "complete": ("enders", "enderID", "enderName", "enderType")}
ADDRESS_BEFORE = r"(?:,\s*|\b(?:brave|jeune|digne|noble|cher|chère|vaillant|vaillante|courageux|courageuse)\s+)"


def _entries(table) -> list[dict]:
    """A capture table (questID -> capture, or a list) as a flat list of captures."""
    values = table.values() if isinstance(table, dict) else (table or [])
    out = []
    for value in values:
        out.extend(v for v in (value if isinstance(value, list) else [value]) if isinstance(v, dict))
    return out


def latest(captures: dict) -> dict[tuple[int, str], dict]:
    """(questID, kind) -> the most recently seen capture."""
    out: dict[tuple[int, str], dict] = {}
    for kind, table in (("detail", "quests"), ("complete", "completions")):
        for cap in _entries(captures.get(table)):
            qid = cap.get("questID")
            if not isinstance(qid, int) or not (cap.get("text") or "").strip():
                continue
            seen = out.get((qid, kind))
            if seen is None or (cap.get("lastSeen") or 0) >= (seen.get("lastSeen") or 0):
                out[(qid, kind)] = cap
    return out


def _word(value: str) -> str:
    return r"(?<![\w])" + re.escape(value) + r"(?![\w])"


def impersonal(text: str | None, cap: dict) -> str | None:
    """The captured text with the player put back as markers: name -> <nom>; class, race -> <classe>, <race> when
    they address the player."""
    text = convert_text(text)
    if not text:
        return None
    name = (cap.get("playerName") or "").strip()
    if name:
        text = re.sub(_word(name), "<nom>", text, flags=re.IGNORECASE)
    for key, marker in (("playerClass", "<classe>"), ("playerRace", "<race>")):
        value = (cap.get(key) or "").strip()
        if value:
            text = re.sub(f"({ADDRESS_BEFORE}){_word(value)}(?=\\s*[.!?,…])", lambda m: m.group(1) + marker, text,
                          flags=re.IGNORECASE)
    return text


def similarity(a: str, b: str) -> float:
    def tokens(s: str) -> list[str]:
        return re.findall(r"\w+", re.sub(r"<[^>]*>", " ", s.lower()))
    return difflib.SequenceMatcher(None, tokens(a), tokens(b), autojunk=False).ratio()


def _capture_record(cap: dict, kind: str, texts: dict[str, str | None]) -> dict:
    _, id_key, name_key, type_key = SPEAKERS[kind]
    return {"texts": texts, "npc": cap.get(id_key) or cap.get("npcID"), "npc_name": cap.get(name_key),
            "npc_type": cap.get(type_key), "npc_sex": cap.get("npcSex"), "player_sex": cap.get("playerSex"),
            "zone": cap.get("zone"), "map_id": cap.get("mapID"), "client": cap.get("client"),
            "first_seen": cap.get("firstSeen"), "last_seen": cap.get("lastSeen")}


def apply(record: dict, kind: str, cap: dict) -> dict:
    """Merge one capture into one registry record (in place). Returns what happened: filled fields, differing
    fields (with their similarity), speaker added."""
    texts = {field: impersonal(cap.get(key), cap) for field, key in FILLS[kind].items()}
    if kind == "detail":
        texts["name"] = convert_text(cap.get("title"))
    result: dict = {"filled": [], "differs": [], "speaker": None}
    source = record.setdefault("source", {})
    channels, origins = source.setdefault("texts", {}), source.setdefault("origins", {})
    for field, value in texts.items():
        if not value:
            continue
        current = record.get(field)
        if current:
            if channels.get(field) != "capture" and field != "name":
                score = similarity(current, value)
                if score < SAME:
                    result["differs"].append((field, round(score, 2)))
            continue
        if looks_english(value):
            continue
        record[field] = value
        channels[field], origins[field] = "capture", "capture"
        result["filled"].append(field)
    list_key, id_key, name_key, type_key = SPEAKERS[kind]
    npc = cap.get(id_key)
    if not any(s.get("type") == "npc" for s in record.get(list_key) or []) and isinstance(npc, int) \
            and cap.get(type_key) == "Creature":
        record[list_key] = [{"type": "npc", "id": npc, "name": cap.get(name_key)}] + list(record.get(list_key) or [])
        result["speaker"] = npc
    record["capture"] = {**(record.get("capture") or {}), kind: _capture_record(cap, kind, texts)}
    record["placeholders"] = sorted(set(placeholders(record.get("description")) +
                                        placeholders(record.get("objectives"))))
    record["missing"] = quest_registry.missing_fields(record)
    record["status"] = "incomplete" if record["missing"] else "complete"
    return result


def import_captures(captures: dict, zones_dir: Path | None = None, dry_run: bool = False) -> dict:
    zones_dir = zones_dir or storage.ZONES_DIR
    by_quest = collections.defaultdict(list)
    wanted = latest(captures)
    for (qid, kind), cap in wanted.items():
        by_quest[qid].append((kind, cap))
    report: dict = {"captures": len(wanted), "matched": 0, "unknown": [], "filled": [], "differs": [],
                    "speakers": [], "zones": collections.Counter()}
    seen: set[int] = set()
    for path in sorted(zones_dir.glob("**/quests.json")):
        data = storage.read_json(path) or {}
        key = str(path.parent.relative_to(zones_dir))
        changed = False
        for qid_str, record in (data.get("quests") or {}).items():
            qid = int(qid_str)
            if qid not in by_quest:
                continue
            seen.add(qid)
            for kind, cap in sorted(by_quest[qid], key=lambda kc: kc[0] != "detail"):
                report["matched"] += 1
                before = repr(record)
                result = apply(record, kind, cap)
                changed |= repr(record) != before
                row = {"quest": qid, "kind": kind, "zone": key, "title": record.get("name")}
                if result["filled"]:
                    report["filled"].append({**row, "fields": result["filled"]})
                    report["zones"][key] += 1
                for field, score in result["differs"]:
                    report["differs"].append({**row, "field": field, "score": score})
                if result["speaker"]:
                    report["speakers"].append({**row, "npc": result["speaker"]})
        if changed and not dry_run:
            storage.write_json(path, data)
    report["unknown"] = sorted(qid for qid in by_quest if qid not in seen)
    report["zones"] = dict(report["zones"])
    return report


def summary(report: dict) -> list[str]:
    lines = [f"{report['captures']} captured texts, {report['matched']} of quests in the registries, "
             f"{len(report['unknown'])} quests no registry holds"]
    kinds = collections.Counter(r["kind"] for r in report["filled"])
    lines.append(f"filled: {len(report['filled'])} texts (start {kinds['detail']}, end {kinds['complete']})")
    lines += [f"  {zone}: {n}" for zone, n in sorted(report["zones"].items(), key=lambda kv: -kv[1])]
    if report["speakers"]:
        lines.append(f"speaker NPC taken from the capture: {len(report['speakers'])}")
        lines += [f"  {r['quest']} {r['kind']} npc {r['npc']} ({r['zone']})" for r in report["speakers"]]
    lines.append(f"differs from the registry (kept, human decision): {len(report['differs'])}")
    lines += [f"  {r['quest']} {r['kind']} {r['field']} {r['score']:.2f} {r['title']} ({r['zone']})"
              for r in report["differs"]]
    if report["unknown"]:
        lines.append(f"quests no registry holds: {report['unknown']}")
    return lines
