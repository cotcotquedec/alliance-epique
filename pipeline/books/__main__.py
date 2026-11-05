"""Books read by Elise (D19): extraction, text preparation, cost (pipeline/books/__init__.py).

    python -m pipeline.books extract            # Forever Database (.data/) -> data/zones/@books/books.json
    python -m pipeline.books scripts            # books.json -> data/zones/@books/scripts.json (Elise's pages)
    python -m pipeline.books cost [--json]      # ElevenLabs characters and credits, every book and the scope
    python -m pipeline.books show [book]        # a summary, or one book ("object:37", "item:1307", a title)
"""

from __future__ import annotations

import argparse
import json
import sys

from pipeline import storage
from pipeline.books import REGISTRY, SECTION, folder


def _registry() -> dict:
    registry = storage.read_json(folder() / REGISTRY)
    if not registry:
        raise SystemExit(f"no {folder() / REGISTRY}: run `python -m pipeline.books extract` first")
    return registry


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m pipeline.books", description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="command", required=True)
    sub.add_parser("extract", help="the books of the Forever Database into books.json")
    sub.add_parser("scripts", help="Elise's script of each page of the Alliance scope into scripts.json")
    p = sub.add_parser("cost", help="ElevenLabs characters and expected credits")
    p.add_argument("--json", action="store_true")
    p = sub.add_parser("show", help="a summary of the registry, or one book")
    p.add_argument("book", nargs="?")
    args = ap.parse_args(argv)

    if args.command == "extract":
        from pipeline.books import extract
        from pipeline.foreverdb.importer import DATA_DIR, VMANGOS_SQLITE
        if not VMANGOS_SQLITE.exists() or not (DATA_DIR / "quest").is_dir():
            print("no Forever Database in .data/: run tools/prepare_db.sh", file=sys.stderr)
            return 1
        path = extract.write(extract.extract())
        print(f"wrote {path}")
        return 0
    if args.command == "scripts":
        from pipeline.books import scripts
        scripts.write(_registry())
        return 0
    if args.command == "cost":
        from pipeline.books import scripts
        c = scripts.cost(_registry())
        if args.json:
            print(json.dumps(c, ensure_ascii=False, indent=1))
            return 0
        for scope, label in (("all", "every book with a French title"), ("scope", "Alliance scope")):
            s = c[scope]
            print(f"{label}: {s['pages']} pages, {s['lines']} lines, {s['chars']} characters = {s['credits_once']} "
                  f"credits once, about {s['credits_expected']} with the takes the judge refuses "
                  f"(x{c['paid_per_kept']})")
        return 0
    registry = _registry()
    if args.book is None:
        print(json.dumps(registry["summary"], ensure_ascii=False, indent=1))
        missing = {}
        for m in registry["missing"]:
            missing[m["why"]] = missing.get(m["why"], 0) + 1
        excluded = {}
        for e in registry["excluded"]:
            excluded[e["why"]] = excluded.get(e["why"], 0) + 1
        print(f"missing: {missing}; excluded: {excluded}")
        return 0
    books = registry["books"]
    found = books.get(args.book) or next((b for b in books.values() if args.book.lower() in
                                          f"{b['title']} {b['title_en']}".lower()), None)
    if not found:
        print(f"no book {args.book!r}", file=sys.stderr)
        return 1
    scripts_doc = storage.read_json(folder() / "scripts.json") or {}
    print(json.dumps({k: v for k, v in found.items() if k != "pages"}, ensure_ascii=False, indent=1))
    for page in found["pages"]:
        script = (scripts_doc.get(SECTION) or {}).get(str(page["page"]))
        print(f"\n--- page {page['n']} ({page['page']})\n{(script or {}).get('text') or page['text']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
