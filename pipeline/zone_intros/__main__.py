"""Elise's zone introductions: the zones, a zone's dossier, writing the texts (pipeline/zone_intros/__init__.py).

    python -m pipeline.zone_intros list                      # the zones, their map ID and whether a text exists
    python -m pipeline.zone_intros dossier 12                # what Claude is given for Elwynn Forest
    python -m pipeline.zone_intros generate [--zone 12]... [--force] [--parallel 4] [--bare]
    python -m pipeline.zone_intros show [12]                 # the texts written
"""

from __future__ import annotations

import argparse
import json
import sys

from pipeline.llm import LLMLimit
from pipeline.zone_intros import generate, zones


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m pipeline.zone_intros", description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="command", required=True)
    sub.add_parser("list", help="the zones Elise introduces")
    p = sub.add_parser("dossier", help="a zone's dossier, as Claude gets it")
    p.add_argument("area", type=int)
    p = sub.add_parser("generate", help="Claude writes the missing introductions")
    p.add_argument("--zone", type=int, action="append", help="an area ID (repeatable): written again")
    p.add_argument("--force", action="store_true", help="write every zone again")
    p.add_argument("--parallel", type=int, default=generate.PARALLEL)
    p.add_argument("--bare", action="store_true", help="Claude Code with ANTHROPIC_API_KEY only (pipeline/llm.py)")
    p = sub.add_parser("show", help="the texts written")
    p.add_argument("area", type=int, nargs="?")
    args = ap.parse_args(argv)

    if args.command == "list":
        done = generate.existing()
        for area, z in zones.zones().items():
            print(f"{area:>6}  map {z['map']}  {z['group']:<17} {z['name']:<28} "
                  f"{'text' if area in done else '-':<5} {', '.join(z['categories'])}")
        return 0
    if args.command == "dossier":
        print(json.dumps(zones.dossier(args.area), ensure_ascii=False, indent=1))
        return 0
    if args.command == "show":
        for area, script in sorted(generate.existing().items()):
            if args.area is None or area == args.area:
                print(f"## {area} {script['name']} (map {script['map']})\n\n{script['text']}\n")
        return 0
    try:
        report = generate.generate(args.zone, args.force, bare=args.bare, parallel=args.parallel)
    except LLMLimit as err:
        print(f"Claude usage limit: {err}", file=sys.stderr)
        return 75
    print(f"written {report['written']}, failed {len(report['failed'])}")
    return 1 if report["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
