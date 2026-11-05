"""Text to read aloud, one version for every character (D6, D8; rules in docs/voices-and-text.md).

- `<nom>` (player name) is always a form of address: removed, and the sentence is stitched back.
- `<classe>` / `<race>`: removed when used alone as a form of address; after a word ("jeune
  <classe>", "un <classe>") replaced by the epicene "camarade" (validated 2026-10-05).
- `<a/b>` and `<a/b:c>`: masculine / feminine variants (`text_f` is None when there is none).
- Any other short `<...>` (e.g. `<grand sourire>`) is a stage direction: not read, returned apart.
  A long bracketed block is narration (item-started quests: "<Ce Murloc devait terroriser...>"):
  the text is kept, only the brackets go.
- The read text is the description, then the objectives announced "Objectif : ..." (D6); for the
  turn-in, the completion text alone (decided 2026-10-06).
"""

from __future__ import annotations

import re

NEUTRAL_WORD = "camarade"
OBJECTIVE_PREFIX = "Objectif : "

_ADDRESS = "nom|classe|race"
_GENDER = re.compile(r"<([^<>/]+)/([^<>/]+?)(?::c)?>")
_DIRECTION = re.compile(r"<([^<>/]{1,40})>")
_NARRATION = re.compile(r"<([^<>]{41,})>")


def _unwrap_narration(text: str) -> str:
    return _NARRATION.sub(lambda m: m.group(1), text)


def _strip_address(text: str) -> str:
    # ", <nom>." / ", <nom> !" -> "." ; ", <nom>, " -> ", "
    text = re.sub(rf"\s*,\s*<(?:{_ADDRESS})>\s*(?=[.!?…:;])", "", text)
    text = re.sub(rf",\s*<(?:{_ADDRESS})>\s*,", ",", text)
    # "<nom>, mes éclaireurs" at the start of a sentence -> "Mes éclaireurs"
    text = re.sub(rf"(^|[.!?…]\s+|\n)<(?:{_ADDRESS})>\s*,\s*(\w)",
                  lambda m: m.group(1) + m.group(2).upper(), text)
    # "<prudent/prudente> <nom>." (no comma): just drop it
    text = re.sub(r"\s*<nom>", "", text)
    # what is left of <classe>/<race> follows a word: epicene noun
    return re.sub(r"<(?:classe|race)>", NEUTRAL_WORD, text)


def _tidy(text: str) -> str:
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r" +([.,!?…:;])", lambda m: m.group(1) if m.group(1) in ".,…" else " " + m.group(1), text)
    text = re.sub(r"\.\.\.\s*\.\.\.", "...", text)
    return "\n".join(line.strip() for line in text.split("\n")).strip()


def normalize(text: str | None) -> dict:
    """{'text': masculine or only version, 'text_f': feminine variant or None, 'directions': [...]}"""
    if not text:
        return {"text": None, "text_f": None, "directions": []}
    text = _unwrap_narration(text)
    directions = [d for d in _DIRECTION.findall(text) if d not in ("nom", "classe", "race")]
    text = _DIRECTION.sub(lambda m: m.group(0) if m.group(1) in ("nom", "classe", "race") else " ", text)
    text = _strip_address(text)
    masculine = _tidy(_GENDER.sub(lambda m: m.group(1), text))
    feminine = _tidy(_GENDER.sub(lambda m: m.group(2), text))
    return {"text": masculine, "text_f": feminine if feminine != masculine else None, "directions": directions}


def template(text: str | None) -> dict:
    """Like `normalize`, but the gender agreements stay as `<masculine/feminine>` markers, so that one
    acting direction serves both variants (see `render`)."""
    if not text:
        return {"text": None, "directions": []}
    text = _unwrap_narration(text)
    directions = [d for d in _DIRECTION.findall(text) if d not in ("nom", "classe", "race")]
    text = _DIRECTION.sub(lambda m: m.group(0) if m.group(1) in ("nom", "classe", "race") else " ", text)
    text = _GENDER.sub(lambda m: f"<{m.group(1)}/{m.group(2)}>", _strip_address(text))  # drops ":c"
    return {"text": _tidy(text), "directions": directions}


def speech_template(description: str | None, objectives: str | None) -> dict:
    """The acceptance text (D6) with gender markers: {'text', 'gendered', 'directions'}."""
    desc, obj = template(description), template(objectives)
    if not desc["text"]:
        return {"text": None, "gendered": False, "directions": desc["directions"]}
    text = desc["text"] + ("\n\n" + OBJECTIVE_PREFIX + obj["text"] if obj["text"] else "")
    return {"text": text, "gendered": bool(_GENDER.search(text)), "directions": desc["directions"] + obj["directions"]}


def completion_template(completion: str | None) -> dict:
    """The completion text (said by the NPC the quest is turned in to) with gender markers."""
    tpl = template(completion)
    return {"text": tpl["text"] or None, "gendered": bool(tpl["text"] and _GENDER.search(tpl["text"])),
            "directions": tpl["directions"]}


def render(text: str, sex: str) -> str:
    """Resolve gender markers for a player of sex 'm' or 'f'."""
    return _GENDER.sub(lambda m: m.group(1) if sex == "m" else m.group(2), text)


def speech(description: str | None, objectives: str | None) -> dict:
    """The acceptance text to read (D6): description, then "Objectif : ..."."""
    desc, obj = normalize(description), normalize(objectives)
    if not desc["text"]:
        return {"text": None, "text_f": None, "directions": desc["directions"]}

    def join(d: str, o: str | None) -> str:
        return d + ("\n\n" + OBJECTIVE_PREFIX + o if o else "")

    text = join(desc["text"], obj["text"])
    feminine = None
    if desc["text_f"] or obj["text_f"]:
        feminine = join(desc["text_f"] or desc["text"], obj["text_f"] or obj["text"])
    return {"text": text, "text_f": feminine, "directions": desc["directions"] + obj["directions"]}
