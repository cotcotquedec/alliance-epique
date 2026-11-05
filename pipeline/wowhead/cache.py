"""Wowhead pages fetched until 2026-10-12, read from the disk cache only (data/cache/wowhead/).

Wowhead is no longer crawled: its CloudFront WAF refuses every non-browser client (403 checked on 2026-11-01 from
an address a browser reaches the same page from), and getting round it is ruled out (CLAUDE.md §3). What was
fetched before stays useful: the quest categories (data/zones.json, D12), their level order, the zone pages of
Elise's introductions (D16) and the NPC greetings list (pipeline/game_voices.py).
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

CACHE_DIR = Path(__file__).resolve().parents[2] / "data" / "cache" / "wowhead"


@dataclass
class Page:
    path: str
    status: int
    final_url: str
    text: str
    fetched_at: str | None = None


def cache_key(path: str, host: str = "www") -> str:
    key = re.sub(r"[^A-Za-z0-9=._-]+", "_", path.strip("/")) or "root"
    return key if host == "www" else f"{host}_{key}"


def cached(path: str, host: str = "www", cache_dir: Path = CACHE_DIR) -> Page | None:
    """The cached page of `path` (e.g. '/forever/fr/zone=12') on `host`, None if it was never fetched."""
    key = cache_key(path, host)
    body, meta = cache_dir / f"{key}.html", cache_dir / f"{key}.json"
    if not meta.exists():
        return None
    info = json.loads(meta.read_text(encoding="utf-8"))
    text = body.read_text(encoding="utf-8") if body.exists() else ""
    return Page(path, info["status"], info["final_url"], text, info.get("fetched_at"))
