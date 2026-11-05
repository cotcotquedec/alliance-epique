"""Books read by Elise (D19, 2026-10-21): the texts one reads in the world (books, letters, plaques, tombstones,
monuments: the game's "item text", `page_text`), read aloud page by page by the narrator, Elise (D9), in her
ElevenLabs voice. Mail is never read.

Two separate steps, then a loop of their own:
- extraction (`extract.py`): the books of the Forever Database (VMaNGOS `page_text`, French in `locales_page_text`;
  objects of type TEXT and items with a page) -> data/zones/@books/books.json;
- text preparation (`scripts.py`): Elise's script of each page, the text as written -> data/zones/@books/scripts.json,
  with the ElevenLabs character count (`cost`);
- the books loop (tools/books/): one audio per page, audio.json of the same folder.

The folder is a category-like folder of its own (in no group, covered by --all), as data/zones/@elise/levels/ is:
books are not Elise's lines (they have their own loop), and one folder keeps the registry, the scripts and the audio
together, as a category keeps quests.json, scripts.json and audio.json.

    python -m pipeline.books extract | scripts [--force] | cost | show [book]
"""

from pipeline.storage import ZONES_DIR

KEY = "@books"  # loop key of the folder (in no group nor category: covered by --all)
REGISTRY = "books.json"
SECTION = "pages"  # scripts.json section, keyed by page ID
AUDIO_SECTION = "book"  # audio.json section, keyed by page ID
SIDES_IN_SCOPE = ("alliance", "both", "unknown")  # the project is Alliance-only; an unknown side is kept, flagged


def folder(zones_dir=None):
    return (zones_dir or ZONES_DIR) / KEY


def keys(zones_dir=None) -> list[str]:
    """[KEY] once its scripts.json exists, else []."""
    return [KEY] if (folder(zones_dir) / "scripts.json").exists() else []
