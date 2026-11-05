"""Releases of the Forever Database (github.com/Stein-N/WoW-Quest-Database): we follow its tags, not its main
branch (decided 2026-10-08). Read-only: `git ls-remote` for the tags, the GitHub API to place a build made from
an untagged commit, the release's CHANGELOG.json for its notes.

    python -m pipeline.foreverdb.release check     is there a newer release than our build? (tools/db_check.sh)
    python -m pipeline.foreverdb.release latest    the latest release tag (tools/prepare_db.sh --update)

Exit codes of `check`: 0 up to date (or our build is newer than the latest release), 10 a newer release, or no
build yet, 2 cannot tell (network).
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import urllib.error
import urllib.request

from pipeline import storage

REPO_URL = "https://github.com/Stein-N/WoW-Quest-Database.git"
API = "https://api.github.com/repos/Stein-N/WoW-Quest-Database"
RAW = "https://raw.githubusercontent.com/Stein-N/WoW-Quest-Database"
DB_DIR = storage.REPO_ROOT / ".data" / "forever-db"
UP_TO_DATE, NEWER, UNKNOWN = 0, 10, 2
_VERSION = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")


def version(tag: str) -> tuple[int, int, int] | None:
    m = _VERSION.match(tag)
    return tuple(int(g) for g in m.groups()) if m else None


def remote_tags(run=subprocess.run) -> dict[str, str]:
    """Release tag -> commit SHA (an annotated tag's peeled commit wins)."""
    proc = run(["git", "ls-remote", "--tags", REPO_URL], capture_output=True, text=True, timeout=60)
    if proc.returncode != 0:
        raise OSError(f"git ls-remote failed: {proc.stderr.strip()[-300:]}")
    tags: dict[str, str] = {}
    for line in proc.stdout.splitlines():
        sha, _, ref = line.partition("\t")
        name = ref.removeprefix("refs/tags/")
        peeled = name.endswith("^{}")
        name = name.removesuffix("^{}")
        if version(name) and (peeled or name not in tags):
            tags[name] = sha
    return tags


def latest(tags: dict[str, str]) -> str | None:
    return max(tags, key=version) if tags else None


def local_head(run=subprocess.run) -> str | None:
    if not (DB_DIR / ".git").exists():
        return None
    proc = run(["git", "-C", str(DB_DIR), "rev-parse", "HEAD"], capture_output=True, text=True)
    return proc.stdout.strip() or None


def _get(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "ForeverSpeech release check (personal use)"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def compare(base: str, head: str, get=_get) -> str:
    """GitHub's status of `head` against `base`: "ahead", "behind", "identical" or "diverged"."""
    return json.loads(get(f"{API}/compare/{base}...{head}"))["status"]


def notes(tag: str, newer_than: tuple | None, get=_get) -> list[str]:
    """The data notes of the releases after `newer_than` up to `tag`, from the release's CHANGELOG.json."""
    try:
        changelog = json.loads(get(f"{RAW}/{tag}/CHANGELOG.json"))
    except (OSError, ValueError):
        return ["  (changelog unavailable)"]
    out = []
    for entry in changelog.get("versions", []):
        v = version(entry.get("version", ""))
        if v is None or v > version(tag) or (newer_than is not None and v <= newer_than):
            continue
        out.append(f"  {entry['version']} ({entry.get('date')}): {len(entry.get('website') or [])} website note(s)")
        out += [f"    - {line}" for line in entry.get("dataNotes") or []]
    return out


def check(run=subprocess.run, get=_get) -> tuple[int, list[str]]:
    """(exit code, lines for a human)."""
    head = local_head(run)
    if head is None:
        return NEWER, ["no Forever Database built yet: tools/prepare_db.sh"]
    try:
        tags = remote_tags(run)
    except (OSError, subprocess.TimeoutExpired) as err:
        return UNKNOWN, [f"cannot read the releases: {err}"]
    newest = latest(tags)
    if newest is None:
        return UNKNOWN, ["the repository has no release tag"]
    ours = max((t for t, sha in tags.items() if sha == head), key=version, default=None)
    lines = [f"our build: {ours or 'untagged commit'} ({head[:7]}); latest release: {newest} "
             f"({tags[newest][:7]})"]
    if ours == newest:
        return UP_TO_DATE, lines + ["up to date"]
    if ours is not None:
        return NEWER, lines + [f"newer release: {newest}", *notes(newest, version(ours), get), *NEXT]
    try:
        status = compare(tags[newest], head, get)
    except (OSError, ValueError, KeyError) as err:
        return UNKNOWN, lines + [f"cannot place our build against {newest}: {err}"]
    if status in ("ahead", "identical"):
        return UP_TO_DATE, lines + [f"our build is newer than {newest} (main branch): nothing to do until the "
                                    "next release"]
    return NEWER, lines + [f"newer release: {newest} (our build is {status})", *notes(newest, None, get), *NEXT]


NEXT = ["next: tools/prepare_db.sh --update, then tools/zone.sh sync --dry-run (no loop running)"]


def main(argv: list[str] | None = None) -> None:
    command = (argv if argv is not None else sys.argv[1:] or ["check"])[0]
    if command == "latest":
        tag = latest(remote_tags())
        if tag is None:
            raise SystemExit("the repository has no release tag")
        print(tag)
        return
    if command != "check":
        raise SystemExit(__doc__)
    code, lines = check()
    print("\n".join(lines))
    sys.exit(code)


if __name__ == "__main__":
    main()
