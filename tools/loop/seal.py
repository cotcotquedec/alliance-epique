"""Seal of a pass's read-only objects (constitution, oracle, arbiter, ratchet code).

A human reviews those files, then seals them: `tools/loop/seal.sh text`. The seal (tools/<pass>/SEAL,
committed) holds their SHA-256. The loop refuses to start, and stops before each arbitration, if a sealed
file changed since: the loop never runs on a success criterion nobody validated (rule no. 1).
"""

from __future__ import annotations

import hashlib
from pathlib import Path

from pipeline.storage import REPO_ROOT


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(seal: Path, files: list[str], root: Path = REPO_ROOT) -> str:
    text = "".join(f"{digest(root / f)}  {f}\n" for f in files)
    seal.write_text(text, encoding="utf-8")
    return text


def check(seal: Path, files: list[str], root: Path = REPO_ROOT) -> list[str]:
    """Problems found (empty: the seal holds)."""
    if not seal.exists():
        return [f"no seal ({seal.relative_to(root) if seal.is_relative_to(root) else seal}): review the "
                "read-only objects, then seal them"]
    sealed = dict(reversed(line.split("  ", 1)) for line in seal.read_text(encoding="utf-8").splitlines() if line)
    problems = [f"{f}: not in the seal" for f in files if f not in sealed]
    problems += [f"{f}: changed since the seal" for f in files
                 if f in sealed and (not (root / f).exists() or digest(root / f) != sealed[f])]
    return problems
