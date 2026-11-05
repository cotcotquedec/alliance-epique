"""Parsers for the cached Wowhead Forever pages (markers documented in docs/spikes/S7-wowhead-crawl.md).

Only what the data still reads from the cache (pipeline/wowhead/cache.py): category listings, the quest menu, the
text variables. Every parser is tested against saved pages in tests/pipeline/fixtures/ and returns None/[] rather
than guessing when a marker is missing.
"""

from __future__ import annotations

import json
import re

_DECODER = json.JSONDecoder()

_PLACEHOLDER = re.compile(r"<([^<>]{1,40})>")


def json_after(text: str, marker: str, opener: str = "{"):
    """Decode the JSON value starting at the first `opener` after `marker`."""
    i = text.find(marker)
    if i < 0:
        return None
    start = text.find(opener, i + len(marker))
    if start < 0:
        return None
    value, _ = _DECODER.raw_decode(text, start)
    return value


def listview(page: str, lv_id: str) -> list[dict]:
    """Rows of `new Listview({... id: '<lv_id>', ... data: [...]})`."""
    m = re.search(r"new Listview\(\{[^{]*?id:\s*'" + re.escape(lv_id) + r"'", page)
    if not m:
        return []
    data_at = page.find("data:", m.end())
    if data_at < 0:
        return []
    rows, _ = _DECODER.raw_decode(page, page.find("[", data_at))
    return rows


def placeholders(text: str) -> list[str]:
    """Wowhead text variables such as <nom>, <classe>, <costaud/costaude>."""
    return _PLACEHOLDER.findall(text or "")


def parse_quest_menu(script: str) -> list[dict]:
    """Quest categories of `nether.wowhead.com/forever/fr/menus` (`menu.def.quests`).

    Returns one entry per leaf category (a zone, dungeon, class...): id, name, group, path.
    Entries are `[id, name, url, children?, options?]`; headings have no url.
    """
    tree = json_after(script, 'WH.setPageData("menu.def.quests",', "[") or []
    zones = []
    for group in tree:
        if len(group) < 3 or not group[2]:
            continue  # heading
        children = group[3] if len(group) > 3 and isinstance(group[3], list) else []
        for entry in children or [group]:
            if len(entry) < 3 or not entry[2]:
                continue
            zones.append({"id": int(entry[0]), "name": entry[1].replace("\xa0", " "),
                          "group_name": group[1], "path": entry[2]})
    return zones
