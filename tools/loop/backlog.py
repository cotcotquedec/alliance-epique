"""Backlog written by a pass's critic: what is missing, zone by zone. It never validates anything and the
arbiter never reads it; it is for the human (data/cache/loops/<pass>/backlog.md)."""

from __future__ import annotations

import re
from pathlib import Path

from pipeline import storage

ERROR_PATTERN = re.compile(r"FAILED|ERROR|Error|Traceback|STOPPED|stopped:|refused", re.IGNORECASE)


def error_lines(output_tail: str, limit: int = 10) -> list[str]:
    return [ln.strip() for ln in output_tail.splitlines() if ERROR_PATTERN.search(ln)][-limit:]


def record(run_dir: Path, zone: str, entry: dict) -> None:
    """Replaces the zone's entry, then rewrites backlog.md from backlog.json."""
    path = run_dir / "backlog.json"
    backlog = storage.read_json(path, {})
    backlog[zone] = entry
    storage.write_json(path, backlog)
    lines = ["# Backlog", "", "Written by the critic after each attempt: what is still missing. Nothing here is "
             "validated; the arbiter does not read it.", ""]
    for key, item in backlog.items():
        lines.append(f"## {key}")
        lines.append("")
        for name, value in item.items():
            if isinstance(value, list):
                shown = ", ".join(str(v) for v in value[:40]) + (" …" if len(value) > 40 else "")
                lines.append(f"- {name} ({len(value)}): {shown or 'none'}")
            else:
                lines.append(f"- {name}: {value}")
        lines.append("")
    (run_dir / "backlog.md").write_text("\n".join(lines), encoding="utf-8")
