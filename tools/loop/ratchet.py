"""Ratchet: the highest level a pass ever reached, kept on disk. READ-ONLY for the loop: only `tighten`
writes it, and it can only go up, counter by counter. A level below it means data was lost.

The file lives with the pass's run files (data/cache/loops/<pass>/ratchet.json). To accept a lower level
on purpose (a zone refetched with fewer quests, a registry cleaned by hand), a human deletes the file.
"""

from __future__ import annotations

from pathlib import Path

from pipeline import storage
from tools.loop.arbiter import dropped


def load(path: Path) -> dict | None:
    data = storage.read_json(path)
    return data["level"] if data else None


def tighten(path: Path, level: dict, when: str) -> dict:
    """Raises the ratchet to `level` (counter by counter) and returns it; refuses to lower it."""
    current = load(path) or {}
    lost = dropped(current, level)
    if lost:
        raise ValueError(f"the ratchet never goes down: {lost}")
    merged = {k: max(v, current.get(k, v)) for k, v in level.items()}
    if merged != current:
        storage.write_json(path, {"level": merged, "updated": when})
    return merged
