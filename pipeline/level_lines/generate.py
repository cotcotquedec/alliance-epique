"""Claude writes Elise's level-up story (pipeline/llm.py): the arc and the 59 lines in one answer (prompt_v<N>.md,
pinned model, JSON schema). Each line is checked (length for its level, no figure, no symbol, no game word); a line
that breaks a rule is asked again alone, with the arc and its neighbours (ATTEMPTS at most). Only written when
missing, or with --force (every line: a new story), or `again` (some levels, in the same story): a new text means a
new audio (the Elise loop redoes a changed text, credits included).
"""

from __future__ import annotations

import hashlib
import json
import re

from pipeline import narrator, storage
from pipeline.llm import LLMError, claude_json
from pipeline.level_lines import FIRST, LAST, SECTION, folder

PROMPT_VERSION = 1  # v1 (2026-10-11)
MODEL = "claude-opus-5-5"
EFFORT = "high"
ATTEMPTS = 3
GAME_WORDS = re.compile(r"\b(niveaux?|expériences?|quêtes?|talents?|donjons?|raids?|monstres?|PNJ)\b", re.IGNORECASE)

STORY_SCHEMA = {
    "type": "object", "additionalProperties": False, "required": ["arc", "lines"],
    "properties": {
        "arc": {"type": "string"},
        "lines": {"type": "array", "minItems": LAST - FIRST + 1, "maxItems": LAST - FIRST + 1, "items": {
            "type": "object", "additionalProperties": False, "required": ["level", "text"],
            "properties": {"level": {"type": "integer"}, "text": {"type": "string"}}}},
    },
}
LINE_SCHEMA = {"type": "object", "additionalProperties": False, "required": ["text"],
               "properties": {"text": {"type": "string"}}}


def prompt_file():
    from pathlib import Path
    return Path(__file__).with_name(f"prompt_v{PROMPT_VERSION}.md")


def words_for(level: int) -> tuple[int, int]:
    """The length the prompt asks for a level, with a little slack before asking again."""
    if level >= LAST:
        return 35, 90
    return (10, 40) if level < 40 else (12, 50)


def problems(level: int, text: str) -> list[str]:
    out = []
    low, high = words_for(level)
    words = len(re.findall(r"[\wÀ-ÿ'’-]+", text))
    if not low <= words <= high:
        out.append(f"{words} mots")
    if re.search(r"\d", text):
        out.append("un nombre en chiffres")
    if re.search(r"[()\[\]<>$*#_!]", text):
        out.append("une parenthèse, un symbole ou une exclamation")
    if GAME_WORDS.search(text):
        out.append(f"un mot de jeu ({GAME_WORDS.search(text).group(0)})")
    return out


def clean(text: str) -> str:
    return "\n\n".join(p.strip() for p in re.split(r"\n\s*\n", text.strip()) if p.strip())


def scripts_file():
    return folder() / "scripts.json"


def existing() -> dict:
    return storage.read_json(scripts_file()) or {"schema": 1}


def _record(level: int, text: str, model: str, attempts: int, story: str) -> dict:
    return {"npc_id": narrator.NARRATOR_ID, "name": f"Niveau {level}", "level": level, "text": text,
            "generator": {"prompt_version": PROMPT_VERSION, "model": model, "effort": EFFORT, "story": story,
                          "attempts": attempts},
            "created_at": storage.now()}


def again_one(level: int, arc: str, lines: dict[int, str], issues: list[str] | None, call=claude_json,
              bare: bool = False) -> tuple[str, str]:
    """One level's line written again in the story: (text, model)."""
    near = {lv: lines[lv] for lv in range(level - 3, level + 4) if lv in lines and lv != level}
    msg = (f"L'arc de l'histoire :\n{arc}\n\nLes répliques voisines (niveau : texte) :\n"
           + json.dumps(near, ensure_ascii=False, indent=1)
           + f"\n\nÉcris seulement la réplique du niveau {level}, dans la même histoire, selon les mêmes règles."
           + (f" La précédente ne les respectait pas : {' ; '.join(issues)}." if issues else ""))
    answer = call(prompt_file().read_text(encoding="utf-8"), msg, LINE_SCHEMA, MODEL, EFFORT, bare=bare)
    return clean(answer.data["text"]), answer.model


def fix(level: int, arc: str, lines: dict[int, str], call=claude_json, bare: bool = False,
        issues: list[str] | None = None) -> tuple[str, str, int]:
    """Asks a line again until it passes: (text, model, attempts)."""
    for attempt in range(1, ATTEMPTS + 1):
        text, model = again_one(level, arc, lines, issues, call, bare)
        issues = problems(level, text)
        if not issues:
            return text, model, attempt
    raise LLMError(f"level {level}: still {', '.join(issues)} after {ATTEMPTS} attempts")


def generate(force: bool = False, call=claude_json, bare: bool = False, log=print) -> dict:
    """Writes the story (arc and 59 lines) if missing, or again with force. Returns {"written", "fixed"}."""
    data = existing()
    if (data.get(SECTION) or {}) and not force:
        log("the story is written (--force for a new one, `again <level>` for some lines)")
        return {"written": 0, "fixed": 0}
    log(f"writing the story with {MODEL}")
    answer = call(prompt_file().read_text(encoding="utf-8"),
                  f"Écris l'arc et les {LAST - FIRST + 1} répliques, du niveau {FIRST} au niveau {LAST}.",
                  STORY_SCHEMA, MODEL, EFFORT, bare=bare)
    arc = answer.data["arc"].strip()
    lines = {int(x["level"]): clean(x["text"]) for x in answer.data["lines"]}
    missing = [lv for lv in range(FIRST, LAST + 1) if lv not in lines]
    if missing:
        raise LLMError(f"levels missing in the answer: {missing}")
    story = hashlib.sha256(arc.encode("utf-8")).hexdigest()[:12]
    records, fixed = {}, 0
    for level in range(FIRST, LAST + 1):
        issues = problems(level, lines[level])
        attempts = 1
        if issues:
            log(f"level {level}: {', '.join(issues)}: asked again")
            lines[level], _, attempts = fix(level, arc, lines, call, bare, issues)
            attempts += 1
            fixed += 1
        records[str(level)] = _record(level, lines[level], answer.model, attempts, story)
    storage.write_json(scripts_file(), {"schema": 1, "arc": arc, "story": story, SECTION: records})
    return {"written": len(records), "fixed": fixed}


def again(levels: list[int], call=claude_json, bare: bool = False, log=print) -> int:
    """Writes some levels' lines again, in the story already written."""
    data = existing()
    records = data.get(SECTION) or {}
    if not records:
        raise SystemExit("no story yet: python -m pipeline.level_lines generate")
    lines = {int(k): v["text"] for k, v in records.items()}
    for level in levels:
        text, model, attempts = fix(level, data["arc"], lines, call, bare)
        lines[level] = text
        records[str(level)] = _record(level, text, model, attempts, data.get("story", ""))
        log(f"level {level}: {text}")
    data[SECTION] = {str(k): records[str(k)] for k in sorted(map(int, records))}
    storage.write_json(scripts_file(), data)
    return len(levels)
