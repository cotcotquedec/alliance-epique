"""Where each French quest text of the registries comes from (2026-10-21): `source.origins` = {field: origin}.

`source.texts` says which channel brought a text into the registry: `wowhead` (our crawl, D10) or `foreverdb`. The
Forever Database itself merges several upstreams into its French texts (etl/build.py, build_l10n) and does not say
which one gave a text, except AzerothCore. The origin is the upstream whose raw text equals the database's, tried in
the database's own order of preference.

Origins:
- `wowhead`: our crawl of wowhead.com/forever/fr (cache data/cache/wowhead/), the Forever text;
- `capture`: the text shown in game (D1), once captures are imported;
- `foreverdb:questie`: QuestieDB's translations (titles, objectives);
- `foreverdb:vmangos`: VMaNGOS' locales_quest, the Classic text;
- `foreverdb:client_cache`: texts the database read from WoW client caches (questcache.wdb);
- `foreverdb:wowhead`: texts the database fetched from Wowhead for the quests the others lack;
- `foreverdb:azerothcore`: AzerothCore's translations (WotLK data, only fields Classic has);
- `foreverdb:unknown`: no upstream matches (the database changed its rules: read etl/build.py again).

    python -m pipeline.foreverdb.origins [--dry-run]    # fills source.origins in every registry, and the
                                                        # source/origins of the quest scripts, nothing else
"""

from __future__ import annotations

import argparse
import collections
import functools
import json
import sqlite3
from pathlib import Path

from pipeline import storage

DB_DIR = storage.REPO_ROOT / ".data" / "forever-db"
QUESTIE_L10N = DB_DIR / "build" / "questie" / "forever" / "l10n.json"
VMANGOS_SQLITE = DB_DIR / "vendor" / "vmangos" / "sqlite-dump" / "mangos.sqlite"
CORRECTIONS = DB_DIR / "etl" / "corrections"
LOCALE, VMANGOS_LOCALE = "frFR", 2

# our field -> the database's field (pipeline/foreverdb/importer.py, FIELDS)
DB_FIELDS = {"name": "name", "objectives": "objectivesText", "description": "details", "progress": "progress",
             "completion": "completion"}
VMANGOS_COLUMNS = {"name": "Title", "objectivesText": "Objectives", "details": "Details",
                   "progress": "RequestItemsText", "completion": "OfferRewardText"}
# the database's order of preference: QuestieDB, VMaNGOS, client caches, then Wowhead (both merged as its
# "cache texts"), AzerothCore last
ORDER = ("questie", "vmangos", "client_cache", "wowhead")


def _flat(value) -> str | None:
    if isinstance(value, list):
        value = "\n".join(v for v in value if v)
    return value.strip() if isinstance(value, str) and value.strip() else None


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


@functools.lru_cache(maxsize=1)
def upstreams() -> dict[str, dict[int, dict[str, str]]]:
    """{upstream: {quest id: {database field: raw French text}}}; an upstream absent on disk is empty."""
    out: dict[str, dict[int, dict[str, str]]] = {name: collections.defaultdict(dict) for name in ORDER}
    for qid, entry in (_read(QUESTIE_L10N).get("Quest") or {}).items():
        for field in ("name", "objectivesText"):
            text = _flat((entry.get(field) or {}).get(LOCALE))
            if text:
                out["questie"][int(qid)][field] = text
    if VMANGOS_SQLITE.exists():
        con = sqlite3.connect(f"file:{VMANGOS_SQLITE}?mode=ro", uri=True)
        con.row_factory = sqlite3.Row
        cols = ", ".join(f"{c}_loc{VMANGOS_LOCALE} AS {f}" for f, c in VMANGOS_COLUMNS.items())
        for row in con.execute(f"SELECT entry, {cols} FROM locales_quest"):
            for field in VMANGOS_COLUMNS:
                text = _flat(row[field])
                if text:
                    out["vmangos"][row["entry"]][field] = text
        con.close()
    for folder, name in (("questcache", "client_cache"), ("wowhead", "wowhead")):
        quests = _read(CORRECTIONS / folder / "forever" / f"{LOCALE}.json").get("quests") or {}
        for qid, texts in quests.items():
            for field in DB_FIELDS.values():
                text = _flat(texts.get(field))
                if text:
                    out[name][int(qid)][field] = text
    return out


def database_origin(qid: int, field: str, fr_entry: dict) -> str:
    """Origin of the database's French text of `field` (our name) for quest `qid`; `fr_entry` is its l10n entry."""
    db_field = DB_FIELDS[field]
    if db_field in (fr_entry.get("azerothcore") or []):
        return "foreverdb:azerothcore"
    text = _flat(fr_entry.get(db_field))
    for name, texts in upstreams().items():
        if text and texts.get(qid, {}).get(db_field) == text:
            return f"foreverdb:{name}"
    return "foreverdb:unknown"


def record_origins(qid: int, record: dict, channels: dict, fr_entry: dict) -> dict:
    """{field: origin} for the texts the record has, from their channel (`source.texts`)."""
    out = {}
    for field in DB_FIELDS:
        if not record.get(field):
            continue
        channel = channels.get(field) or "wowhead"
        out[field] = database_origin(qid, field, fr_entry) if channel == "foreverdb" else channel
    return out


def main(argv: list[str] | None = None) -> int:
    from pipeline.foreverdb.importer import DATA_DIR, _shards
    parser = argparse.ArgumentParser(prog="python -m pipeline.foreverdb.origins", description=__doc__.split("\n")[0])
    parser.add_argument("--dry-run", action="store_true", help="count the origins, write nothing")
    args = parser.parse_args(argv)
    fr = _shards(DATA_DIR / "l10n" / LOCALE / "quest")
    counts: collections.Counter = collections.Counter()
    script_counts: collections.Counter = collections.Counter()
    for path in sorted((storage.REPO_ROOT / "data" / "zones").glob("**/quests.json")):
        data = storage.read_json(path)
        changed = False
        for qid, record in (data.get("quests") or {}).items():
            source = record.setdefault("source", {})
            origins = record_origins(int(qid), record, source.get("texts") or {}, fr.get(str(qid)) or {})
            counts.update(f"{field} {origin}" for field, origin in origins.items())
            if source.get("origins") != origins:
                source["origins"] = origins
                changed = True
        if changed and not args.dry_run:
            storage.write_json(path, data)
        script_counts.update(script_origins(path.parent / "scripts.json", data.get("quests") or {}, args.dry_run))
    for key, n in sorted(counts.items()):
        print(f"{n:6d}  {key}")
    print("scripts:")
    for key, n in sorted(script_counts.items()):
        print(f"{n:6d}  {key}")
    return 0


def script_origins(path: Path, quests: dict, dry_run: bool = False) -> collections.Counter:
    """Sets `source` and `origins` of the quest scripts of a scripts.json from their quest (pipeline/scripts.py,
    text_origins); the text is never touched. A script whose text no longer matches its quest's is left as it is
    (counted `text changed`): its origin is not known."""
    from pipeline import scripts
    data = storage.read_json(path)
    counts: collections.Counter = collections.Counter()
    if not data:
        return counts
    changed = False
    for kind in scripts.KINDS:
        for qid, script in scripts.section(data, kind).items():
            quest = quests.get(qid)
            if not quest or scripts.text_template(quest, kind)["text"] != script.get("text"):
                counts[f"{kind} text changed or quest gone"] += 1
                continue
            source, origins = scripts.text_origins(quest, kind)
            counts[f"{kind} {source}"] += 1
            if (script.get("source"), script.get("origins")) != (source, origins):
                script["source"], script["origins"] = source, origins
                changed = True
    if changed and not dry_run:
        storage.write_json(path, data)
    return counts


if __name__ == "__main__":
    raise SystemExit(main())
