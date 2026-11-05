"""Elise's zone introductions (2026-10-11): the first time the player sets foot in a zone, Elise (D9) says a few
words about it, written for her from the zone's lore and our registries.

- zones.py: the zones that get one (the Forever Database's top-level areas of the two continents, with their
  French name and the client's map ID), and each zone's dossier (places, people, quests, levels);
- generate.py: Claude writes each introduction (prompt_v<N>.md, pinned model, JSON schema), stored as a script in
  data/zones/<group>/@intros/scripts.json, section "zones"; the Elise loop reads it there (tools/elise/frame.py);
- `python -m pipeline.zone_intros list | dossier <area> | generate [--zone <area>]... [--force]`.
"""

from pipeline.storage import ZONES_DIR

INTROS = "@intros"  # the category-like folder of a group holding its intros (no quests.json: not a category)
SECTION = "zones"  # scripts.json section


def folder(group: str):
    return ZONES_DIR / group / INTROS


def keys(zones_dir=None) -> list[str]:
    """The intro folders on disk, as loop keys ("eastern-kingdoms/@intros"), continent order."""
    base = zones_dir or ZONES_DIR
    return [f"{g}/{INTROS}" for g in ("eastern-kingdoms", "kalimdor") if (base / g / INTROS / "scripts.json").exists()]
