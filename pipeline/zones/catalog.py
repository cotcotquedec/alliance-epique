"""Catalogue of Wowhead Forever quest categories (zones, dungeons, classes...): data/zones.json.

Wowhead's categorisation is the source of truth (decided 2026-10-05; its menu read from the cache since 2026-11-01): a zone is a leaf of the
`menu.def.quests` tree served by nether.wowhead.com, keyed by its URL path, for instance
`eastern-kingdoms/elwynn-forest` (Northshire is part of it).
"""

from __future__ import annotations

from pathlib import Path

from pipeline import storage
from pipeline.wowhead.parse import parse_quest_menu

SCHEMA = 1
MENU_PATH = "/forever/fr/menus"  # on host "nether"


def zone_key(path: str) -> str:
    return path.split("/quests/", 1)[1].strip("/")


def build_catalog(entries: list[dict], previous: dict | None = None) -> dict:
    """Catalogue from the menu entries, keeping what earlier fetches recorded per zone."""
    old = (previous or {}).get("zones", {})
    zones = {}
    for entry in entries:
        key = zone_key(entry["path"])
        zone = {
            "id": entry["id"],
            "name": entry["name"],
            "group": key.split("/")[0],
            "group_name": entry["group_name"],
            "path": entry["path"],
            "state": "todo",  # todo | partial | fetched
            "summary": None,
        }
        for kept in ("name", "state", "summary", "fetched_at"):
            if kept in old.get(key, {}):
                zone[kept] = old[key][kept]
        zones[key] = zone
    return {"schema": SCHEMA, "source": "nether.wowhead.com" + MENU_PATH + " (menu.def.quests)",
            "updated_at": storage.now(), "zones": zones}


def rebuild() -> dict:
    """data/zones.json again from the menu fetched before (cache only: Wowhead is no longer crawled)."""
    from pipeline.wowhead.cache import cached
    page = cached(MENU_PATH, host="nether")
    if page is None or page.status != 200:
        raise SystemExit("menu: not in the cache (data/cache/wowhead/nether_forever_fr_menus.*)")
    entries = parse_quest_menu(page.text)
    if not entries:
        raise SystemExit("menu: no quest category found, the markup may have changed")
    catalog = build_catalog(entries, load())
    save(catalog)
    return catalog


def load() -> dict | None:
    return storage.read_json(storage.ZONES_FILE)


def save(catalog: dict) -> None:
    catalog["updated_at"] = storage.now()
    storage.write_json(storage.ZONES_FILE, catalog)


def resolve(catalog: dict, ref: str) -> str:
    """Zone key from a key, a slug, a numeric id or a French name."""
    zones = catalog["zones"]
    if ref in zones:
        return ref
    candidates = [k for k, z in zones.items()
                  if k.split("/")[-1] == ref or str(z["id"]) == ref
                  or z["name"].casefold() == ref.casefold()]
    if len(candidates) == 1:
        return candidates[0]
    if candidates:
        raise SystemExit(f"{ref!r} is ambiguous: {', '.join(sorted(candidates))}")
    raise SystemExit(f"unknown zone {ref!r} (see: list)")


def zone_dir(key: str) -> Path:
    return storage.ZONES_DIR / key
