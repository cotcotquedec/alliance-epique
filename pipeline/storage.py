"""Local data registries on disk (data/zones.json, data/zones/<zone>/{quests,npcs}.json)."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = REPO_ROOT / "data"
ZONES_FILE = DATA_DIR / "zones.json"
ZONES_DIR = DATA_DIR / "zones"


def now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S")


def read_json(path: Path, default=None):
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value) -> None:
    """Atomic write: an interrupted run never leaves a truncated registry behind."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def by_id(records: dict) -> dict:
    """Records keyed by str(id), in numeric order (stable diffs)."""
    return {str(k): records[k] for k in sorted(records, key=int)}
