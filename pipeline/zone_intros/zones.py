"""The zones Elise introduces and the dossier Claude writes from.

A zone is a top-level area of the Forever Database (`web/static/data/forever/zones.json`: no parent, not an
instance) on the two continents, with the client's map ID (`uiMapId`, what `C_Map.GetBestMapForUnit` should give
in game: spike S12) and its French name (`l10n/frFR/zones.json`, without the English name some carry in brackets:
"Marche de l'Ouest (Westfall)"). Kept: the zones on the continents' Classic maps, and any top-level area one of our
categories of eastern-kingdoms or kalimdor belongs to (Forever's new zones: Riverglades, Shen Dralas). Left out: the
continents themselves, the areas without a name ("Zone 16577") and those without a French name.

The dossier comes from our registries only (data/zones/**): the quests whose area is the zone or one of its
subzones (titles, objectives, the start of a few descriptions, levels), the NPCs who give them, and the zone's
subzones in French.
"""

from __future__ import annotations

import json
import re
from functools import lru_cache
from pathlib import Path

from pipeline import storage
from pipeline.foreverdb.importer import DATA_DIR as DB_DATA

GROUPS = ("eastern-kingdoms", "kalimdor")
CONTINENT_MAPS = {1414, 1415}  # Kalimdor, Eastern Kingdoms (synthetic areas of the database)
CLASSIC_MAPS = range(1411, 1459)  # the zone maps of the two continents (the database's uiMapId of each zone)
# Kalimdor's zone maps; every other map of CLASSIC_MAPS is in the Eastern Kingdoms. Only used for a zone none of our
# categories belongs to (Deadwind Pass); the others take their category's group.
KALIMDOR_MAPS = {1411, 1412, 1413, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1446, 1447, 1448, 1449, 1450,
                 1451, 1452, 1454, 1456, 1457}
# Forever's own zones with their own map (2026-10-12), outside the Classic maps and in none of our continents'
# categories: area ID -> (French name when the base has none, group). Zephras Isle: "Île de Zéphras" as the client
# names it (GetZoneText, seen in game on 2026-10-12, map 2521).
FOREVER = {16593: ("Île de Zéphras", "eastern-kingdoms"), 616: ("Mont Hyjal", "kalimdor")}
UNNAMED = re.compile(r"^Zone \d+$")
JUNK = re.compile(r"UNUSED|Delete|Supprimez|\bTEST\b|DO NOT", re.IGNORECASE)
BRACKETS = re.compile(r"\s*\([^()]*\)\s*$")

# Who holds each zone, seen from the Alliance (2026-10-11: Elise is the Alliance's narrator, the addon covers the
# Alliance only). Every other zone is contested (shared, disputed, or held by neither faction).
ALLIANCE = {1, 10, 11, 12, 38, 40, 44, 141, 148, 1519, 1537, 1657}  # Dun Morogh ... Stormwind, Ironforge, Darnassus
HORDE = {14, 85, 130, 215, 1497, 1637, 1638}  # Durotar, Tirisfal, Silverpine, Mulgore, Undercity, Orgrimmar, T. Bluff
TERRITORY = {"alliance": "terre de l'Alliance", "horde": "terre de la Horde, ennemie",
             "contested": "zone contestée ou sans maître"}


def territory(area: int) -> str:
    return "alliance" if area in ALLIANCE else "horde" if area in HORDE else "contested"


MAX_PLACES, MAX_PEOPLE, MAX_QUESTS, MAX_EXCERPTS, EXCERPT = 30, 15, 30, 6, 240


def clean_name(name: str | None) -> str | None:
    """The French name without the English one in brackets; None for an empty or junk name."""
    if not name or JUNK.search(name):
        return None
    return BRACKETS.sub("", name).strip() or None


@lru_cache(maxsize=None)
def _database(data_dir: Path = DB_DATA) -> tuple[dict, dict]:
    areas = json.loads((data_dir / "zones.json").read_text(encoding="utf-8"))["zones"]
    french = json.loads((data_dir / "l10n" / "frFR" / "zones.json").read_text(encoding="utf-8"))
    return areas, french


def top(area: int | str, areas: dict) -> str:
    """The top-level area of an area (itself when it has no parent)."""
    key, seen = str(area), set()
    while (areas.get(key) or {}).get("parent") and key not in seen:
        seen.add(key)
        key = str(areas[key]["parent"])
    return key


def zones(data_dir: Path = DB_DATA, catalog: dict | None = None) -> dict[int, dict]:
    """area ID -> {area, map, name, name_en, group, categories}, in map order."""
    areas, french = _database(data_dir)
    catalog = catalog if catalog is not None else (storage.read_json(storage.ZONES_FILE) or {}).get("zones", {})
    belongs: dict[str, list[str]] = {}
    for key, cat in catalog.items():
        if cat.get("group") in GROUPS and cat.get("id") is not None:
            belongs.setdefault(top(cat["id"], areas), []).append(key)
    out = {}
    for key, area in areas.items():
        if area.get("parent") or area.get("instance") or not area.get("uiMapId"):
            continue
        ui_map = int(area["uiMapId"])
        if ui_map in CONTINENT_MAPS or not (ui_map in CLASSIC_MAPS or key in belongs or int(key) in FOREVER):
            continue
        if UNNAMED.match(area.get("name") or "") or JUNK.search(area.get("name") or ""):
            continue
        name = (FOREVER.get(int(key)) or (None,))[0] or clean_name(french.get(key))
        cats = sorted(belongs.get(key, []))
        if not name and cats:
            name = catalog[cats[0]].get("name")
        if not name:
            continue
        group = cats[0].split("/", 1)[0] if cats else FOREVER[int(key)][1] if int(key) in FOREVER \
            else ("kalimdor" if ui_map in KALIMDOR_MAPS else "eastern-kingdoms")
        out[int(key)] = {"area": int(key), "map": ui_map, "name": name, "name_en": area.get("name"), "group": group,
                         "categories": cats}
    return dict(sorted(out.items(), key=lambda kv: (kv[1]["map"], kv[0])))


def _registries(zones_dir: Path) -> tuple[dict, dict]:
    quests, npcs = {}, {}
    for path in sorted(zones_dir.glob("**/quests.json")):
        quests.update((storage.read_json(path) or {}).get("quests", {}))
    for path in sorted(zones_dir.glob("**/npcs.json")):
        npcs.update((storage.read_json(path) or {}).get("npcs", {}))
    return quests, npcs


def wowhead_zone(area: int, read=None) -> dict:
    """The Wowhead zone page of a Forever zone (quest and NPC names, in French; from the cache, fetched until
    2026-10-12): our registries know little of Forever's own zones (Zephras Isle: 7 placeholder quests in the base,
    146 on Wowhead)."""
    from pipeline.wowhead.cache import cached
    from pipeline.wowhead.parse import listview
    page = (read or cached)(f"/forever/fr/zone={area}")
    if page is None or page.status != 200:
        return {}
    def names(lv: str, limit: int) -> list[str]:
        seen = []
        for row in listview(page.text, lv):
            name = row.get("name") or ""
            if name and not name.startswith("[") and name not in seen and name != "Gardien des âmes":
                seen.append(name)
        return seen[:limit]
    return {"quests": names("quests", MAX_QUESTS), "people": names("npcs", MAX_PEOPLE), "places": names("objects", 0)}


def dossier(area: int, data_dir: Path = DB_DATA, zones_dir: Path | None = None, catalog: dict | None = None,
            registries: tuple[dict, dict] | None = None) -> dict:
    """What Claude knows of a zone besides its own knowledge of the lore: names, places, people, quests."""
    zone = zones(data_dir, catalog)[int(area)]
    areas, french = _database(data_dir)
    quests, npcs = registries or _registries(zones_dir or storage.ZONES_DIR)
    places = sorted({n for k, a in areas.items() if str(a.get("parent")) == str(area)
                     and (n := clean_name(french.get(k))) and n != zone["name"]})
    mine = [q for q in quests.values() if q.get("zone_id") is not None and top(q["zone_id"], areas) == str(area)
            and q.get("side") in ("alliance", "both", None)]
    mine.sort(key=lambda q: (q.get("level") or 0, int(q["id"])))
    levels = [q["level"] for q in mine if q.get("level") and q["level"] > 0]
    givers: dict[str, int] = {}
    for q in mine:
        for s in q.get("starters") or []:
            if s.get("type") == "npc":
                givers[str(s["id"])] = givers.get(str(s["id"]), 0) + 1
    people = []
    for nid, _ in sorted(givers.items(), key=lambda kv: -kv[1])[:MAX_PEOPLE]:
        npc = npcs.get(nid) or {}
        if npc.get("name"):
            people.append(npc["name"] + (f", {npc['title']}" if npc.get("title") else ""))
    excerpts = [q["description"][:EXCERPT].rstrip() + ("…" if len(q["description"]) > EXCERPT else "")
                for q in mine if q.get("description")][:MAX_EXCERPTS]
    if int(area) in FOREVER:  # Forever's own zone: what Wowhead shows of it
        extra = wowhead_zone(int(area))
        people = people or extra.get("people", [])
        if extra.get("quests"):
            mine_names = extra["quests"]
        else:
            mine_names = None
    else:
        mine_names = None
    return {**{k: zone[k] for k in ("area", "map", "name", "name_en", "group")},
            "territory": TERRITORY[territory(int(area))],
            "levels": [min(levels), max(levels)] if levels else None,
            "places": places[:MAX_PLACES], "people": people,
            "quests": mine_names or [f"{q['name']} : {q['objectives']}" if q.get("objectives") else q["name"]
                                     for q in mine[:MAX_QUESTS] if q.get("name")],
            "excerpts": [e for e in excerpts if not e.startswith("[")], "quest_count": len(mine)}
