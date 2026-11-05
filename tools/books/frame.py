"""The books frame: what Elise reads and how (D19, 2026-10-21). READ-ONLY for the books loop (sealed in
tools/books/SEAL): changing it is a human decision.

A book reading is one page of a book (D19), said by Elise, the narrator: the scripts.json section "pages" of
data/zones/@books/ (pipeline/books/scripts.py), keyed by page ID; for a gendered page (D8), one reading per player
sex. Unit ID "book_<page>" (and "book_<page>_f"), which is also the game file's name:
addon/ForeverSpeech/audio/1000000/book_<page>[_f].ogg (index contract v9). ElevenLabs reads each page whole in her
fixed voice, with the model, settings and output of her own lines (tools/elise/frame.py, imported: the same voice
must sound the same). A page's audio is tied to its text (`text_hash`): a changed text gets a new audio.
"""

from __future__ import annotations

from pipeline import books, narrator
from pipeline.narration import render
from tools.elise import frame as elise_frame

TTS_MODEL, OUTPUT_FORMAT, SETTINGS = elise_frame.TTS_MODEL, elise_frame.OUTPUT_FORMAT, elise_frame.SETTINGS
SR, LOUDNESS = elise_frame.SR, elise_frame.LOUDNESS
text_hash = elise_frame.text_hash
KIND = "book"


def unit_id(page: int | str, sex: str) -> str:
    return f"book_{page}" + ("_f" if sex == "f" else "")


def units(scripts: dict | None) -> list[dict]:
    """The page readings of the books scripts.json: [{id, page, kind, sex, npc, name, text}], page order."""
    out = []
    for key, script in sorted(((scripts or {}).get(books.SECTION) or {}).items(), key=lambda kv: int(kv[0])):
        if not script.get("text") or not narrator.is_narrator(script.get("npc_id")):
            continue
        for sex in (("m", "f") if script.get("gendered") else ("m",)):
            out.append({"id": unit_id(key, sex), "page": int(key), "quest": int(key), "kind": KIND, "sex": sex,
                        "npc": narrator.NARRATOR_ID, "name": f"{script.get('title') or '?'} p.{script.get('n', 1)}",
                        "text": render(script["text"], sex)})
    return out
