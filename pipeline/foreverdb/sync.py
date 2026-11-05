"""Synchronisation of the zone registries with the Forever Database (2026-10-08): the database says where each
quest lives, the registries follow it. A quest lives in one category only, and its identity is its ID, never its
category: a quest that changes category takes everything along (its record, its scripts, its validated audio, the
state of its readings), so that nothing is generated again because of a move.

    python -m pipeline.zones sync --dry-run     what would change, nothing written
    python -m pipeline.zones sync               moves, retires and restores, then imports every category

For each quest:
- in the database and already in the registries: updated in place, or **moved** if the database puts it in
  another category;
- in the database, not in the registries but in the archive: **restored** with all it had;
- in the database only: new (the import adds it);
- in the registries, no longer in the database: **retired** to the archive (data/archive/quests.json), audio files
  left on disk. Never retired: a quest captured in game (the capture proves it exists) or one that never came from
  the database (Wowhead fetch); they are only listed.

A text that changed in the database is listed (only the database's own texts can change, a Wowhead or captured
text is kept, importer.quest_record): redoing its script or audio is a human decision. Retiring lowers the loops'
counters: their ratchets stop them, and a human relaunches them with --reset-ratchet.

`tools/zone.sh import` (the base loop) only adds and updates: it refuses to run while a move, a retirement or a
restore is pending. No loop may run during a sync (they read and write the same files).
"""

from __future__ import annotations

import copy
from dataclasses import dataclass, field
from pathlib import Path

from pipeline import storage

SIDE_FILES = ("scripts.json", "audio.json", "readings.json")  # per-category files keyed by quest
TEXTS = ("description", "objectives", "completion")  # the texts read aloud (D6)


class DuplicateQuests(RuntimeError):
    """A quest in two categories: the registries are inconsistent, nothing is written."""


@dataclass
class Plan:
    stamp: str
    moved: list[tuple[int, str, str]] = field(default_factory=list)  # (quest, from, to)
    restored: list[tuple[int, str]] = field(default_factory=list)  # (quest, to)
    retired: list[tuple[int, str]] = field(default_factory=list)  # (quest, from)
    kept: list[tuple[int, str, str]] = field(default_factory=list)  # (quest, category, "capture" | "other source")
    new: list[tuple[int, str]] = field(default_factory=list)  # (quest, to)
    changed: list[tuple[int, str, list[str], bool]] = field(default_factory=list)  # (quest, category, texts, audio)

    @property
    def structural(self) -> bool:
        """Whether the plan moves, retires or restores quests (the import alone does not)."""
        return bool(self.moved or self.retired or self.restored)


def archive_file() -> Path:
    return storage.ZONES_DIR.parent / "archive" / "quests.json"


def load_corpus(zones_dir: Path | None = None) -> dict[int, tuple[str, dict]]:
    """Quest ID -> (its category, its record), over every registry. Raises DuplicateQuests if a quest is in two."""
    zones_dir = zones_dir or storage.ZONES_DIR
    out: dict[int, tuple[str, dict]] = {}
    dups: dict[int, list[str]] = {}
    for path in sorted(zones_dir.glob("**/quests.json")):
        key = str(path.parent.relative_to(zones_dir))
        for qid, record in ((storage.read_json(path) or {}).get("quests") or {}).items():
            qid = int(qid)
            if qid in out:
                dups.setdefault(qid, [out[qid][0]]).append(key)
            out[qid] = (key, record)
    if dups:
        listed = "; ".join(f"{q}: {', '.join(keys)}" for q, keys in sorted(dups.items())[:10])
        raise DuplicateQuests(f"{len(dups)} quest(s) in several categories ({listed}): fix the registries first")
    return out


def _voiced(key: str, cache: dict[str, set[str]]) -> set[str]:
    """The quests of a category with audio (audio.json), cached."""
    if key not in cache:
        audio = storage.read_json(storage.ZONES_DIR / key / "audio.json") or {}
        cache[key] = {q for section in ("audio", "complete") for q in (audio.get(section) or {})}
    return cache[key]


def plan(db, split: dict[str, list[int]], keys: list[str] | None = None) -> Plan:
    """What a sync would do. `split`: category -> quest IDs (importer.zone_of_quests); `keys`: only these target
    categories (nothing is retired then: retiring needs the whole picture)."""
    from pipeline.foreverdb.importer import quest_record
    corpus = load_corpus()
    archived = (storage.read_json(archive_file()) or {}).get("quests", {})
    voiced: dict[str, set[str]] = {}
    out = Plan(stamp=db.stamp)
    target = {qid: key for key, ids in split.items() for qid in ids if str(qid) in db.quests}
    for qid, key in sorted(target.items()):
        if keys is not None and key not in keys:
            continue
        if qid in corpus:
            home, previous = corpus[qid]
            has_audio = str(qid) in _voiced(home, voiced)
            if home != key:
                out.moved.append((qid, home, key))
        elif str(qid) in archived:
            previous, has_audio = archived[str(qid)]["quests.json"], bool(archived[str(qid)].get("audio.json"))
            out.restored.append((qid, key))
        else:
            out.new.append((qid, key))
            continue
        record = quest_record(db, qid, 0, previous)
        texts = [t for t in TEXTS if (previous.get(t) or None) != (record.get(t) or None)]
        if texts:
            out.changed.append((qid, key, texts, has_audio))
    if keys is None:
        for qid, (key, record) in sorted(corpus.items()):
            if str(qid) in db.quests:
                continue
            if record.get("capture"):
                out.kept.append((qid, key, "capture"))
            elif not (record.get("source") or {}).get("foreverdb"):
                out.kept.append((qid, key, "other source"))
            else:
                out.retired.append((qid, key))
    return out


# --- moving a quest's entries -------------------------------------------------------------------

class Files:
    """The per-category files a sync touches, loaded once and written at the end."""

    def __init__(self):
        self.data: dict[Path, dict | None] = {}

    def get(self, key: str, name: str) -> dict | None:
        path = storage.ZONES_DIR / key / name
        if path not in self.data:
            self.data[path] = storage.read_json(path)
        return self.data[path]

    def ensure(self, key: str, name: str, like: dict | None) -> dict:
        """The file's data, created empty (with the schema of `like`) if missing."""
        data = self.get(key, name)
        if data is None:
            data = {"schema": like.get("schema")} if like and "schema" in like else {}
            self.data[storage.ZONES_DIR / key / name] = data
        return data

    def write(self) -> None:
        for path, data in self.data.items():
            if data is not None:
                storage.write_json(path, data)


def take(files: Files, key: str, qid: int) -> dict:
    """Removes a quest's entries from a category; returns them, by file name (the NPC records are copied: an NPC
    may speak other quests of that category)."""
    q = str(qid)
    bundle: dict = {}
    quests = files.get(key, "quests.json") or {}
    record = (quests.get("quests") or {}).pop(q, None)
    bundle["quests.json"] = record
    npcs = (files.get(key, "npcs.json") or {}).get("npcs") or {}
    speakers = {str(s["id"]) for s in (record or {}).get("starters", []) + (record or {}).get("enders", [])
                if s.get("type") == "npc"}
    bundle["npcs.json"] = {n: copy.deepcopy(npcs[n]) for n in sorted(speakers) if n in npcs}
    for name in SIDE_FILES:
        data = files.get(key, name)
        if not data:
            continue
        entries: dict = {"schema": data.get("schema")}
        for section, value in data.items():
            if section == "readings":  # unit IDs (<quest>_<kind>[_f]) -> entries with their quest
                moved = {u: e for u, e in value.items() if e.get("quest") == qid}
                for u in moved:
                    del value[u]
                if moved:
                    entries[section] = moved
            elif section == "history":  # archived readings (tools/voices/redo.py)
                moved = [e for e in value if e.get("quest") == qid]
                if moved:
                    data[section] = [e for e in value if e.get("quest") != qid]
                    entries[section] = moved
            elif section == "failed":  # scripts that failed, by kind
                moved = {kind: {q: value[kind].pop(q)} for kind in value if q in value[kind]}
                if moved:
                    entries[section] = moved
            elif isinstance(value, dict) and q in value:  # scripts, complete, audio: keyed by quest
                entries[section] = {q: value.pop(q)}
        if len(entries) > 1:
            bundle[name] = entries
    return bundle


def put(files: Files, key: str, qid: int, bundle: dict) -> None:
    """Adds a quest's entries (from `take`) to a category."""
    q = str(qid)
    quests = files.ensure(key, "quests.json", None)
    quests.setdefault("quests", {})[q] = bundle["quests.json"]
    quests["quests"] = storage.by_id(quests["quests"])
    if bundle.get("npcs.json"):
        npcs = files.ensure(key, "npcs.json", None).setdefault("npcs", {})
        for n, record in bundle["npcs.json"].items():
            npcs.setdefault(n, record)  # a record already there is the category's own, as recent
        files.get(key, "npcs.json")["npcs"] = storage.by_id(npcs)
    for name in SIDE_FILES:
        entries = bundle.get(name)
        if not entries:
            continue
        data = files.ensure(key, name, entries)
        for section, value in entries.items():
            if section == "schema":
                continue
            if section == "history":
                data.setdefault(section, []).extend(value)
            elif section == "failed":
                for kind, items in value.items():
                    data.setdefault(section, {}).setdefault(kind, {}).update(items)
            elif section == "readings":
                data.setdefault(section, {}).update(value)
            else:
                data.setdefault(section, {}).update(value)
                data[section] = storage.by_id(data[section])


def apply(p: Plan, log=print) -> None:
    """Moves, restores and retires (the import then updates every record); checks no quest ends in two places."""
    files = Files()
    archive = storage.read_json(archive_file()) or {"schema": 1, "quests": {}}
    for qid, src, dst in p.moved:
        put(files, dst, qid, take(files, src, qid))
    for qid, dst in p.restored:
        entry = archive["quests"][str(qid)]
        put(files, dst, qid, {k: v for k, v in entry.items() if k.endswith(".json")})
    for qid, src in p.retired:
        archive["quests"][str(qid)] = {"category": src, "archived_at": storage.now(), "stamp": p.stamp,
                                       **take(files, src, qid)}
    seen: dict[int, Path] = {}
    for path, data in files.data.items():
        if path.name == "quests.json":
            for qid in (data or {}).get("quests", {}):
                if int(qid) in seen:
                    raise DuplicateQuests(f"quest {qid} would be in {seen[int(qid)].parent} and {path.parent}")
                seen[int(qid)] = path
    # an interruption may leave a quest in two places (the next plan refuses and says which), never in none:
    # the archive gets the retired quests first, the registries next, the restored ones leave the archive last
    if p.retired:
        archive["quests"] = storage.by_id(archive["quests"])
        storage.write_json(archive_file(), archive)
    files.write()
    if p.restored:
        for qid, _ in p.restored:
            del archive["quests"][str(qid)]
        storage.write_json(archive_file(), archive)
    load_corpus()  # the whole corpus, once written: still one category per quest
    log(f"moved {len(p.moved)}, restored {len(p.restored)}, retired {len(p.retired)}")


def describe(p: Plan, limit: int = 20) -> list[str]:
    """The plan, for a human."""
    def some(items, fmt):
        shown = [fmt(i) for i in items[:limit]]
        return shown + ([f"    … (+{len(items) - limit})"] if len(items) > limit else [])
    lines = [f"sync with the Forever Database ({p.stamp}):"]
    lines.append(f"  moved: {len(p.moved)}")
    lines += some(p.moved, lambda m: f"    {m[0]}: {m[1]} -> {m[2]}")
    lines.append(f"  restored from the archive: {len(p.restored)}")
    lines += some(p.restored, lambda r: f"    {r[0]} -> {r[1]}")
    lines.append(f"  retired to the archive: {len(p.retired)}")
    lines += some(p.retired, lambda r: f"    {r[0]} (from {r[1]})")
    captured = sum(1 for k in p.kept if k[2] == "capture")
    lines.append(f"  not in the database, kept: {len(p.kept)} (captured in game {captured}, "
                 f"other source {len(p.kept) - captured})")
    lines.append(f"  new: {len(p.new)}")
    voiced = [c for c in p.changed if c[3]]
    lines.append(f"  text changed in the database: {len(p.changed)}, {len(voiced)} with audio (to decide)")
    lines += some(voiced, lambda c: f"    {c[0]} ({c[1]}): {', '.join(c[2])}")
    return lines
