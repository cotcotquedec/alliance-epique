"""Quest texts from the WoW client's own cache (Cache/WDB/frFR/questcache.wdb) into the zone registries (2026-11-16).

The client keeps the server's answer to every quest it has looked up (quest log, tracker, links), even when the addon
captured nothing: title, start text (`details`) and objectives, in French, raw (markers $B, $N, $G kept, so the m/f
variants stay possible, D8). No completion text: the client does not cache it, captures give it.

The file is read with the Forever Database's reader (.data/forever-db/etl/questcache.py, GPL-3.0, local, never
copied here); nothing encrypted is read (S13). A record the reader could not confirm (objective counts not
recovered) is taken unless its title contradicts the registry's, and a text with a count left unfilled is dropped. Like the capture import (pipeline/capture_quests.py): only the texts a
registry lacks are filled, channel and origin `client_cache`, kept by the base import; a differing text is listed,
never replaced (D13).

    python -m pipeline.captures cache "<WoW>/_forever_/Cache/WDB/frFR/questcache.wdb" [--zones DIR] [--dry-run]
"""

from __future__ import annotations

import collections
import importlib.util
import re
from pathlib import Path

from pipeline import capture_quests, storage
from pipeline.foreverdb.importer import convert_text

READER = storage.REPO_ROOT / ".data" / "forever-db" / "etl" / "questcache.py"
FIELDS = {"name": "name", "description": "details", "objectives": "objectivesText"}  # ours -> the reader's


def _reader(path: Path | None = None):
    path = path or READER
    if not path.exists():
        raise FileNotFoundError(f"{path} missing: tools/prepare_db.sh builds the Forever Database")
    spec = importlib.util.spec_from_file_location("fs_questcache", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


UNFILLED = re.compile(r"\$\d+o[a-z]")  # an objective count the reader could not put back


def read(wdb: Path, reader=None) -> tuple[str, int, dict[int, dict]]:
    """-> (locale, client build, {quest id: {our field: text in our markup, "confirmed": bool}}).

    "confirmed": the reader found the objective records ending at the strings (their counts are sure); an
    unconfirmed record has the same strings, its counts may be missing (`$1oa` left, dropped here)."""
    locale, build, quests = (reader or _reader()).quest_texts(str(wdb))
    out = {}
    for qid, entry in quests.items():
        texts = {ours: convert_text(entry.get(theirs)) for ours, theirs in FIELDS.items()}
        texts = {f: (None if v and UNFILLED.search(v) else v) for f, v in texts.items()}
        out[qid] = {**texts, "confirmed": bool(entry.get("_confirmed", True))}
    return locale, build, out


def _title_conflicts(registry: str | None, cache: str | None) -> bool:
    """Both titles known and not the same words (the record is keyed by quest ID: a missing title is no doubt)."""
    return bool(registry and cache) and capture_quests.similarity(registry, cache) < 1.0


def import_cache(texts: dict[int, dict], build: int, zones_dir: Path | None = None, dry_run: bool = False) -> dict:
    zones_dir = zones_dir or storage.ZONES_DIR
    report: dict = {"quests": len(texts), "build": build, "matched": 0, "unknown": [], "skipped": [], "filled": [], "differs": [],
                    "zones": collections.Counter()}
    seen: set[int] = set()
    for path in sorted(zones_dir.glob("**/quests.json")):
        data = storage.read_json(path) or {}
        key = str(path.parent.relative_to(zones_dir))
        changed = False
        for qid_str, record in (data.get("quests") or {}).items():
            qid = int(qid_str)
            if qid not in texts:
                continue
            seen.add(qid)
            report["matched"] += 1
            entry = dict(texts[qid])
            if not entry.pop("confirmed", True) and _title_conflicts(record.get("name"), entry.get("name")):
                report["skipped"].append({"quest": qid, "zone": key, "title": record.get("name"),
                                          "cache_title": entry.get("name")})
                continue
            result: dict = {"filled": [], "differs": []}
            capture_quests.fill(record, entry, "client_cache", result)
            row = {"quest": qid, "kind": "detail", "zone": key, "title": record.get("name")}
            for field, score in result["differs"]:
                report["differs"].append({**row, "field": field, "score": score})
            if result["filled"]:
                record["source"]["client_cache"] = build
                capture_quests.refresh(record)
                report["filled"].append({**row, "fields": result["filled"]})
                report["zones"][key] += 1
                changed = True
        if changed and not dry_run:
            storage.write_json(path, data)
    report["unknown"] = sorted(qid for qid in texts if qid not in seen)
    report["zones"] = dict(report["zones"])
    return report


def summary(report: dict) -> list[str]:
    fields = collections.Counter(f for r in report["filled"] for f in r["fields"])
    lines = [f"{report['quests']} quests in the client cache (build {report['build']}), {report['matched']} in the "
             f"registries, {len(report['unknown'])} no registry holds",
             f"filled: {len(report['filled'])} quests ({', '.join(f'{f} {n}' for f, n in sorted(fields.items()))})"]
    lines += [f"  {zone}: {n}" for zone, n in sorted(report["zones"].items(), key=lambda kv: -kv[1])]
    lines.append(f"differs from the registry (kept, human decision): {len(report['differs'])}")
    lines += [f"  {r['quest']} {r['field']} {r['score']:.2f} {r['title']} ({r['zone']})" for r in report["differs"]]
    if report["skipped"]:
        lines.append(f"unconfirmed records whose title contradicts the registry's (skipped): {len(report['skipped'])}")
        lines += [f"  {r['quest']} {r['title']!r} != {r['cache_title']!r} ({r['zone']})" for r in report["skipped"]]
    if report["unknown"]:
        lines.append(f"quests no registry holds: {report['unknown']}")
    return lines
