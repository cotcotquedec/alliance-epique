"""NPC dialogues from VMaNGOS (2026-10-10): the text of the dialogue window one opens by talking to an NPC (the chat
bubble), page after page, as the NPC says it. Classic data (Forever may differ: spike S11, the in-game capture is the
truth, D1); French only (D5).

The database's chain: creature_template.gossip_menu_id -> gossip_menu (entry, text_id, condition_id) -> npc_text
(BroadcastTextID0) -> broadcast_text, French in locales_broadcast_text (male_text_loc2 / female_text_loc2: the
NPC's sex). A page's options (gossip_menu_option) of the "chat" kind (option_id 1) lead to sub-pages (action_menu_id):
those pages are read too; the option lines themselves are the player's words and are never read (decided 2026-10-10).
A page or an option may need a quest (conditions: quest taken, rewarded, not taken...): its quest ids are kept, so
that one knows which dialogues belong to a quest ("go and talk to...").

Only NPCs friendly to the Alliance (QuestieDB react "A"). Each NPC's dialogues live in one category,
(an NPC with dialogues only goes to its zone's category only if that category has Alliance quests: not Orgrimmar),
data/zones/<group>/<category>/dialogues.json: the category where the NPC already is (it speaks a quest there), else the
one of its zone in the database; once placed, an NPC stays in its category (its scripts and audio are there). An NPC
who only has dialogues is added to that category's npcs.json (`dialogue_only`), so that it gets a persona (text loop)
and a model voice (voice loop) like the quest NPCs.
"""

from __future__ import annotations

import collections
import json
import sqlite3
from pathlib import Path

from pipeline import storage
from pipeline.foreverdb.importer import VMANGOS_SQLITE, convert_text

SCHEMA = 1
CHAT = 1  # gossip_menu_option.option_id of a plain conversation line
QUEST_CONDITIONS = {8, 9, 14, 22, 23}  # VMaNGOS condition types that name a quest (value1)
GROUPS = {-1, -2, -3}  # AND, OR, NOT of other conditions (value1..value4)


class Gossip:
    """The gossip tables of VMaNGOS, read once."""

    def __init__(self, sqlite: Path = VMANGOS_SQLITE):
        con = sqlite3.connect(f"file:{sqlite}?mode=ro", uri=True)
        try:
            self.root = {e: m for e, m in con.execute(
                "SELECT entry, gossip_menu_id FROM creature_template WHERE gossip_menu_id > 0 ORDER BY patch")}
            self.menus = collections.defaultdict(list)
            for entry, text_id, cond in con.execute("SELECT entry, text_id, condition_id FROM gossip_menu"):
                self.menus[entry].append((text_id, cond))
            self.options = collections.defaultdict(list)
            for menu, oid, kind, action, cond in con.execute(
                    "SELECT menu_id, id, option_id, action_menu_id, condition_id FROM gossip_menu_option "
                    "ORDER BY menu_id, id"):
                self.options[menu].append((oid, kind, action, cond))
            self.npc_text = {i: b for i, b in con.execute("SELECT ID, BroadcastTextID0 FROM npc_text")}
            self.french = {e: (m, f) for e, m, f in con.execute(
                "SELECT entry, male_text_loc2, female_text_loc2 FROM locales_broadcast_text")}
            self.conditions = {r[0]: r[1:] for r in con.execute(
                "SELECT condition_entry, type, value1, value2, value3, value4 FROM conditions")}
        finally:
            con.close()

    def quests(self, cond: int | None, seen: set | None = None) -> set[int]:
        """The quests a condition names, through AND/OR/NOT groups."""
        seen = seen if seen is not None else set()
        if not cond or cond in seen or cond not in self.conditions:
            return set()
        seen.add(cond)
        kind, *values = self.conditions[cond]
        if kind in GROUPS:
            return set().union(*(self.quests(v, seen) for v in values))
        return {values[0]} if kind in QUEST_CONDITIONS and values[0] else set()

    def pages(self, npc: int) -> list[dict]:
        """The NPC's dialogue pages with a French text, first page first, then the sub-pages in click order."""
        root = self.root.get(npc)
        if not root:
            return []
        out, seen, queue = [], set(), collections.deque([(root, set(), True)])
        while queue:
            menu, needs, first = queue.popleft()
            if menu in seen:
                continue
            seen.add(menu)
            for text_id, cond in self.menus.get(menu, []):
                broadcast = self.npc_text.get(text_id)
                male, female = self.french.get(broadcast) or (None, None)
                text, text_f = convert_text(male) or convert_text(female), convert_text(female)
                if not text:
                    continue
                out.append({"id": str(broadcast), "menu": menu, "text_id": text_id, "first": first,
                            "quests": sorted(needs | self.quests(cond)), "text": text,
                            **({"text_female": text_f} if text_f and text_f != text else {})})
            for _, kind, action, cond in self.options.get(menu, []):
                if kind == CHAT and action > 0:
                    queue.append((action, needs | self.quests(cond), False))
        unique, ids = [], set()
        for page in out:  # one page per text: a text shown under several conditions is read once
            if page["id"] not in ids:
                ids.add(page["id"])
                unique.append(page)
        return unique


def homes(zones_dir: Path) -> dict[int, str]:
    """NPC -> the category that already holds its dialogues (sticky)."""
    out = {}
    for path in sorted(zones_dir.glob("**/dialogues.json")):
        key = str(path.parent.relative_to(zones_dir))
        for nid in (json.loads(path.read_text(encoding="utf-8")).get("npcs") or {}):
            out.setdefault(int(nid), key)
    return out


def import_dialogues(db, catalog: dict, order: list[str], gossip: Gossip | None = None,
                     zones_dir: Path | None = None, log=print) -> dict:
    """Writes every category's dialogues.json and adds the dialogue-only NPCs to its npcs.json. `order`: the
    categories in level order (an NPC in several categories goes to the first)."""
    from pipeline.foreverdb.importer import npc_record
    from pipeline.npcs import registry as npc_registry
    from pipeline.zones import catalog as zones
    zones_dir = zones_dir or zones.zone_dir("x").parent
    gossip = gossip or Gossip()
    by_id = {int(z["id"]): key for key, z in catalog["zones"].items()}
    rank = {key: i for i, key in enumerate(order)}
    present: dict[int, str] = {}
    for path in sorted(zones_dir.glob("**/npcs.json"), key=lambda p: rank.get(str(p.parent.relative_to(zones_dir)),
                                                                             len(rank))):
        key = str(path.parent.relative_to(zones_dir))
        for nid in (json.loads(path.read_text(encoding="utf-8")).get("npcs") or {}):
            present.setdefault(int(nid), key)
    sticky = homes(zones_dir)
    alliance = {str(p.parent.relative_to(zones_dir)) for p in zones_dir.glob("**/quests.json")
                if any((q.get("side") or "both") in ("alliance", "both")
                       for q in (json.loads(p.read_text(encoding="utf-8")).get("quests") or {}).values())}
    placed: dict[str, dict[int, dict]] = collections.defaultdict(dict)
    for nid in sorted(gossip.root):
        base = db.npcs.get(str(nid)) or {}
        if "A" not in (base.get("react") or ""):
            continue
        pages = gossip.pages(nid)
        if not pages:
            continue
        zone_id = (base.get("zone") or {}).get("zone")
        key = sticky.get(nid) or present.get(nid)
        if not key:  # an NPC with dialogues only: its zone's category, if Alliance players have quests there
            key = next((by_id[z] for z in db.parents(zone_id) if z in by_id), None)
            if key not in alliance:
                continue
        name = (db.npcs_fr.get(str(nid)) or {}).get("name") or base.get("name")
        placed[key][nid] = {"name": name, "pages": pages}
    report = {"categories": 0, "npcs": 0, "pages": 0, "new_npcs": 0}
    for key in sorted(set(placed) | {k for k in sticky.values()}):
        folder = zones_dir / key
        npcs_here = placed.get(key, {})
        storage.write_json(folder / "dialogues.json", {
            "schema": SCHEMA, "zone": key, "updated_at": storage.now(), "source": {"foreverdb": db.stamp},
            "npcs": storage.by_id(npcs_here)})
        registry = storage.read_json(folder / "npcs.json") or {"schema": npc_registry.SCHEMA, "zone": key,
                                                                "npcs": {}}
        added = 0
        for nid in npcs_here:
            if str(nid) not in registry["npcs"]:
                registry["npcs"][str(nid)] = {**npc_record(db, nid, None, npcs_here[nid]["name"]),
                                              "dialogue_only": True}
                added += 1
        if added:
            registry["npcs"] = storage.by_id({int(k): v for k, v in registry["npcs"].items()})
            registry["summary"] = npc_registry.summarize({int(k): v for k, v in registry["npcs"].items()})
            storage.write_json(folder / "npcs.json", registry)
        if npcs_here:
            report["categories"] += 1
        report["npcs"] += len(npcs_here)
        report["pages"] += sum(len(n["pages"]) for n in npcs_here.values())
        report["new_npcs"] += added
    log(f"dialogues: {report['npcs']} NPCs, {report['pages']} pages in {report['categories']} categories "
        f"({report['new_npcs']} NPCs added for their dialogues)")
    return report
