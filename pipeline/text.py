"""Language heuristics shared by the spikes and the registries (function-word counts)."""

from __future__ import annotations

import re

_FR = {"le", "la", "les", "de", "des", "du", "et", "vous", "je", "un", "une", "est", "pour",
       "que", "qui", "dans", "pas", "nous", "votre", "mon", "ce", "sur", "il", "à"}
# No "on": it is also a French pronoun ("On recherche : Lardeur").
_EN = {"the", "and", "you", "to", "of", "is", "for", "that", "in", "it", "we", "not", "your",
       "my", "this", "he", "with", "are", "be"}


def _counts(text: str) -> tuple[int, int]:
    words = re.findall(r"[a-zàâçéèêëîïôûùüÿœ']+", text.lower())
    return sum(w in _FR for w in words), sum(w in _EN for w in words)


def looks_french(text: str | None) -> bool:
    if not text:
        return False
    fr, en = _counts(text)
    return fr > en


def looks_english(text: str | None) -> bool:
    """True only on positive evidence (two English function words or more, and more than French
    ones): short French texts such as titles and objectives stay French."""
    if not text:
        return False
    fr, en = _counts(text)
    return en >= 2 and en > fr
