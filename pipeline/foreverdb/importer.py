"""Zone registries (data/zones/<zone>/{quests,npcs}.json) from the Forever Database, in the same format as
the Wowhead fetch, so that every next step (personas, scripts, audio, report) is unchanged.

    python -m pipeline.zones import [zone...]     # every zone of the catalogue by default

- Zones: the Wowhead quest categories of data/zones.json. A quest goes to the category whose cached Wowhead
  listing holds it (same split as before); else to the first category up its zone's parent chain in the
  database; else to "uncategorized".
- Quest texts: French only (D5). The database's text variables become the Wowhead markup the narration
  reads: $B line break, $N <nom>, $C <classe>, $R <race>, $Gil:elle; <il/elle>.
- Text priority: in-game capture > Wowhead > this database. A text already in the registry (Wowhead fetch,
  capture) is kept: Wowhead shows the Forever text, VMaNGOS the Classic one, and they differ on some quests
  (checked on Elwynn quest 40, 2026-10-06); the database fills what is missing. Givers and enders: the
  database's, else the previous ones. Quests known only from an earlier source stay; captures are kept.
  `source.texts` names the channel of each text, `source.origins` its upstream (pipeline/foreverdb/origins.py).
- A quest lives in one category only: when the database moves, retires or restores quests, the import refuses and
  the sync (pipeline/foreverdb/sync.py, `python -m pipeline.zones sync`) does it, taking every entry along.
- NPCs: every NPC who speaks a quest of the zone (giver or ender). French name and title from the
  database, display ID from VMaNGOS; the game voice (race, sex, set) known from an earlier Wowhead fetch is
  kept, else unknown (the persona then guesses the race, prompt v3).
"""

from __future__ import annotations

import json
import re
import sqlite3
from pathlib import Path

from pipeline import storage
from pipeline.foreverdb import origins
from pipeline.quests import registry as quest_registry
from pipeline.text import looks_english
from pipeline.wowhead.parse import placeholders

DB_DIR = storage.REPO_ROOT / ".data" / "forever-db"
DATA_DIR = DB_DIR / "web" / "static" / "data" / "forever"
VMANGOS_SQLITE = DB_DIR / "vendor" / "vmangos" / "sqlite-dump" / "mangos.sqlite"
FALLBACK_ZONE = "uncategorized"
SIDES = {"A": "alliance", "H": "horde", "B": "both"}
FIELDS = {"name": "name", "objectives": "objectivesText", "description": "details", "progress": "progress",
          "completion": "completion"}  # our field -> database field


class MissingDatabase(RuntimeError):
    pass


# --- text ---------------------------------------------------------------------------------------

_GENDER = re.compile(r"\$[Gg]\s*([^:;$]+):([^;$]+);")
_VARS = {"N": "<nom>", "C": "<classe>", "R": "<race>"}


def convert_text(text) -> str | None:
    """Database text (string, or list of lines for objectives) -> our markup, or None if empty."""
    if isinstance(text, list):
        text = "\n".join(text)
    if not text or not text.strip():
        return None
    text = text.replace("\u00a0", " ").replace("\u202f", " ")  # French typography spaces
    text = _GENDER.sub(lambda m: f"<{m.group(1).strip()}/{m.group(2).strip()}>", text)
    text = re.sub(r"\$[Bb]", "\n", text)
    text = re.sub(r"\$([NnCcRr])", lambda m: _VARS[m.group(1).upper()], text)
    text = re.sub(r"[ \t]*\n[ \t]*", "\n", text)
    text = re.sub(r"[ \t]{2,}", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip() or None


# --- database -----------------------------------------------------------------------------------

def _shards(folder: Path) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for path in sorted(folder.glob("*.json")):
        out.update(json.loads(path.read_text(encoding="utf-8")))
    return out


class ForeverDB:
    """The built database (web/static/data/forever), French texts included."""

    def __init__(self, data_dir: Path = DATA_DIR, sqlite: Path | None = VMANGOS_SQLITE):
        if not (data_dir / "quest").is_dir():
            raise MissingDatabase(f"no built Forever Database in {data_dir}: run tools/prepare_db.sh")
        self.quests = _shards(data_dir / "quest")
        self.quests_fr = _shards(data_dir / "l10n" / "frFR" / "quest")
        self.npcs = _shards(data_dir / "npc")
        self.npcs_fr = _shards(data_dir / "l10n" / "frFR" / "npc")
        self.zones = json.loads((data_dir / "zones.json").read_text(encoding="utf-8"))["zones"]
        meta = json.loads((data_dir.parent / "meta.json").read_text(encoding="utf-8"))
        # the sources' versions, not the build time: rebuilding the same sources changes nothing
        self.stamp = f"db {_head(data_dir)}; questie {meta.get('questie')}; vmangos {meta.get('vmangos')}"
        self.displays = _display_ids(sqlite) if sqlite and sqlite.exists() else {}

    def parents(self, zone_id: int | None):
        seen = 0
        while zone_id is not None and seen < 12:
            yield zone_id
            zone_id = (self.zones.get(str(zone_id)) or {}).get("parent")
            seen += 1


def _head(data_dir: Path) -> str:
    """Commit of the database repository (it ships its own Wowhead corrections)."""
    import subprocess
    repo = data_dir.parents[3]
    proc = subprocess.run(["git", "-C", str(repo), "rev-parse", "--short", "HEAD"], capture_output=True, text=True)
    return proc.stdout.strip() or "unknown"


def _display_ids(sqlite: Path) -> dict[int, int]:
    with sqlite3.connect(f"file:{sqlite}?mode=ro", uri=True) as con:
        rows = con.execute("SELECT entry, display_id1 FROM creature_template WHERE display_id1 > 0 "
                           "ORDER BY patch").fetchall()
    return {entry: display for entry, display in rows}  # the latest patch wins


# --- zones --------------------------------------------------------------------------------------

def zone_of_quests(db: ForeverDB, catalog: dict, listings: dict[str, list[int]]) -> dict[str, list[int]]:
    """Catalogue zone key -> quest ids: the cached Wowhead listing first, then the database's zone chain."""
    by_id = {int(z["id"]): key for key, z in catalog["zones"].items()}
    owner: dict[int, str] = {}
    for key, ids in listings.items():
        for qid in ids:
            owner.setdefault(qid, key)
    for key, quest in db.quests.items():
        qid = int(key)
        if qid in owner:
            continue
        zone_id = (quest.get("zone") or {}).get("zone")
        owner[qid] = next((by_id[z] for z in db.parents(zone_id) if z in by_id), FALLBACK_ZONE)
    out: dict[str, list[int]] = {key: [] for key in catalog["zones"]}
    for qid, key in owner.items():
        out.setdefault(key, []).append(qid)
    return {key: sorted(ids) for key, ids in out.items()}


def cached_listings(catalog: dict) -> dict[str, list[int]]:
    """Quest ids of each Wowhead category page already in the cache (no network)."""
    from pipeline.wowhead.cache import cached
    from pipeline.wowhead.parse import listview
    out = {}
    for key, zone in catalog["zones"].items():
        page = cached(zone["path"])
        if page is not None and page.status == 200:
            out[key] = [row["id"] for row in listview(page.text, "quests")]
    return out


# --- records ------------------------------------------------------------------------------------

def _speaker(db: ForeverDB, ref: dict) -> dict:
    kind = ref.get("t")
    name = (db.npcs_fr.get(str(ref["id"])) or {}).get("name") if kind == "npc" else None
    return {"type": kind, "id": ref["id"], "name": name or ref.get("name")}


def quest_record(db: ForeverDB, qid: int, zone_id: int, previous: dict | None) -> dict:
    base, fr = db.quests[str(qid)], db.quests_fr.get(str(qid)) or {}
    previous = previous or {}
    texts, not_french, sources = {}, [], {}
    previous_sources = (previous.get("source") or {}).get("texts", {})
    for field, db_field in FIELDS.items():
        kept = previous.get(field) if previous_sources.get(field) != "foreverdb" else None
        if kept:  # Wowhead (the Forever text) or a capture: never replaced by the database's Classic text
            texts[field], sources[field] = kept, previous_sources.get(field) or "wowhead"
            continue
        value = convert_text(fr.get(db_field))
        if value and looks_english(value):
            not_french.append(field)
            value = None
        if value:
            sources[field] = "foreverdb"
        texts[field] = value
    starters = [_speaker(db, s) for s in base.get("startedBy") or []] or previous.get("starters", [])
    enders = [_speaker(db, s) for s in base.get("finishedBy") or []] or previous.get("enders", [])
    rewards = base.get("rewards") or {}
    record = {
        "id": qid,
        **texts,
        "starters": starters,
        "enders": enders,
        "zone_id": zone_id,
        "level": base.get("level"),
        "reqlevel": base.get("reqLevel"),
        "side": SIDES.get(base.get("side")) or previous.get("side"),
        "xp": rewards.get("xp"),
        "money": rewards.get("money"),
        "forever": previous.get("forever") or {"status": None, "patch": None},
        "placeholders": sorted(set(placeholders(texts["description"]) + placeholders(texts["objectives"]))),
        "not_french": not_french,
        "wowhead": previous.get("wowhead"),
        "capture": previous.get("capture"),
        "source": {"foreverdb": db.stamp, "texts": sources,
                   "origins": origins.record_origins(qid, texts, sources, fr)},
    }
    record["missing"] = quest_registry.missing_fields(record)
    record["status"] = "incomplete" if record["missing"] else "complete"
    return record


def npc_record(db: ForeverDB, nid: int, previous: dict | None, name_hint: str | None = None) -> dict:
    """`name_hint`: the name the quest gives its speaker, for an NPC missing from the database's NPC list."""
    base, fr = db.npcs.get(str(nid)) or {}, db.npcs_fr.get(str(nid)) or {}
    previous = previous or {}
    react = base.get("react") or ""
    voice = previous.get("voice") or {"source": None, "kind": "unknown", "reason": "no_game_voice_data"}
    record = {
        "id": nid,
        "name": fr.get("name") or previous.get("name") or base.get("name") or name_hint,
        "title": fr.get("subName") or previous.get("title") or base.get("subName"),
        "type": previous.get("type"),
        "classification": base.get("rank") or previous.get("classification"),
        "react": {"alliance": 1 if "A" in react else None, "horde": 1 if "H" in react else None}
        if react else previous.get("react"),
        "faction": (base.get("faction") or {}).get("name"),
        "zones": [(base.get("zone") or {}).get("name")] if base.get("zone") else previous.get("zones", []),
        "coords": previous.get("coords", {}),
        "levels": [base.get("minLevel"), base.get("maxLevel")] if base else previous.get("levels"),
        "display_id": db.displays.get(nid) or previous.get("display_id"),
        "quests_started": [q["id"] for q in base.get("starts") or []] or previous.get("quests_started", []),
        "quests_ended": [q["id"] for q in base.get("ends") or []] or previous.get("quests_ended", []),
        "forever": previous.get("forever") or {"status": None},
        "voice": voice,
        "model": previous.get("model"),
        "sex": previous.get("sex"),  # {value, source}: from the Wowhead NPC pages (game voice, 3D model), 2026-10-11
        "wowhead": previous.get("wowhead"),
        "wowhead_classic": previous.get("wowhead_classic"),
        "source": {"foreverdb": db.stamp if base else None},
    }
    record["missing"] = [f for f in ("name", "display_id") if not record[f]]
    if voice.get("kind") in ("unknown", "none"):
        record["missing"].append("voice")
    return record


# --- import -------------------------------------------------------------------------------------

def import_zone(db: ForeverDB, catalog: dict, key: str, quest_ids: list[int]) -> dict:
    """Writes the zone's registries; returns its summary. Previous records are merged, never dropped."""
    from pipeline.npcs import registry as npc_registry
    from pipeline.zones import catalog as zones
    zone = catalog["zones"][key]
    folder = zones.zone_dir(key)
    prev_quests = (storage.read_json(folder / "quests.json") or {}).get("quests", {})
    prev_npcs = (storage.read_json(folder / "npcs.json") or {}).get("npcs", {})
    quests = {int(k): q for k, q in prev_quests.items()}  # quests the database lacks stay (Wowhead, capture)
    for qid in quest_ids:
        if str(qid) in db.quests:
            quests[qid] = quest_record(db, qid, int(zone["id"]), prev_quests.get(str(qid)))
    speakers = {s["id"]: s.get("name") for q in quests.values() for s in q.get("starters", []) + q.get("enders", [])
                if s.get("type") == "npc"}
    npcs = {int(k): n for k, n in prev_npcs.items()}
    for nid, name in sorted(speakers.items()):
        npcs[nid] = npc_record(db, nid, prev_npcs.get(str(nid)), name)
    header = {"zone": key, "zone_id": zone["id"], "zone_name": zone["name"], "updated_at": storage.now(),
              "source": {"foreverdb": db.stamp}}
    summary = {"quests": quest_registry.summarize(quests), "npcs": npc_registry.summarize(npcs)}
    if quests or (folder / "quests.json").exists():  # a category emptied by a sync is written empty
        storage.write_json(folder / "quests.json", {"schema": quest_registry.SCHEMA, **header,
                                                    "summary": summary["quests"], "quests": storage.by_id(quests)})
        storage.write_json(folder / "npcs.json", {"schema": npc_registry.SCHEMA, **header,
                                                  "summary": summary["npcs"], "npcs": storage.by_id(npcs)})
        zone.update({"state": "imported", "summary": summary, "imported_at": storage.now()})
    return summary


class SyncNeeded(RuntimeError):
    """The database moves, retires or restores quests: a human reviews and runs the sync (pipeline.foreverdb.sync)."""


def import_zones(keys: list[str] | None = None, db: ForeverDB | None = None, log=print,
                 split: dict[str, list[int]] | None = None) -> dict:
    """Adds and updates the quests of the database in their categories. Refuses (SyncNeeded) when the database
    moves, retires or restores quests: that is the sync's job (`python -m pipeline.zones sync`)."""
    from pipeline.foreverdb import sync
    from pipeline.zones import catalog as zones
    from pipeline.zones.__main__ import _catalog
    db = db or ForeverDB()
    catalog = _catalog()
    if split is None:
        split = zone_of_quests(db, catalog, cached_listings(catalog))
        pending = sync.plan(db, split, keys)
        if pending.structural:
            raise SyncNeeded(f"the Forever Database moves {len(pending.moved)} quest(s), retires {len(pending.retired)}"
                             f" and restores {len(pending.restored)}: review `tools/zone.sh sync --dry-run`, then run "
                             "`tools/zone.sh sync` (no loop running)")
    report = {"zones": 0, "quests": 0, "npcs": 0, "stamp": db.stamp}
    for key in keys or list(catalog["zones"]):
        summary = import_zone(db, catalog, key, split.get(key, []))
        catalog["zones"][key]["foreverdb"] = db.stamp  # imported at this version, quests or not
        if summary["quests"]["quests"]:
            report["zones"] += 1
            report["quests"] += summary["quests"]["quests"]
            report["npcs"] += summary["npcs"]["npcs"]
            q = summary["quests"]
            log(f"  {key}: {q['quests']} quests ({q['complete']} complete), {summary['npcs']['npcs']} NPCs")
    zones.save(catalog)
    return report


def status(db: ForeverDB | None = None) -> dict:
    """Where the registries stand against the built database (the base loop's oracle): zones still to
    import at the current database version, and the counters that must never go down."""
    from pipeline.zones.__main__ import _catalog
    catalog = _catalog()
    try:
        db = db or ForeverDB()
        stamp = db.stamp
    except MissingDatabase:
        stamp = None
    level = {"zones": 0, "quests": 0, "descriptions": 0, "completions": 0}
    todo = []
    for key in catalog["zones"]:
        data = storage.read_json(zones_dir(key) / "quests.json")
        quests = (data or {}).get("quests", {})
        if quests:
            level["zones"] += 1
            level["quests"] += len(quests)
            level["descriptions"] += sum(1 for q in quests.values() if q.get("description"))
            level["completions"] += sum(1 for q in quests.values() if q.get("completion"))
        if stamp is None or (data or {}).get("source", {}).get("foreverdb") != stamp:
            todo.append(key)
    # zones without any quest in the database are imported as nothing: not left to do once it is built
    if stamp is not None:
        split_known = {k for k, z in catalog["zones"].items() if z.get("foreverdb") == stamp}
        todo = [k for k in todo if k not in split_known]
    return {"stamp": stamp, "todo": todo, "level": level}


def zones_dir(key: str) -> Path:
    from pipeline.zones import catalog as zones
    return zones.zone_dir(key)


def sync_zones(dry_run: bool = False, db: ForeverDB | None = None, log=print):
    """The sync (pipeline.foreverdb.sync): its plan, then, unless `dry_run`, the moves, retirements and restores
    and the import of every category. Returns the plan."""
    from pipeline.foreverdb import sync
    from pipeline.zones.__main__ import _catalog
    db = db or ForeverDB()
    catalog = _catalog()
    split = zone_of_quests(db, catalog, cached_listings(catalog))
    p = sync.plan(db, split)
    for line in sync.describe(p):
        log(line)
    if dry_run:
        return p
    sync.apply(p, log)
    report = import_zones(db=db, log=log, split=split)
    log(f"imported {report['zones']} zone(s): {report['quests']} quests")
    if p.retired:
        log("quests were retired: the loops' counters went down, relaunch each loop once with --reset-ratchet")
    return p

