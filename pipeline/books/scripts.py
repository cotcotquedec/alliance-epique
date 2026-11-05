"""Elise's scripts of the books (D19, 2026-10-21): from the books registry (extract.py), the text she reads for each
page, in data/zones/@books/scripts.json, section "pages", keyed by page ID (a page shared by several books, the same
book on several shelves, is read once).

A book is read as written: no rewriting. Only what is not text for the ear changes:
- the HTML of some pages (<HTML>, <P>, <H1>, <BR/>, <IMG>, as the game's SimpleHTML shows them): a title, a paragraph
  or a line break becomes a paragraph or a line, an image nothing;
- the database's variables as in every text the addon reads (D8, pipeline/narration.py): `$B` a line break (`$B$B`
  a paragraph), `$N` (the player's name) as a form of address left out with its comma, inside a sentence ("atteste
  que $N a tué") "l'aventurier" or "l'aventurière"; `$C`/`$R` alone left out, after a word "camarade"; `$g`
  agreements stay as `<masculine/feminine>` markers, read twice (one audio per player sex);
- a bracketed note of the text ("<texte illisible>") is read without its brackets: it is part of the page.

Only the books of the Alliance scope (side alliance, both or unknown: extract.SIDES_IN_SCOPE) with a French title.
`cost()` counts the characters ElevenLabs will bill (both variants of a gendered page), for every book and for the
scope, with the credits a run is expected to spend (takes refused by the judge are paid too: the ratio of the Elise
loop's tries, data/cache/loops/elise/tries.jsonl).
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from pipeline import narrator, storage
from pipeline.books import REGISTRY, SECTION, SIDES_IN_SCOPE, folder
from pipeline.foreverdb.importer import convert_text
from pipeline.narration import render, template

SCHEMA = 1
VERSION = "books-1"
CREDITS_PER_CHAR = 1.0  # ElevenLabs bills one credit per character with the multilingual models (assumed for eleven_v4)
DEFAULT_RATIO = 1.4  # characters paid per character kept, when no Elise tries are known (Elise: 1.41, 2026-10-21)
ELISE_TRIES = storage.REPO_ROOT / "data" / "cache" / "loops" / "elise" / "tries.jsonl"

_BREAK = re.compile(r"<\s*br\s*/?\s*>", re.IGNORECASE)
_BLOCK_END = re.compile(r"<\s*/\s*(?:p|h[1-6])\s*>", re.IGNORECASE)
_TAG = re.compile(r"<\s*/?\s*(?:html|body|p|h[1-6]|img|a|font)\b[^<>]*>", re.IGNORECASE)
_ENTITIES = {"&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&nbsp;": " "}
_KEEP = re.compile(r"^(?:nom|classe|race|[^<>/]+/[^<>/]+)$")  # narration markup, not a note of the text
_BRACKETS = re.compile(r"<([^<>]+)>")
# the player's name inside a sentence, not as a form of address ("atteste que <nom> a tué"): D8's neutral word
_NAME_IN_SENTENCE = re.compile(r"(?<=[^\W\d_])(\s+)<nom>(?!\s*[,.!?…:;])")
NEUTRAL_NAME = "<l'aventurier/l'aventurière>"
# "... ! $N, qui vous apporte ce manifeste, a réussi": the name is the subject, not a form of address
_NAME_SUBJECT = re.compile(r"(^|[.!?…]\s+)<nom>(?=\s*,\s*qui\b)", re.MULTILINE)


def strip_html(text: str) -> str:
    """SimpleHTML -> plain text: a line break a newline, the end of a paragraph or title a blank line."""
    if not re.search(r"<\s*(?:html|body|p|br|h[1-6])\b", text, re.IGNORECASE):
        return text
    text = _BREAK.sub("\n", text)
    text = _BLOCK_END.sub("\n\n", text)
    text = _TAG.sub("", text)
    for entity, char in _ENTITIES.items():
        text = text.replace(entity, char)
    return text


def unwrap_notes(text: str) -> str:
    """A bracketed note of the page is read without its brackets; the narration markup stays."""
    return _BRACKETS.sub(lambda m: m.group(0) if _KEEP.match(m.group(1).strip()) else m.group(1), text)


def prepare(raw_markup: str | None) -> dict:
    """A page's text in the registry (narration markup, extract.convert_text) -> {text, gendered}."""
    if not raw_markup:
        return {"text": None, "gendered": False}
    # the registry text came through convert_text: HTML first on its own lines, then the narration rules
    text = unwrap_notes(strip_html(raw_markup))
    text = convert_text(text) or ""
    text = _NAME_SUBJECT.sub(lambda m: m.group(1) + "<L'aventurier/L'aventurière>", text)
    text = _NAME_IN_SENTENCE.sub(lambda m: m.group(1) + NEUTRAL_NAME, text)
    tpl = template(text)
    out = tpl["text"] or None
    return {"text": out, "gendered": bool(out and re.search(r"<[^<>/]+/[^<>/]+>", out))}


def variants(script: dict) -> list[tuple[str, str]]:
    """[(sex, text)] of a page script: one, or two for a gendered page."""
    text = script["text"]
    return [("m", render(text, "m")), ("f", render(text, "f"))] if script.get("gendered") else [("m", text)]


def in_scope(book: dict) -> bool:
    return bool(book.get("title")) and book.get("side") in SIDES_IN_SCOPE


def build(registry: dict, previous: dict | None = None) -> dict:
    """The scripts.json document of the books registry; a page whose text did not change keeps its record."""
    old = (previous or {}).get(SECTION) or {}
    pages: dict[int, dict] = {}
    for key, book in sorted((registry.get("books") or {}).items()):
        if not in_scope(book):
            continue
        for page in book["pages"]:
            entry = pages.get(page["page"])
            if entry is None:
                prepared = prepare(page["text"])
                if not prepared["text"]:
                    continue
                entry = {"page": page["page"], "n": page["n"], "title": book["title"], "books": [],
                         "npc_id": narrator.NARRATOR_ID, "npc_name": narrator.NAME, "side": book["side"],
                         "source": "foreverdb", **prepared,
                         "chars": sum(len(t) for _, t in variants(prepared))}
                kept = old.get(str(page["page"]))
                same = kept and kept.get("text") == entry["text"]
                entry["generator"] = kept["generator"] if same else {"version": VERSION, "at": storage.now()}
                pages[page["page"]] = entry
            entry["books"].append(key)
            if book["side"] != entry["side"]:
                entry["side"] = "both" if "unknown" not in (book["side"], entry["side"]) else entry["side"]
    return {"schema": SCHEMA, "npc_id": narrator.NARRATOR_ID, "updated_at": storage.now(),
            "source": {"books": registry.get("updated_at")}, SECTION: storage.by_id(pages),
            "cost": cost(registry)}


def ratio(path: Path = ELISE_TRIES) -> float:
    """Characters paid per character kept in the Elise loop (refused takes are paid too)."""
    if not path.exists():
        return DEFAULT_RATIO
    paid = kept = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        row = json.loads(line)
        paid += row.get("chars", 0)
        kept += row.get("chars", 0) if not row.get("failed") else 0
    return round(paid / kept, 2) if kept else DEFAULT_RATIO


def cost(registry: dict, tries: Path = ELISE_TRIES) -> dict:
    """Characters ElevenLabs bills to read every page once (both variants of a gendered page): every book with a
    French title, and the Alliance scope; with the credits expected for a whole run (takes refused included)."""
    seen: dict[str, dict[int, int]] = {"all": {}, "scope": {}}
    lines = {"all": 0, "scope": 0}
    for book in (registry.get("books") or {}).values():
        if not book.get("title"):
            continue
        for page in book["pages"]:
            prepared = prepare(page["text"])
            if not prepared["text"]:
                continue
            chars = sum(len(t) for _, t in variants(prepared))
            for scope in ("all", "scope") if in_scope(book) else ("all",):
                if page["page"] not in seen[scope]:
                    seen[scope][page["page"]] = chars
                    lines[scope] += 2 if prepared["gendered"] else 1
    r = ratio(tries)
    out = {"credits_per_char": CREDITS_PER_CHAR, "paid_per_kept": r}
    for scope in ("all", "scope"):
        chars = sum(seen[scope].values())
        out[scope] = {"pages": len(seen[scope]), "lines": lines[scope], "chars": chars,
                      "credits_once": round(chars * CREDITS_PER_CHAR), "credits_expected": round(chars * r)}
    return out


def write(registry: dict | None = None, zones_dir: Path | None = None, log=print) -> dict:
    """Writes data/zones/@books/scripts.json from the registry on disk (or the one given)."""
    base = folder(zones_dir)
    registry = registry or storage.read_json(base / REGISTRY)
    if not registry:
        raise SystemExit(f"no {base / REGISTRY}: run `python -m pipeline.books extract` first")
    doc = build(registry, storage.read_json(base / "scripts.json"))
    storage.write_json(base / "scripts.json", doc)
    c = doc["cost"]
    log(f"book scripts: {len(doc[SECTION])} page(s) for Elise; ElevenLabs: {c['scope']['chars']} characters in the "
        f"Alliance scope ({c['scope']['lines']} lines), {c['all']['chars']} for every book; expected "
        f"{c['scope']['credits_expected']} credits with refused takes (x{c['paid_per_kept']})")
    return doc
