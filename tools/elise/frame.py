"""The Elise frame: what she reads and how (2026-10-10). READ-ONLY for the Elise loop (sealed in tools/elise/SEAL):
changing it is a human decision.

Her lines: every quest text no NPC says, the scripts whose speaker is the narrator (pipeline/scripts.py,
pipeline/narrator.py), start ("detail") and end ("complete") of quest, one line per player sex for a gendered text
(D8), as the readings frame cuts them (tools/readings/frame.py `units`); and since 2026-10-11 her introduction of each
zone ("zone"), said the first time the player sets foot in it: the scripts.json section "zones" of the intro folders
(data/zones/<group>/@intros/, pipeline/zone_intros/), keyed by area ID, one line (written without any agreement with
the player's sex), line ID "<area>_zone"; and her level-up lines ("level", 2026-10-11), one per level gained (2 to
60), one story: scripts.json section "levels" of data/zones/@elise/levels/ (pipeline/level_lines/), line ID
"<level>_level"; and her companion lines ("companion", D18, 2026-10-15), one of a tier's 10 lines when a companion
reaches that friendship tier, written by hand: scripts.json section "lines" of data/zones/@elise/companions/
(pipeline/companion_lines/), line ID "<ID>_companion" (ID: the tier's place x 100 + the variant, 401: good friend,
line 1). Her voice is fixed (tools/elise/voice.py);
ElevenLabs reads each line whole with TTS_MODEL. A line's audio is tied to its text: `text_hash`, so a changed text
gets a new audio (her voice does not change, decided 2026-10-10).
"""

from __future__ import annotations

import hashlib

from pipeline import companion_lines, narrator
from tools.readings import frame as reading_frame

TTS_MODEL = "eleven_v4"  # the model of the Elwynn readings (2026-10-07), French
OUTPUT_FORMAT = "mp3_44100_192"
SETTINGS = None  # ElevenLabs' defaults for her voice
SR = 44100  # takes: mono 44.1 kHz WAV, -20 LUFS like the Qwen3 readings
LOUDNESS = -20.0


ZONES = "zones"  # scripts.json section of her zone introductions (pipeline/zone_intros/)
LEVELS = "levels"  # scripts.json section of her level-up lines (pipeline/level_lines/)


def units(scripts: dict | None) -> list[dict]:
    """Her lines in a zone's scripts.json: [{id, quest, kind, sex, npc, name, text}] ("quest": the area ID of a zone
    introduction, the level of a level-up line, the line ID of a companion line)."""
    out = [u for u in reading_frame.units(scripts) if narrator.is_narrator(u["npc"])]
    for section, kind in ((ZONES, "zone"), (LEVELS, "level")):
        for key, script in sorted(((scripts or {}).get(section) or {}).items(), key=lambda kv: int(kv[0])):
            if script.get("text") and narrator.is_narrator(script.get("npc_id")):
                out.append({"id": reading_frame.unit_id(key, kind, "m"), "quest": int(key), "kind": kind,
                            "sex": "m", "npc": narrator.NARRATOR_ID, "name": script.get("name") or "?",
                            "text": script["text"]})
    for line in companion_lines.lines(scripts):
        out.append({"id": reading_frame.unit_id(line["id"], "companion", "m"), "quest": line["id"],
                    "kind": "companion", "sex": "m", "npc": narrator.NARRATOR_ID, "name": line["name"],
                    "text": line["text"]})
    return out


def text_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]
