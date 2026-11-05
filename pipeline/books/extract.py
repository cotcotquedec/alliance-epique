"""Extraction of the books (D19, 2026-10-21): every text one reads in the world, from the Forever Database, into
data/zones/@books/books.json. Classic data (VMaNGOS): Forever may differ, and its own books are not there; an in-game
capture will be the truth (D1).

VMaNGOS keeps a text as a chain of pages: `page_text` (entry, text, next_page), French in `locales_page_text`
(Text_loc2). A chain starts from:
- an object of type TEXT (gameobject_template type 9: a book on a shelf, a plaque, a tombstone; data0 = first page)
  or a GOOBER that shows a page when used (type 10, data7);
- an item with a page (item_template.page_text: a letter, a note, a book in the bags).
Both rows exist once per patch: the latest patch wins. Their French name (locales_gameobject / locales_item,
name_loc2; else the Forever Database's French name) is the book's title, the one the game shows above the text
(ItemTextGetItem), hence the index key (pipeline/match.py fs_key).

French only (D5): a page without a French text (or still in English) is not kept, it goes to `missing`; a book without
a French title cannot be found in game and goes there too. Mail is never read: an item sent by mail (mail_loot_template)
is left out (`excluded`), and so is a deprecated or test row ("Deprecated ...", "TEST ...": never in game).

Where the book is: an object's zone comes from the Forever Database (QuestieDB spawns) when it knows the object, else
from its VMaNGOS spawns, as the zone of the nearest creature spawned on the same map (`zone_source: "nearest_npc"`,
an estimate); an item's from its sources in the Forever Database (where it drops, the quest it starts or belongs to).
Side (the project covers the Alliance): an item restricted to Horde races, a text tied only to Horde quests, or one
in a Horde territory is "horde"; tied only to Alliance quests or races, "alliance"; anywhere else it is "both"
(neutral); with nothing to tell, "unknown" (kept in the scope, flagged).
"""

from __future__ import annotations

import collections
import re
import sqlite3
from pathlib import Path

from pipeline import storage
from pipeline.books import REGISTRY, SIDES_IN_SCOPE, folder
from pipeline.foreverdb.importer import DATA_DIR, VMANGOS_SQLITE, _shards, convert_text
from pipeline.match import fs_fp, fs_key
from pipeline.text import looks_english

SCHEMA = 1
TEXT, GOOBER = 9, 10  # gameobject types: a text object (data0 = page), an object used by hand (data7 = page)
ALLIANCE_RACES = 1 | 4 | 8 | 64  # Human, Dwarf, Night Elf, Gnome (allowable_race bits)
HORDE_RACES = 2 | 16 | 32 | 128  # Orc, Undead, Tauren, Troll
HORDE_ZONES = {14, 215, 85, 1637, 1638, 1497}  # Durotar, Mulgore, Tirisfal, Orgrimmar, Thunder Bluff, Undercity
NEAREST = 250.0  # yards: farther than that from any creature spawn, an object's zone stays unknown
MAX_PAGES = 200  # a chain longer than that is broken data
SIDES = {"A": "alliance", "H": "horde", "B": "both"}
DEPRECATED = re.compile(r"^\s*(?:\[?deprecated|\[?test\b|\[?unused|\[?ph\b|zz)", re.IGNORECASE)  # never in game


class Pages:
    """The VMaNGOS tables of the books, read once (read-only)."""

    def __init__(self, sqlite: Path = VMANGOS_SQLITE):
        con = sqlite3.connect(f"file:{sqlite}?mode=ro", uri=True)
        try:
            self.pages = {e: (t, n) for e, t, n in con.execute("SELECT entry, text, next_page FROM page_text")}
            self.french = {e: t for e, t in con.execute("SELECT entry, Text_loc2 FROM locales_page_text")}
            self.objects = {e: {"name": n, "type": t, "page": d0 if t == TEXT else d7} for e, n, t, d0, d7 in
                            con.execute("SELECT entry, name, type, data0, data7 FROM gameobject_template "
                                        f"WHERE type IN ({TEXT}, {GOOBER}) ORDER BY patch")}
            self.objects = {e: o for e, o in self.objects.items() if o["page"] in self.pages}
            self.items = {e: {"name": n, "page": p, "races": r} for e, n, p, r in con.execute(
                "SELECT entry, name, page_text, allowable_race FROM item_template WHERE page_text > 0 ORDER BY patch")}
            self.items = {e: i for e, i in self.items.items() if i["page"] in self.pages}
            self.object_names = {e: n for e, n in con.execute("SELECT entry, name_loc2 FROM locales_gameobject")}
            self.item_names = {e: n for e, n in con.execute("SELECT entry, name_loc2 FROM locales_item")}
            self.mail_items = {i for (i,) in con.execute("SELECT DISTINCT item FROM mail_loot_template")}
            self.spawns = collections.defaultdict(list)
            for e, m, x, y in con.execute("SELECT id, map, position_x, position_y FROM gameobject"):
                if e in self.objects:
                    self.spawns[e].append((m, x, y))
            self.creatures = [(m, x, y, n) for n, m, x, y in con.execute(  # event spawns left out (fairs, feasts)
                "SELECT id, map, position_x, position_y FROM creature "
                "WHERE guid NOT IN (SELECT guid FROM game_event_creature)")]
            self.maps = {e: n for e, n in con.execute("SELECT entry, map_name FROM map_template ORDER BY patch")}
            self.item_quests = collections.defaultdict(lambda: collections.defaultdict(set))
            self.quest_races, self.quest_zone = {}, {}
            for e, start in con.execute("SELECT entry, start_quest FROM item_template WHERE page_text > 0 "
                                        "AND start_quest > 0"):
                self.item_quests[e]["starts"].add(start)
            columns = {"given_by": ("SrcItemId",), "objective_of": tuple(f"ReqItemId{i}" for i in range(1, 5))
                       + tuple(f"ReqSourceId{i}" for i in range(1, 5)),
                       "reward_of": tuple(f"RewItemId{i}" for i in range(1, 5))
                       + tuple(f"RewChoiceItemId{i}" for i in range(1, 7))}
            names = [c for cs in columns.values() for c in cs]
            for row in con.execute(f"SELECT entry, RequiredRaces, ZoneOrSort, {', '.join(names)} FROM quest_template "
                                   "ORDER BY patch"):
                quest, races, zone, values = row[0], row[1], row[2], dict(zip(names, row[3:]))
                self.quest_races[quest], self.quest_zone[quest] = races, zone if zone and zone > 0 else None
                for key, cs in columns.items():
                    for c in cs:
                        if values[c] in self.items:
                            self.item_quests[values[c]][key].add(quest)
        finally:
            con.close()

    def chain(self, first: int) -> list[int]:
        """The page entries of a book, first page first (a loop or a missing page ends it)."""
        out, page = [], first
        while page and page in self.pages and page not in out and len(out) < MAX_PAGES:
            out.append(page)
            page = self.pages[page][1]
        return out

    def french_text(self, page: int) -> str | None:
        """The page's French text as the database has it ($N, $B... kept), or None (absent, empty or English)."""
        text = self.french.get(page)
        if not text or not text.strip() or looks_english(text):
            return None
        return text


class Places:
    """Zone of a world position: the zone of the nearest creature spawned on the same map (an estimate)."""

    def __init__(self, creatures: list[tuple], npc_zone: dict[int, int], cell: float = NEAREST):
        self.cell = cell
        self.grid = collections.defaultdict(list)
        for m, x, y, npc in creatures:
            zone = npc_zone.get(npc)
            if zone:
                self.grid[(m, int(x // cell), int(y // cell))].append((x, y, zone, npc))

    def zone(self, m: int, x: float, y: float, voters: int = 5) -> int | None:
        """The zone most of the `voters` nearest creatures (one vote per creature kind) say, within NEAREST."""
        cx, cy = int(x // self.cell), int(y // self.cell)
        near = sorted(((px - x) ** 2 + (py - y) ** 2, npc, zone)
                      for i in (-1, 0, 1) for j in (-1, 0, 1)
                      for px, py, zone, npc in self.grid.get((m, cx + i, cy + j), ()))
        votes, seen = collections.Counter(), set()
        for d, npc, zone in near:
            if d > NEAREST ** 2 or len(seen) >= voters:
                break
            if npc not in seen:
                seen.add(npc)
                votes[zone] += 1
        return votes.most_common(1)[0][0] if votes else None


class Database:
    """What the extraction needs from the built Forever Database (JSON): quests' sides and zones, NPCs' zones,
    objects' and items' sources, French names."""

    def __init__(self, data_dir: Path = DATA_DIR):
        import json
        self.quests = _shards(data_dir / "quest")
        self.npcs = _shards(data_dir / "npc")
        self.objects = _shards(data_dir / "object")
        self.objects_fr = _shards(data_dir / "l10n" / "frFR" / "object")
        self.items = _shards(data_dir / "item")
        self.items_fr = _shards(data_dir / "l10n" / "frFR" / "item")
        self.zones = json.loads((data_dir / "zones.json").read_text(encoding="utf-8"))["zones"]
        fr = data_dir / "l10n" / "frFR" / "zones.json"
        self.zones_fr = json.loads(fr.read_text(encoding="utf-8")) if fr.exists() else {}

    def npc_zone(self) -> dict[int, int]:
        """NPC -> its zone, for the NPCs spawned in one zone only (a guard of every city tells nothing)."""
        return {int(k): int(next(iter(n["spawns"]))) for k, n in self.npcs.items() if len(n.get("spawns") or {}) == 1}

    def zone_name(self, zone: int | None) -> str | None:
        if not zone:
            return None
        return self.zones_fr.get(str(zone)) or (self.zones.get(str(zone)) or {}).get("name")

    def quest_side(self, qid: int) -> str | None:
        return SIDES.get((self.quests.get(str(qid)) or {}).get("side"))

    def quest_zone(self, qid: int) -> int | None:
        return ((self.quests.get(str(qid)) or {}).get("zone") or {}).get("zone")


def side_of(sides: set[str]) -> str | None:
    """One side from the sides of the quests or races a text is tied to."""
    sides = {s for s in sides if s}
    if not sides:
        return None
    if sides == {"horde"}:
        return "horde"
    if sides == {"alliance"}:
        return "alliance"
    return "both"


def race_side(mask: int | None) -> str | None:
    if not mask or mask < 0 or (mask & ALLIANCE_RACES and mask & HORDE_RACES):
        return None
    return "horde" if mask & HORDE_RACES else "alliance" if mask & ALLIANCE_RACES else None


def _most(zones: list[int]) -> int | None:
    zones = [z for z in zones if z]
    return collections.Counter(zones).most_common(1)[0][0] if zones else None


def object_place(db: Database, pages: Pages, places: Places, entry: int) -> dict:
    record = db.objects.get(str(entry)) or {}
    spawns = record.get("spawns") or {}
    zone, source = None, None
    if spawns:
        zone, source = _most([int(z) for z, coords in spawns.items() for _ in coords]), "foreverdb"
    elif record.get("zone"):
        zone, source = record["zone"].get("zone"), "foreverdb"
    world = pages.spawns.get(entry, [])
    if zone is None and world:
        zone, source = _most([places.zone(m, x, y) for m, x, y in world]), "nearest_npc"
    maps = sorted({m for m, _, _ in world})
    out = {"zone": zone, "zone_name": db.zone_name(zone), "zone_source": source if zone else None,
           "map": maps[0] if maps else None, "map_name": pages.maps.get(maps[0]) if maps else None,
           "spawns": len(world)}
    if len(world) > 1 and source == "nearest_npc":  # the same book on several shelves
        out["zones"] = sorted({z for z in (places.zone(m, x, y) for m, x, y in world) if z})
    return out


def object_quests(db: Database, entry: int) -> dict:
    record = db.objects.get(str(entry)) or {}
    return {k: sorted({q["id"] for q in record.get(f) or [] if q.get("t") == "quest"})
            for k, f in (("starts", "starts"), ("ends", "ends"), ("objective_of", "objectiveOf"))
            if record.get(f)}


QUEST_LINKS = ("starts", "given_by", "objective_of", "reward_of")  # how an item is tied to a quest


def item_sources(db: Database, pages: Pages, entry: int) -> dict:
    """The item's quests (VMaNGOS quest_template and start_quest, the Forever Database's links) and where it drops."""
    record = db.items.get(str(entry)) or {}
    links = {k: set(v) for k, v in pages.item_quests.get(entry, {}).items()}
    if (record.get("startsQuest") or {}).get("t") == "quest":
        links.setdefault("starts", set()).add(record["startsQuest"]["id"])
    for key, field in (("objective_of", "objectiveOf"), ("reward_of", "rewardFrom")):
        links.setdefault(key, set()).update(q["id"] for q in record.get(field) or [] if q.get("t") == "quest")
    out = {k: sorted(links[k]) for k in QUEST_LINKS if links.get(k)}
    for key, field in (("dropped_by", "droppedBy"), ("in_objects", "objectDrops"), ("in_items", "containedIn"),
                       ("sold_by", "vendors")):
        ids = sorted({s["id"] for s in record.get(field) or []})
        if ids:
            out[key] = ids[:10]
    return out


def item_place(db: Database, pages: Pages, entry: int, sources: dict) -> dict:
    record = db.items.get(str(entry)) or {}
    zones = [int(z) for where in (record.get("spawns") or {}).values()
             for z, coords in ((where or {}).get("spawns") or {}).items() for _ in coords]
    zone, source = _most(zones), "foreverdb"
    if zone is None:
        zone, source = _most([db.quest_zone(q) or pages.quest_zone.get(q) for k in QUEST_LINKS
                              for q in sources.get(k, [])]), "quest"
    return {"zone": zone, "zone_name": db.zone_name(zone), "zone_source": source if zone else None}


def book_pages(pages: Pages, first: int) -> tuple[list[dict], list[dict]]:
    """(French pages, pages missing in French) of the book starting at `first`; n = the page number in game."""
    kept, missing = [], []
    for n, page in enumerate(pages.chain(first), 1):
        raw = pages.french_text(page)
        if raw is None:
            missing.append({"page": page, "n": n, "why": "english" if pages.french.get(page) else "no_french"})
            continue
        kept.append({"page": page, "n": n, "text": convert_text(raw), "fp": fs_fp(raw), "chars": len(raw)})
    return kept, missing


def extract(db: Database | None = None, pages: Pages | None = None, log=print) -> dict:
    """The books registry (not written)."""
    db = db or Database()
    pages = pages or Pages()
    places = Places(pages.creatures, db.npc_zone())
    books, missing, excluded = {}, [], []
    sources = [("object", e, o) for e, o in sorted(pages.objects.items())] + \
              [("item", e, i) for e, i in sorted(pages.items.items())]
    for kind, entry, row in sources:
        key = f"{kind}:{entry}"
        if kind == "item" and entry in pages.mail_items:
            excluded.append({"book": key, "title_en": row["name"], "why": "mail"})
            continue
        if DEPRECATED.match(row["name"] or ""):
            excluded.append({"book": key, "title_en": row["name"], "why": "deprecated"})
            continue
        if kind == "object":
            title = pages.object_names.get(entry) or (db.objects_fr.get(str(entry)) or {}).get("name")
            where, quests = object_place(db, pages, places, entry), object_quests(db, entry)
            sides = {db.quest_side(q) for ids in quests.values() for q in ids}
            side, why = side_of(sides), "quests"
        else:
            title = pages.item_names.get(entry) or (db.items_fr.get(str(entry)) or {}).get("name")
            quests = item_sources(db, pages, entry)
            where = item_place(db, pages, entry, quests)
            side, why = race_side(row["races"]), "races"
            if side is None:
                side, why = side_of({db.quest_side(q) or race_side(pages.quest_races.get(q))
                                     for k in QUEST_LINKS for q in quests.get(k, [])}), "quests"
        if side is None and where.get("zone"):
            side, why = ("horde" if any(z in HORDE_ZONES for z in _parents(db, where["zone"])) else "both"), "zone"
        kept, lacking = book_pages(pages, row["page"])
        record = {"kind": kind, "id": entry, "title": title, "title_en": row["name"],
                  "key": fs_key(title) if title else None, "side": side or "unknown",
                  "side_source": why if side else None, "where": where, "quests": quests,
                  "first_page": row["page"], "pages": kept}
        if lacking:
            record["missing"] = lacking
        books[key] = record
        missing += [{"book": key, **m} for m in lacking]
        if not title:
            missing.append({"book": key, "why": "no_french_title"})
        if not kept:
            missing.append({"book": key, "why": "no_french_page"})
    registry = {"schema": SCHEMA, "updated_at": storage.now(), "source": {"vmangos": str(VMANGOS_SQLITE.name)},
                "summary": summarize(books), "books": books, "missing": missing, "excluded": excluded}
    s = registry["summary"]
    log(f"books: {s['books']} ({s['books_in_scope']} in the Alliance scope, {s['readable']} readable in French); "
        f"pages {s['pages']} unique, {s['pages_french']} in French ({s['coverage']} %), {s['chars_french']} "
        f"characters; {len(missing)} missing, {len(excluded)} excluded (mail, deprecated)")
    return registry


def _parents(db: Database, zone: int | None):
    seen = 0
    while zone is not None and seen < 12:
        yield int(zone)
        zone = (db.zones.get(str(zone)) or {}).get("parent")
        seen += 1


def summarize(books: dict) -> dict:
    unique, french, chars = set(), set(), {}
    by_side = collections.Counter(b["side"] for b in books.values())
    for b in books.values():
        unique.update([p["page"] for p in b["pages"]] + [m["page"] for m in b.get("missing", [])])
        for p in b["pages"]:
            french.add(p["page"])
            chars[p["page"]] = p["chars"]
    readable = [b for b in books.values() if b["title"] and b["pages"]]
    return {"books": len(books), "books_in_scope": sum(1 for b in books.values() if b["side"] in SIDES_IN_SCOPE),
            "readable": len(readable), "by_side": dict(sorted(by_side.items())),
            "by_kind": dict(collections.Counter(b["kind"] for b in books.values())),
            "pages": len(unique), "pages_french": len(french),
            "coverage": round(100 * len(french) / len(unique), 1) if unique else 0.0,
            "chars_french": sum(chars.values())}


def write(registry: dict, zones_dir: Path | None = None) -> Path:
    path = folder(zones_dir) / REGISTRY
    storage.write_json(path, registry)
    return path
