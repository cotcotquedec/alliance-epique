"""What a loop run (or the report) covers: the data's own structure, groups and categories (2026-10-07).

The quests are sorted as on Wowhead: a **group** (a continent, or a theme: eastern-kingdoms, kalimdor, classes,
professions, dungeons, raids, battlegrounds, world-events, miscellaneous, uncategorized) holds **categories**
(elwynn-forest, warrior, alchemy...): data/zones/<group>/<category>/. A category is always given with its group;
a group without categories (uncategorized) is a category on its own.

    --all                                     every group
    --group classes                           every category of the group
    --group eastern-kingdoms --category elwynn-forest [--category westfall]...
"""

from __future__ import annotations

import argparse
from pathlib import Path

from pipeline import storage

USAGE = "give --all, or --group G (and optionally --category C, repeatable, a category of that group)"


class ScopeError(ValueError):
    pass


def groups(zones_dir: Path | None = None) -> dict[str, list[str]]:
    """group -> its category keys ("eastern-kingdoms/elwynn-forest"; "uncategorized" for a group without any),
    from the registries on disk (a category exists once it has its quests.json)."""
    zones_dir = zones_dir or storage.ZONES_DIR
    out: dict[str, list[str]] = {}
    for path in sorted(zones_dir.glob("**/quests.json")):
        key = str(path.parent.relative_to(zones_dir))
        out.setdefault(key.split("/", 1)[0], []).append(key)
    return out


def resolve(all_: bool, group: str | None, categories: list[str] | None,
            zones_dir: Path | None = None) -> list[str] | None:
    """The category keys of the scope, or None for --all. Raises ScopeError with what is wrong and what exists."""
    known = groups(zones_dir)
    if all_:
        if group or categories:
            raise ScopeError("--all covers every group: no --group or --category with it")
        return None
    if not group:
        raise ScopeError(USAGE if not categories else "a --category is always given with its --group")
    if group not in known:
        raise ScopeError(f"unknown group {group!r}; groups: {', '.join(known)}")
    keys = known[group]
    if not categories:
        return keys
    out = []
    for category in categories:
        name = category.split("/", 1)[1] if category.startswith(group + "/") else category
        key = f"{group}/{name}"
        if key not in keys:
            names = ", ".join(k.split("/", 1)[1] for k in keys if "/" in k) or "none (the group is one category)"
            raise ScopeError(f"no category {name!r} in group {group!r}; its categories: {names}")
        out.append(key)
    return list(dict.fromkeys(out))


def add_arguments(ap: argparse.ArgumentParser) -> None:
    ap.add_argument("--all", action="store_true", dest="all_groups", help="every group")
    ap.add_argument("--group", help="a group: eastern-kingdoms, kalimdor, classes, professions, dungeons...")
    ap.add_argument("--category", action="append", help="a category of that group (repeatable), e.g. elwynn-forest")


def from_args(args, required: bool = True) -> list[str] | None:
    """The scope of parsed arguments (add_arguments); without any and not required: everything (None)."""
    if not required and not (args.all_groups or args.group or args.category):
        return None
    return resolve(args.all_groups, args.group, args.category)
