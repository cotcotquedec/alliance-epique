"""Elise's level-up lines: write the story, show it, write some lines again (pipeline/level_lines/__init__.py).

    python -m pipeline.level_lines generate [--force] [--bare]   # the arc and the 59 lines (only when missing)
    python -m pipeline.level_lines show [level]                  # the arc and the lines
    python -m pipeline.level_lines again 12 [30]... [--bare]     # some lines again, in the same story
"""

from __future__ import annotations

import argparse
import sys

from pipeline.level_lines import SECTION, generate
from pipeline.llm import LLMError, LLMLimit


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m pipeline.level_lines", description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="command", required=True)
    p = sub.add_parser("generate", help="Claude writes the story if missing")
    p.add_argument("--force", action="store_true", help="a new story: every line written again")
    p.add_argument("--bare", action="store_true", help="Claude Code with ANTHROPIC_API_KEY only (pipeline/llm.py)")
    p = sub.add_parser("show", help="the arc and the lines")
    p.add_argument("level", type=int, nargs="?")
    p = sub.add_parser("again", help="some lines again, in the same story")
    p.add_argument("levels", type=int, nargs="+")
    p.add_argument("--bare", action="store_true")
    args = ap.parse_args(argv)

    if args.command == "show":
        data = generate.existing()
        if args.level is None:
            print(f"## L'arc\n\n{data.get('arc', '(pas encore écrit)')}\n")
        for key, line in sorted((data.get(SECTION) or {}).items(), key=lambda kv: int(kv[0])):
            if args.level is None or int(key) == args.level:
                print(f"{int(key):>2}  {line['text']}")
        return 0
    try:
        if args.command == "generate":
            report = generate.generate(args.force, bare=args.bare)
            print(f"written {report['written']} line(s), {report['fixed']} asked again")
        else:
            generate.again(args.levels, bare=args.bare)
    except LLMLimit as err:
        print(f"Claude usage limit: {err}", file=sys.stderr)
        return 75
    except LLMError as err:
        print(f"failed: {err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
