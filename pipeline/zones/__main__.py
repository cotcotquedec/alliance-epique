"""Data commands by quest category (a Wowhead category within its group, D12; "zone" in the code is a category).

    python -m pipeline.zones catalog                 data/zones.json again from Wowhead's menu (cache only)
    python -m pipeline.zones survey [--group G] [--side alliance] [--max-level 30]
                                                     per zone: quests by side and level (cached category pages)
    python -m pipeline.zones order [--side alliance] zones sorted by the median level of their quests of this side
                                                     (zones without any are left out), for tools/all_zones.sh
    python -m pipeline.zones progress [--side alliance] [--all]
    python -m pipeline.zones import [zone...]          zone registries from the Forever Database (main source)
    python -m pipeline.zones sync [--dry-run]        registries in step with the database: moves, retirements
    python -m pipeline.zones report (--all | --group G [--category C]...) [--todo] [--full] [--json]
                                                     completion table per category and what is left
                                                     where each zone stands (text, audio), level order, from the data
    python -m pipeline.zones missing <zone>          quests to open in game to fill the gaps
    python -m pipeline.zones quest <id>              one quest record, as the registry stores it
    python -m pipeline.zones npc <id>                one NPC record, as the registry stores it
    python -m pipeline.zones personas <zone> [--side alliance] [--dry-run] [--npc ID] [--force] [--jobs 4] [--bare]
                                                     persona sheets of the zone's givers (data/voices.json)
    python -m pipeline.zones persona <id>            one persona sheet
    python -m pipeline.zones scripts <zone> [--side alliance] [--dry-run] [--quest ID] [--force]
                                                     quest scripts, without Claude (data/zones/<zone>/scripts.json)
    python -m pipeline.zones script <quest id>       one quest script

<zone> is a key (eastern-kingdoms/elwynn-forest), a slug (elwynn-forest), a Wowhead id (12) or
the French name. Wowhead is no longer crawled (pipeline/wowhead/cache.py): what it gave is read from the cache. `tools/zone.sh` is a shortcut for `python -m pipeline.zones`.
"""

from __future__ import annotations

import argparse
import json
import sys

from pipeline import storage
from pipeline import scripts
from pipeline.personas import generate as personas
from pipeline.wowhead.cache import cached
from pipeline.wowhead.parse import listview
from pipeline.zones import catalog as zones

AUDIO_SECTION = {"detail": "audio", "complete": "complete"}  # section of a zone's audio.json for each kind


def _catalog() -> dict:
    return zones.load() or zones.rebuild()


def cmd_catalog(args) -> None:
    catalog = zones.rebuild()
    groups: dict[str, int] = {}
    for zone in catalog["zones"].values():
        groups[zone["group_name"]] = groups.get(zone["group_name"], 0) + 1
    print(f"{len(catalog['zones'])} categories -> {storage.ZONES_FILE.relative_to(storage.DATA_DIR.parent)}")
    for name, count in groups.items():
        print(f"  {name}: {count}")


SIDES = {"alliance": (1, 3), "horde": (2, 3)}  # Wowhead side: 1 Alliance, 2 Horde, 3 both


def selected(quest: dict, side: str | None, max_level: int | None) -> bool:
    """Quest filter for the paid steps. `quest` is a registry record or a category listing row."""
    raw_side = quest.get("side")
    if isinstance(raw_side, str):
        raw_side = {"alliance": 1, "horde": 2, "both": 3}.get(raw_side)
    if side and raw_side not in (*SIDES[side], None):
        return False
    level = quest.get("level")
    return not (max_level and level and level > max_level)


def cmd_survey(args) -> None:
    catalog = _catalog()
    rows_out = []
    for key, zone in catalog["zones"].items():
        if args.group and zone["group"] not in args.group:
            continue
        page = cached(zone["path"])
        rows = listview(page.text, "quests") if page is not None and page.status == 200 else []
        picked = [r for r in rows if selected(r, args.side, args.max_level)]
        levels = [r["level"] for r in picked if r.get("level")]
        rows_out.append((key, zone["name"], len(rows), len(picked), min(levels, default=0), max(levels, default=0)))
    print(f"{'zone':<42} {'name':<36} {'all':>4} {'kept':>5}  levels")
    for key, name, total, kept, lo, hi in sorted(rows_out, key=lambda r: (-r[3], r[0])):
        print(f"{key:<42} {name[:36]:<36} {total:>4} {kept:>5}  {lo}-{hi}")


def zone_order(listings: dict[str, list[dict]], side: str | None) -> list[tuple[str, float, int, int, int]]:
    """(zone key, median level, quests, lowest, highest) for the zones with quests of this side, by median
    level of those quests, so the low-level zones come first. Never filters quests by level."""
    import statistics
    out = []
    for key, rows in listings.items():
        levels = [r["level"] for r in rows if selected(r, side, None) and (r.get("level") or 0) > 0]
        if levels:
            out.append((key, float(statistics.median(levels)), len(levels), min(levels), max(levels)))
    return sorted(out, key=lambda z: (z[1], z[0]))


def _ordered_zones(side: str | None) -> list[tuple[str, float, int, int, int]]:
    """The zones in level order, from their registries (Forever Database import, D10); a zone without
    registry falls back to its Wowhead category page, from the cache."""
    listings = {}
    for key, zone in _catalog()["zones"].items():
        quests = (storage.read_json(zones.zone_dir(key) / "quests.json") or {}).get("quests")
        if quests:
            listings[key] = list(quests.values())
            continue
        page = cached(zone["path"])
        listings[key] = listview(page.text, "quests") if page is not None and page.status == 200 else []
    return zone_order(listings, side)


def cmd_order(args) -> None:
    for key, median, count, lo, hi in _ordered_zones(args.side):
        print(f"{key}\t{median:g}\t{count}\t{lo}-{hi}")


def zone_progress(key: str, side: str | None, voices: dict, imported: bool = False) -> dict | None:
    """Where a zone stands, read from its data files only (None: not fetched yet; `imported`: the Forever
    Database import went through it and found no quest, so there is nothing to do). Text is done when
    every NPC who speaks the side's quests (giver, or ender of a completion text) has a persona and every
    text that can be voiced has a script (acceptance and completion); audio is done when every script has
    its audio. Counts add up both kinds of script."""
    folder = zones.zone_dir(key)
    quests = (storage.read_json(folder / "quests.json") or {}).get("quests")
    if quests is None and imported:
        quests = {}
    if quests is None:
        return None
    picked = {k: q for k, q in quests.items() if selected(q, side, None)}
    script_file, audio_file = storage.read_json(folder / "scripts.json"), storage.read_json(folder / "audio.json")
    out = {"quests": len(picked), "scripts_done": 0, "scripts_todo": 0, "unvoiceable": 0, "audio_done": 0,
           "audio_todo": 0}
    for kind in scripts.KINDS:
        existing = scripts.section(script_file, kind)
        jobs, skipped = scripts.plan(picked, voices, existing, kind=kind)
        audio = (audio_file or {}).get(AUDIO_SECTION[kind], {})
        voiced = [k for k in existing if k in picked]
        out["scripts_done"] += len(skipped["done"])
        out["scripts_todo"] += len(jobs) + len(skipped["no_persona"])
        # a quest without completion text simply has no turn-in line: not unvoiceable
        out["unvoiceable"] += (len(skipped["no_text"]) if kind == "detail" else 0) + \
            len(skipped[scripts.NO_SPEAKER[kind]])
        out["audio_done"] += sum(1 for k in voiced if audio.get(k))
        out["audio_todo"] += sum(1 for k in voiced if not audio.get(k))
    d_jobs, d_skipped = scripts.plan_dialogues(storage.read_json(folder / "dialogues.json"), voices,
                                               (script_file or {}).get(scripts.DIALOGUES, {}))
    out["scripts_done"] += len(d_skipped["done"])
    out["scripts_todo"] += len(d_jobs) + len(d_skipped["no_persona"])
    out["personas_todo"] = sum(1 for n in _speakers(picked) | dialogue_speakers(key) if str(n) not in voices)
    return out


def dialogue_speakers(key: str) -> set[int]:
    """NPCs whose dialogues live in this category (dialogues.json, pipeline/foreverdb/dialogues.py)."""
    return {int(n) for n in ((storage.read_json(zones.zone_dir(key) / "dialogues.json") or {}).get("npcs") or {})}


def _speakers(quests: dict) -> set[int]:
    """NPCs who say a text of these quests: the givers, and the enders of a completion text."""
    out = set()
    for q in quests.values():
        for kind in scripts.KINDS:
            npc = scripts.speaker(q, kind)
            if npc is not None and scripts.text_template(q, kind)["text"]:
                out.add(npc)
    return out


def cmd_progress(args) -> None:
    voices = personas.load_voices()["npcs"]
    rows, todo_text, todo_audio = [], [], []
    totals = {"quests": 0, "scripts_done": 0, "audio_done": 0, "zones_text": 0, "zones_audio": 0, "zones": 0,
              "personas": len(voices)}
    catalog = _catalog()["zones"]
    for key, median, *_ in _ordered_zones(args.side):
        p = zone_progress(key, args.side, voices, imported=bool(catalog.get(key, {}).get("foreverdb")))
        text_done = p is not None and p["personas_todo"] == 0 and p["scripts_todo"] == 0
        # audio follows the scripts that exist, whether or not the zone's text is complete
        audio_done = p is not None and p["audio_todo"] == 0
        if not text_done:
            todo_text.append(key)
        if p and p["audio_todo"]:
            todo_audio.append(key)
        totals["zones"] += 1
        totals["zones_text"] += text_done
        totals["zones_audio"] += audio_done
        if p:
            for k in ("quests", "scripts_done", "audio_done"):
                totals[k] += p[k]
        if args.all or (not audio_done and len(rows) < args.limit):
            state = ("not fetched" if p is None else
                     f"{p['quests']:>4} quests  personas to do {p['personas_todo']:>3}  scripts {p['scripts_done']:>4} done "
                     f"{p['scripts_todo']:>3} to do  audio {p['audio_done']:>4} done {p['audio_todo']:>4} to do")
            mark = "audio ok" if audio_done else "text ok" if text_done else "text todo"
            rows.append(f"{key:<45} {median:>5g}  {mark:<9}  {state}")
    next_text, next_audio = (todo_text or [None])[0], (todo_audio or [None])[0]
    if args.json:  # the oracle of the loops (tools/text/oracle.py, tools/audio/oracle.py)
        print(json.dumps({**totals, "next_text": next_text, "next_audio": next_audio, "todo_text": todo_text,
                          "todo_audio": todo_audio}))
        return
    print("\n".join(rows))
    print(f"zones with text done: {totals['zones_text']}, with audio done: {totals['zones_audio']}; "
          f"quests {totals['quests']} in fetched zones, scripts {totals['scripts_done']}, audio {totals['audio_done']}")
    print(f"next zone, text pass: {next_text or 'none, all done'}")
    print(f"next zone, audio pass: {next_audio or 'none ready'}")


def cmd_import(args) -> None:
    from pipeline.foreverdb import importer
    keys = [zones.resolve(_catalog(), z) for z in args.zone] if args.zone else None
    try:
        report = importer.import_zones(keys)
    except (importer.MissingDatabase, importer.SyncNeeded) as err:
        raise SystemExit(str(err))
    print(f"imported {report['zones']} zone(s): {report['quests']} quests, {report['npcs']} NPCs "
          f"(Forever Database: {report['stamp']})")
    import_dialogues()


def import_dialogues(db=None) -> dict:
    """The NPCs' dialogues (pipeline/foreverdb/dialogues.py), every category, Alliance side, level order."""
    from pipeline.foreverdb import dialogues, importer
    order = [key for key, *_ in _ordered_zones("alliance", 0)]
    return dialogues.import_dialogues(db or importer.ForeverDB(), _catalog(), order)


def cmd_dialogues(args) -> None:
    from pipeline.foreverdb import importer
    try:
        import_dialogues()
    except importer.MissingDatabase as err:
        raise SystemExit(str(err))


def cmd_books(args) -> None:
    """The books read by Elise (D19): extraction, then Elise's scripts (pipeline/books/)."""
    from pipeline.books import __main__ as books_cli
    for step in ("extract", "scripts"):
        if books_cli.main([step]):
            raise SystemExit(1)


def cmd_sync(args) -> None:
    from pipeline.foreverdb import importer, sync
    try:
        importer.sync_zones(dry_run=args.dry_run)
    except (importer.MissingDatabase, sync.DuplicateQuests) as err:
        raise SystemExit(str(err))


def cmd_report(args) -> None:
    from pipeline.zones import report
    from tools.loop import scope
    try:
        keys = scope.from_args(args)
    except scope.ScopeError as err:
        raise SystemExit(f"report: {err}")
    report.main(keys, args.json, args.todo, args.full)


def _zone_file(ref: str, name: str) -> tuple[str, dict]:
    catalog = _catalog()
    key = zones.resolve(catalog, ref)
    data = storage.read_json(zones.zone_dir(key) / name)
    if data is None:
        raise SystemExit(f"{key} has no registry yet: python -m pipeline.zones import {key}")
    return key, data


def cmd_missing(args) -> None:
    key, data = _zone_file(args.zone, "quests.json")
    rows = [q for q in data["quests"].values() if q["missing"] and not q.get("capture")]
    print(f"{key}: {len(rows)} quests to complete (open them in game to capture their text)")
    for q in rows:
        name = q.get("name") or "?"
        print(f"{q['id']:>6}  {name:<40} missing: {', '.join(q['missing'])}")


def _record(name: str, record_id: int) -> tuple[str, dict]:
    """(category key, record) of a quest or NPC (name: quests | npcs) in the registries."""
    for path in sorted(storage.ZONES_DIR.glob(f"**/{name}.json")):
        record = ((storage.read_json(path) or {}).get(name) or {}).get(str(record_id))
        if record is not None:
            return str(path.parent.relative_to(storage.ZONES_DIR)), record
    raise SystemExit(f"no {name[:-1]} {record_id} in the registries")


def cmd_quest(args) -> None:
    key, record = _record("quests", args.id)
    print(json.dumps({"zone": key, **record}, ensure_ascii=False, indent=1))


def cmd_npc(args) -> None:
    key, record = _record("npcs", args.id)
    print(json.dumps({"zone": key, **record}, ensure_ascii=False, indent=1))


def cmd_personas(args) -> None:
    key, zone_npcs = _zone_file(args.zone, "npcs.json")
    folders = sorted(p.parent for p in storage.ZONES_DIR.glob("**/npcs.json"))
    npcs, quests, npc_zones = personas.zone_registries(folders)  # all zones: an NPC's full dossier
    # the NPCs who speak this side's quests (never a level filter): givers, and enders of a completion text
    zone_quests = storage.read_json(zones.zone_dir(key) / "quests.json")["quests"]
    speakers = _speakers({k: q for k, q in zone_quests.items() if selected(q, args.side, None)})
    speakers |= dialogue_speakers(key)
    only = set(args.npc) if args.npc else speakers
    unknown = sorted(n for n in only if n not in npcs)  # no NPC page fetched yet: rerun the zone fetch
    if unknown:
        print(f"  {len(unknown)} NPC(s) without registry record, no persona possible until fetched: {unknown}")
    only -= set(unknown)
    voices = personas.load_voices()
    jobs = personas.todo(npcs, quests, npc_zones, voices, force=args.force, only=only,
                         dialogues=personas.dialogue_texts(folders))
    print(f"{key}: {len(only)} speaking NPCs, {len(jobs)} persona(s) to generate "
          f"(prompt v{personas.PROMPT_VERSION}, {personas.MODEL}, effort {personas.EFFORT})")
    if args.dry_run:
        for nid, file, digest in jobs:
            print(f"  {nid} {file['npc']['name']}: {len(file['quests_given'])} given, "
                  f"{len(file['quests_ended'])} ended, hash {digest}")
        if args.show:
            print(personas.user_message(personas.dossier(npcs[args.show], quests, npc_zones.get(args.show, []),
                                                         personas.dialogue_texts(folders).get(args.show))))
        return
    report = personas.generate(jobs, voices, workers=args.jobs, bare=args.bare)
    print(f"generated {report['generated']}, failed {len(report['failed'])} {report['failed'] or ''}, "
          f"cost ${report['cost_usd']:.2f} -> {personas.voices_file().relative_to(storage.DATA_DIR.parent)}")
    _stop_on_limit(report, key)
    if report["failed"]:
        sys.exit(1)
    if unknown:
        sys.exit(1)  # the zone's text cannot be complete: its fetch is incomplete


EXIT_LIMIT = 75  # EX_TEMPFAIL: the Claude usage limit is reached, rerun later


def _stop_on_limit(report: dict, key: str) -> None:
    if report.get("stopped"):
        print(f"{key}: Claude usage limit reached, stopped ({report['stopped'][-200:]}). Everything generated so "
              "far is saved; rerun the same command later, it resumes here.")
        sys.exit(EXIT_LIMIT)


def cmd_persona(args) -> None:
    entry = personas.load_voices()["npcs"].get(str(args.id))
    if entry is None:
        raise SystemExit(f"no persona for NPC {args.id}: python -m pipeline.zones personas <zone> --npc {args.id}")
    print(json.dumps(entry, ensure_ascii=False, indent=1))


def cmd_scripts(args) -> None:
    key, quests = _zone_file(args.zone, "quests.json")
    folder = zones.zone_dir(key)
    script_file = storage.read_json(folder / "scripts.json")
    voices = personas.load_voices()["npcs"]
    picked = {k: q for k, q in quests["quests"].items() if selected(q, args.side, None)}  # never a level filter
    if len(picked) < len(quests["quests"]):
        print(f"  side {args.side}: {len(picked)}/{len(quests['quests'])} quests kept")
    jobs = []
    for kind in (args.kind,) if args.kind else scripts.KINDS:
        kind_jobs, skipped = scripts.plan(picked, voices, scripts.section(script_file, kind), force=args.force,
                                          only=set(args.quest) if args.quest else None, kind=kind)
        jobs += kind_jobs
        print(f"{key} {kind}: {len(kind_jobs)} script(s) to write; skipped: "
              + ", ".join(f"{reason} {len(ids)}" for reason, ids in skipped.items()))
        for reason in ("no_text", scripts.NO_SPEAKER[kind], "no_persona"):
            if skipped[reason]:
                print(f"  {reason}: {skipped[reason]}")
    dialogue_jobs = []
    if not args.kind and not args.quest:
        dialogue_jobs, skipped = scripts.plan_dialogues(storage.read_json(folder / "dialogues.json"), voices,
                                                        (script_file or {}).get(scripts.DIALOGUES, {}),
                                                        force=args.force)
        print(f"{key} dialogues: {len(dialogue_jobs)} script(s) to write; skipped: "
              + ", ".join(f"{reason} {len(ids)}" for reason, ids in skipped.items()))
    if args.dry_run or not (jobs or dialogue_jobs):
        return
    report = scripts.generate(folder, jobs)
    report_d = scripts.generate_dialogues(folder, dialogue_jobs)
    print(f"written {report['generated']} + {report_d['generated']} dialogue(s) -> "
          f"{(folder / 'scripts.json').relative_to(storage.DATA_DIR.parent)}")


def cmd_script(args) -> None:
    for path in sorted(storage.ZONES_DIR.glob("**/scripts.json")):
        entry = scripts.section(storage.read_json(path), args.kind).get(str(args.id))
        if entry:
            print(json.dumps(entry, ensure_ascii=False, indent=1))
            return
    raise SystemExit(f"no script for quest {args.id}: python -m pipeline.zones scripts <zone> --quest {args.id}")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="python -m pipeline.zones", description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("catalog", help="data/zones.json again from Wowhead's quest menu (cache only)")
    p.set_defaults(func=cmd_catalog)
    p = sub.add_parser("survey", help="quests per zone by side and level, from the category pages")
    p.add_argument("--group", action="append", help="eastern-kingdoms, kalimdor... (repeatable)")
    p.add_argument("--side", choices=list(SIDES))
    p.add_argument("--max-level", type=int)
    p.set_defaults(func=cmd_survey)
    p = sub.add_parser("order", help="zones by median level of their quests of a side (for tools/all_zones.sh)")
    p.add_argument("--side", choices=list(SIDES))
    p.set_defaults(func=cmd_order)
    p = sub.add_parser("progress", help="where each zone stands (text, audio), in level order, from the data files")
    p.add_argument("--side", choices=list(SIDES))
    p.add_argument("--all", action="store_true", help="every zone, done ones included (default: the next ones)")
    p.add_argument("--limit", type=int, default=15, help="zones shown without --all (default 15)")
    p.add_argument("--json", action="store_true", help="totals and next zones only, as JSON")
    p.set_defaults(func=cmd_progress)
    p = sub.add_parser("import", help="zone registries from the Forever Database (.data/, tools/prepare_db.sh)")
    p.add_argument("zone", nargs="*", help="only these zones (default: every zone of the catalogue)")
    p.set_defaults(func=cmd_import)
    p = sub.add_parser("dialogues", help="the NPCs' dialogues (VMaNGOS, French) into each category's dialogues.json "
                                         "(also done by import; pipeline/foreverdb/dialogues.py)")
    p.set_defaults(func=cmd_dialogues)
    p = sub.add_parser("books", help="the books read by Elise (D19): data/zones/@books/books.json, then its "
                                     "scripts.json (pipeline/books/)")
    p.set_defaults(func=cmd_books)
    p = sub.add_parser("sync", help="registries in step with the Forever Database: moves, retires, restores, then "
                                    "imports (pipeline/foreverdb/sync.py)")
    p.add_argument("--dry-run", action="store_true", help="show what would change, write nothing")
    p.set_defaults(func=cmd_sync)
    p = sub.add_parser("report", help="completion table by category (NPCs, personas, voices, scripts, audio): "
                                      "--all, or --group G [--category C]...")
    from tools.loop import scope
    scope.add_arguments(p)
    p.add_argument("--todo", action="store_true", help="also what is left to do, quest by quest (default: the table)")
    p.add_argument("--full", action="store_true", help="every item of the to-do lists (default: the first 12)")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_report)
    p = sub.add_parser("missing", help="quests whose text must come from a capture")
    p.add_argument("zone")
    p.set_defaults(func=cmd_missing)
    for name, func in (("quest", cmd_quest), ("npc", cmd_npc)):
        p = sub.add_parser(name, help=f"one {name} record by id, from the registries")
        p.add_argument("id", type=int)
        p.set_defaults(func=func)
    p = sub.add_parser("personas", help="persona sheets of the zone's quest givers (Claude, data/voices.json)")
    p.add_argument("zone")
    p.add_argument("--dry-run", action="store_true", help="list what would be generated, no call")
    p.add_argument("--show", type=int, metavar="NPC", help="with --dry-run: print this NPC's dossier")
    p.add_argument("--npc", type=int, action="append", help="only this NPC (repeatable)")
    p.add_argument("--force", action="store_true", help="regenerate the existing personas too (never by default)")
    p.add_argument("--jobs", type=int, default=4, help="parallel calls (default 4)")
    p.add_argument("--bare", action="store_true", help="use ANTHROPIC_API_KEY instead of the Claude Code login")
    p.add_argument("--side", choices=list(SIDES), help="only givers of quests of this side (or both)")
    p.set_defaults(func=cmd_personas)
    p = sub.add_parser("scripts", help="quest scripts of a zone (scripts.json, without Claude)")
    p.add_argument("zone")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--quest", type=int, action="append", help="only this quest (repeatable)")
    p.add_argument("--force", action="store_true", help="write the existing scripts again (never by default)")
    p.add_argument("--side", choices=list(SIDES), help="only quests of this side (or both)")
    p.add_argument("--kind", choices=scripts.KINDS, help="only this kind of script (default: both)")
    p.set_defaults(func=cmd_scripts)
    p = sub.add_parser("script", help="one quest script by quest id")
    p.add_argument("id", type=int)
    p.add_argument("--kind", choices=scripts.KINDS, default="detail")
    p.set_defaults(func=cmd_script)
    p = sub.add_parser("persona", help="one persona sheet by NPC id")
    p.add_argument("id", type=int)
    p.set_defaults(func=cmd_persona)
    args = parser.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
