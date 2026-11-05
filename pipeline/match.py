"""Text matching shared with the addon (index contract v9, 2026-10-21): the same normalisation, byte for byte, in
Python (here) and in Lua 5.1 (the addon), so that a text shown in game finds its entry of the index.

`fs_norm(s)` -> tokens:
1. WoW markers: `$B`/`$b` (line break) and `|n` become a space; the colour codes `|cAARRGGBB` and `|r` are dropped.
2. The base text's variables are dropped: `$N $n $C $c $R $r`, and the gender construct `$g<male>:<female>;` (any
   case) entirely. In game the client has already replaced them; the addon drops the player's name, class and race
   words instead (`match_page`, `without`: as token sequences, 2026-10-21, as the addon does).
3. ASCII A-Z only are lowercased (bytes 65-90): UTF-8 letters (É) are left as they are, as Lua's string.lower does.
4. Every ASCII whitespace or punctuation byte is a separator (Lua `%s` and `%p` in the C locale), and so are the
   French typographic characters ’ « » … – — and the non-breaking spaces U+00A0, U+202F; tokens are the non-empty
   runs between separators.

`fs_key(s)`: the tokens joined with no separator (book titles). `fs_fp(s)`: the first 48 bytes of `fs_key(s)`, cut
back to a UTF-8 character boundary (a book page's fingerprint).

The registries keep texts in the narration markup (pipeline/foreverdb/importer.py `convert_text`: `<nom>`,
`<classe>`, `<race>`, `<il/elle>`): `from_markup` turns it back into the database's variables first, which gives
the same tokens as the raw database text.
"""

from __future__ import annotations

import re
import string

FP_BYTES = 48
THRESHOLD = 0.7  # least share of the base tokens found in the shown text (Spoken's threshold)
MAX_WORDS = 40  # a dialogue page's `words` keeps its first 40 tokens (index size, 2026-10-21)

_TYPOGRAPHIC = tuple(c.encode("utf-8") for c in ("’", "«", "»", "…", "–", "—",
                                                 " ", " "))
_LINE = re.compile(rb"\$[Bb]|\|n")
_COLOUR = re.compile(rb"\|c[0-9A-Fa-f]{8}|\|r")
_GENDER = re.compile(rb"\$[Gg][^:;]*:[^;]*;")
_VARIABLE = re.compile(rb"\$[NnCcRr]")
_SEPARATORS = re.compile(rb"[" + re.escape((string.whitespace + string.punctuation).encode("ascii")) + rb"]+")
_LOWER = bytes.maketrans(string.ascii_uppercase.encode("ascii"), string.ascii_lowercase.encode("ascii"))


def fs_norm(text: str | None) -> list[str]:
    """The contract's tokens of a text."""
    if not text:
        return []
    raw = text.encode("utf-8")
    for char in _TYPOGRAPHIC:
        raw = raw.replace(char, b" ")
    raw = _COLOUR.sub(b"", _LINE.sub(b" ", raw))
    raw = _VARIABLE.sub(b"", _GENDER.sub(b"", raw))
    raw = raw.translate(_LOWER)
    return [t.decode("utf-8") for t in _SEPARATORS.split(raw) if t]


def fs_key(text: str | None) -> str:
    return "".join(fs_norm(text))


def fs_fp(text: str | None) -> str:
    return fs_key(text).encode("utf-8")[:FP_BYTES].decode("utf-8", "ignore")


def words(text: str | None, limit: int | None = MAX_WORDS) -> str:
    """The first `limit` tokens joined by single spaces (a dialogue page's `words` in the index)."""
    return " ".join(fs_norm(text)[:limit])


_MARKUP_GENDER = re.compile(r"<([^<>/]+)/([^<>/]+?)(?::c)?>")


def from_markup(text: str | None) -> str | None:
    """Narration markup -> the database's variables: `<nom>` $N, `<classe>` $C, `<race>` $R, `<m/f>` $gm:f;."""
    if text is None:
        return None
    text = text.replace("<nom>", "$N").replace("<classe>", "$C").replace("<race>", "$R")
    return _MARKUP_GENDER.sub(lambda m: f"$g{m.group(1)}:{m.group(2)};", text)


def score(base: list[str], shown: list[str]) -> float:
    """Share of the base tokens found among the shown ones (each base occurrence counts once)."""
    if not base:
        return 0.0
    seen = set(shown)
    return sum(1 for t in base if t in seen) / len(base)


def player_phrases(*names: str | None) -> list[list[str]]:
    """The token sequences of the player's name, class and race, as the addon removes them from a shown text."""
    return [tokens for tokens in (fs_norm(name) for name in names) if tokens]


def without(tokens: list[str], phrases: list[list[str]]) -> list[str]:
    """The tokens minus every occurrence of the phrases, the longest one first at each place ("Elfe de la nuit"
    leaves as a whole, never "de" or "la" alone): the addon's core/dialogues.lua does the same."""
    out, i = [], 0
    while i < len(tokens):
        skip = max((len(p) for p in phrases if tokens[i:i + len(p)] == p), default=0)
        if skip:
            i += skip
        else:
            out.append(tokens[i])
            i += 1
    return out


def match_page(shown: str, pages: list[dict], phrases: list[list[str]] = ()) -> tuple[int | None, float, bool]:
    """The contract's lookup of a shown dialogue text among an NPC's pages ([{words: ...}]): (index of the page, its
    score, exact). Exact `words` equality wins (a page cut at MAX_WORDS tokens is compared with as many first shown
    tokens); else the best score >= THRESHOLD, ties to the first; else None."""
    tokens = without(fs_norm(shown), list(phrases))
    joined, prefix = " ".join(tokens), " ".join(tokens[:MAX_WORDS])
    for i, page in enumerate(pages):
        cut = page["words"].count(" ") + 1 >= MAX_WORDS
        if page["words"] == (prefix if cut else joined):
            return i, 1.0, True
    best, best_score = None, 0.0
    for i, page in enumerate(pages):
        s = score(page["words"].split(), tokens)
        if s > best_score:
            best, best_score = i, s
    return (best, best_score, False) if best_score >= THRESHOLD else (None, best_score, False)
