"""Dry run of the books loop (tools/books/run.sh --dry-run): what a run would read and spend, offline (no ElevenLabs
call, nothing written). Reads the oracle's view of data/zones/@books/ and data/books/state.json.

    .venv/bin/python -m tools.books.plan [--budget N] [--round N] [--json]
"""

from __future__ import annotations

import argparse
import json
import sys

from pipeline import books, storage
from pipeline.books import scripts as book_scripts
from tools.books import act, judge, oracle


def plan(budget: int | None = None, size: int = act.ROUND) -> dict:
    voice = judge.voice_id()
    state = judge._read(judge.STATE, {"lines": {}})
    pages = {"todo": [], "ok": 0, "not_found": 0, "no_voice": 0, "chars": 0}
    for key in books.keys(judge.ZONES):
        z = oracle.zone_pages(key, voice or "dry-run", state)  # without her voice, count what she would read
        for k in ("ok", "not_found", "chars"):
            pages[k] += z[k]
        pages["todo"] += z["todo"]
    ratio = book_scripts.ratio()
    within, spent = [], 0
    for unit in pages["todo"]:
        if budget is not None and spent + len(unit["text"]) > budget:
            break
        within.append(unit)
        spent += len(unit["text"])
    return {"voice": voice, "scripts": bool(books.keys(judge.ZONES)), "in_place": pages["ok"], "not_found": pages["not_found"],
            "to_do": len(pages["todo"]), "chars_to_do": pages["chars"],
            "credits_expected": round(pages["chars"] * ratio), "paid_per_kept": ratio,
            "budget": budget, "pages_within_budget": len(within), "chars_within_budget": spent,
            "rounds": -(-len(within) // size) if within else 0, "round_size": size,
            "first": [f"{u['id']} {u['name']} ({len(u['text'])} characters)" for u in within[:5]]}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="tools/books/run.sh --dry-run", description=__doc__.splitlines()[0])
    ap.add_argument("--dry-run", action="store_true", help=argparse.SUPPRESS)
    ap.add_argument("--budget", type=int, help="characters the run may spend")
    ap.add_argument("--round", type=int, default=act.ROUND, help="page readings per attempt")
    ap.add_argument("--json", action="store_true")
    args, _ = ap.parse_known_args(argv)  # the run's other options (--all...) are accepted and ignored
    p = plan(args.budget, args.round)
    if args.json:
        print(json.dumps(p, ensure_ascii=False, indent=1))
        return 0
    if not p["scripts"]:
        print(f"no {books.folder() / 'scripts.json'}: python -m pipeline.books extract && python -m pipeline.books "
              "scripts", file=sys.stderr)
        return 1
    print(f"books loop, dry run ({storage.now()}): Elise's voice {p['voice'] or 'MISSING (tools/elise/voice.py)'}")
    print(f"  page readings in place {p['in_place']}, not found in this run {p['not_found']}, to do {p['to_do']} "
          f"({p['chars_to_do']} characters, about {p['credits_expected']} credits with refused takes, "
          f"x{p['paid_per_kept']})")
    if p["budget"] is not None:
        print(f"  budget {p['budget']} characters: {p['pages_within_budget']} page reading(s), "
              f"{p['chars_within_budget']} characters (first takes only)")
    print(f"  rounds of {p['round_size']}: {p['rounds']}")
    for line in p["first"]:
        print(f"  next: {line}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
