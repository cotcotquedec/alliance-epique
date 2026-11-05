"""Elise's level-up lines (2026-10-11): each time the character gains a level (2 to 60), Elise says a few words, and
the 59 lines tell one story, from the first steps to the vision of the end game, in crescendo, on the Alliance's
side. Claude writes the story's arc and every line in one answer (generate.py, prompt_v<N>.md), so that they hold
together; a line that breaks a rule is asked again alone, with the arc and its neighbours.

Stored as scripts of data/zones/@elise/levels/scripts.json, section "levels", keyed by level, said by Elise (npc_id
NARRATOR_ID), with the arc beside them; the Elise loop reads them there (tools/elise/frame.py, kind "level").

    python -m pipeline.level_lines generate [--force] | show [level] | again <level>...
"""

from pipeline.storage import ZONES_DIR

KEY = "@elise/levels"  # loop key of the folder (in no group nor category: covered by --all)
SECTION = "levels"  # scripts.json section
FIRST, LAST = 2, 60


def folder():
    return ZONES_DIR / KEY


def keys(zones_dir=None) -> list[str]:
    """[KEY] once its scripts.json exists, else []."""
    return [KEY] if ((zones_dir or ZONES_DIR) / KEY / "scripts.json").exists() else []
