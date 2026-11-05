"""The readings frame: what is read and how the NPC's model voice is cloned (2026-10-07). READ-ONLY for the
readings loop (sealed in tools/readings/SEAL): changing it is a human decision, and readings already accepted are
kept.

A reading is one quest text said by its NPC: the start (scripts.json "scripts", said by the giver) or the end
("complete", said by the ender), and for a gendered text (D8) one reading per player sex. The text is the script's
plain text (depersonalized, without the ElevenLabs acting tags), its "<masculine/feminine>" forms resolved. Qwen3-TTS
1.7B Base clones the NPC's model voice (voice loop: data/voices/samples/qwen/voices/<npc>/ref.wav and ref.txt) and
reads it paragraph by paragraph, the paragraphs joined by a short silence; validated by ear on the Adjoint Willem's
quests on 2026-10-07.
"""

from __future__ import annotations

import re

REPO = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"
LANGUAGE = "french"
MAX_TOKENS = 4096
GAP = 0.35  # seconds of silence between paragraphs
SR = 24000  # takes: mono 24 kHz, -20 LUFS
LOUDNESS = -20.0
SECTIONS = (("scripts", "detail"), ("complete", "complete"))  # scripts.json section -> kind
VARIANT = re.compile(r"<([^<>/]*)/([^<>]*)>")  # "<un ami/une amie>": masculine / feminine


def variant(text: str, sex: str) -> str:
    return VARIANT.sub(lambda m: m.group(1) if sex == "m" else m.group(2), text)


def paragraphs(text: str) -> list[str]:
    return [p.strip() for p in re.split(r"\n+", text) if p.strip()]


def unit_id(quest: int | str, kind: str, sex: str) -> str:
    return f"{quest}_{kind}" + ("_f" if sex == "f" else "")


def units(scripts: dict | None) -> list[dict]:
    """The readings of a zone's scripts.json: [{id, quest, kind, sex, npc, name, text}], quest order."""
    out = []
    for section, kind in SECTIONS:
        for qid, script in sorted(((scripts or {}).get(section) or {}).items(), key=lambda kv: int(kv[0])):
            if not script.get("text") or script.get("npc_id") is None:
                continue
            for sex in (("m", "f") if script.get("gendered") else ("m",)):
                out.append({"id": unit_id(qid, kind, sex), "quest": int(qid), "kind": kind, "sex": sex,
                            "npc": int(script["npc_id"]), "name": script.get("name") or "?",
                            "text": variant(script["text"], sex)})
    return out
