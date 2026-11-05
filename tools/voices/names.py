"""Misread words, tolerant of how Whisper spells proper nouns (2026-10-12, prepared for the judge; not used until the
user adopts it and reseals). Whisper hears Forever's names well but writes them its own way: "feralas" for Féralas,
"dunmorog" for Dun Morogh, "tranche-bauge", "ashtrip" for Hache-Tripes, "kirajis" for Qiraji. The judge's word
error rate (tools/voices/judge.py `word_error_rate`) counts each of them as an error; here a proper noun of the text
(a capitalised word not at the start of a sentence) matches a heard word close enough to it, accents and hyphens
aside, and two words of a name may be heard as one (and one as two). Every other word is compared as before.

Simulated on the last take of each refused reading and dialogue page (transcripts of the tries logs): the misread
words pass for 43 of 118 readings and 123 of 267 dialogue pages; 25 and 24 of them pass every criterion.
"""

from __future__ import annotations

import difflib
import re
import unicodedata

NEAR = 0.75  # similarity (difflib ratio) between a name of the text and the word heard for it
SENTENCE_END = '.!?:«"\n'


def fold(text: str) -> str:
    """Lower case, without accents."""
    return unicodedata.normalize("NFKD", text.lower()).encode("ascii", "ignore").decode()


def proper_words(text: str) -> set[str]:
    """The folded words of the text's proper nouns: capitalised, not at the start of a sentence; a hyphenated or
    elided name gives each of its parts."""
    out = set()
    for m in re.finditer(r"[\w'’-]+", text):
        word, before = m.group(0), text[:m.start()].rstrip()
        if word[:1].isupper() and before and before[-1] not in SENTENCE_END:
            out.update(fold(part) for part in re.split(r"[-'’]", word) if part)
    return out


def tolerant_wer(reference: str, hypothesis: str, words, near: float = NEAR) -> float:
    """Levenshtein distance over words, divided by the reference's word count, where a proper noun of the reference
    matches a close word heard, and two name words may match one word heard (or one name word two heard).
    `words`: the judge's normalisation (tools/voices/judge.py words)."""
    names = proper_words(reference)
    ref = fold(words(reference.replace("-", " "))).split()
    hyp = fold(words(hypothesis.replace("-", " "))).split()

    def same(r: str, h: str, name: bool) -> bool:
        return r == h or (name and difflib.SequenceMatcher(None, r, h).ratio() >= near)

    inf = float("inf")
    d = [[inf] * (len(hyp) + 1) for _ in range(len(ref) + 1)]
    d[0] = list(range(len(hyp) + 1))
    for i in range(1, len(ref) + 1):
        d[i][0] = i
        r = ref[i - 1]
        for j in range(1, len(hyp) + 1):
            h = hyp[j - 1]
            cost = min(d[i - 1][j - 1] + (0 if same(r, h, r in names) else 1), d[i - 1][j] + 1, d[i][j - 1] + 1)
            if i >= 2 and ref[i - 2] in names and r in names and same(ref[i - 2] + r, h, True):
                cost = min(cost, d[i - 2][j - 1])  # "dun morogh" heard "dunmorog"
            if j >= 2 and r in names and same(r, hyp[j - 2] + h, True):
                cost = min(cost, d[i - 1][j - 2])  # "tranchebauge" heard "tranche bauge"
            d[i][j] = cost
    return d[len(ref)][len(hyp)] / max(len(ref), 1)
