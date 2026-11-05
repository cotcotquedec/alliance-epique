"""The dialogues frame: what is read and how (2026-10-10). READ-ONLY for the dialogues loop (sealed in
tools/dialogues/SEAL): changing it is a human decision.

A dialogue reading is one page of an NPC's dialogue window, said by that NPC: the scripts.json section "dialogues"
(pipeline/scripts.py: the NPC's text only, never the player's lines), keyed "<npc>_<page>"; for a gendered text
(D8), one reading per player sex. Read exactly like a quest reading (tools/readings/frame.py: Qwen3-TTS 1.7B Base
clones the NPC's model voice, paragraph by paragraph).
"""

from __future__ import annotations

from tools.readings import frame as reading_frame

SECTION = "dialogues"  # scripts.json section (pipeline/scripts.py DIALOGUES)
REPO, LANGUAGE, MAX_TOKENS, GAP = reading_frame.REPO, reading_frame.LANGUAGE, reading_frame.MAX_TOKENS, reading_frame.GAP
SR, LOUDNESS = reading_frame.SR, reading_frame.LOUDNESS
paragraphs = reading_frame.paragraphs


def unit_id(key: str, sex: str) -> str:
    return key + ("_f" if sex == "f" else "")


def units(scripts: dict | None) -> list[dict]:
    """The dialogue readings of a zone's scripts.json: [{id, key, page, sex, npc, name, text, first, quests}]."""
    out = []
    for key, script in sorted(((scripts or {}).get(SECTION) or {}).items(),
                              key=lambda kv: [int(x) for x in kv[0].split("_")]):
        if not script.get("text") or script.get("npc_id") is None:
            continue
        for sex in (("m", "f") if script.get("gendered") else ("m",)):
            out.append({"id": unit_id(key, sex), "key": key, "page": script["page"], "sex": sex,
                        "npc": int(script["npc_id"]), "name": script.get("npc_name") or "?",
                        "first": script.get("first", False), "quests": script.get("quests", []),
                        "text": reading_frame.variant(script["text"], sex)})
    return out
