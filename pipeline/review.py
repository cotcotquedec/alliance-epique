"""Review of every generated audio, whatever loop made it (2026-10-10): one life cycle and the user's decisions.

Life cycle, shown the same way for every kind (quest readings, Elise's lines, NPC dialogues, NPC model voices, book
pages read by Elise, D19):
  todo -> in_progress -> refused | validated
- todo: never tried in this run; in_progress: refused by the judge, takes left in this run; refused: no take kept
  after the run's takes (the next run tries again), or refused by hand; validated: by the judge or by hand.
The loops still store their own words (ok, pending, not_found): `status()` maps them.

A refused audio is played in game all the same (decided 2026-10-10): its best take is put in place
(`publish_refused`), marked `refused: {by: judge}`, until a take passes; the oracles never count it as settled.

The user's decisions (control page, tools/voices/bench.py) go to data/review/decisions.json and are applied as soon
as no loop that writes the same files runs, else at the start of that loop's next run (`apply_pending`):
- delete: the audio is removed entirely (game ogg, master, its entry, its best take): back to todo, made again by
  the next pass. For a model voice: the voice and all its NPC's readings and dialogues are redone (tools/voices/redo).
- validate (a refused audio) and refuse (a validated one): applied once the loops' oracles honour a human decision
  (HONOURED, set when they are updated and resealed: a human decision); until then they wait in the queue.

    python -m pipeline.review publish [--kind reading|dialogue|elise|book]  # refused audio in game, when safe
    python -m pipeline.review apply                                       # the decisions waiting, when safe
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

from pipeline import storage

ROOT = storage.REPO_ROOT
DECISIONS = ROOT / "data" / "review" / "decisions.json"
KINDS = ("reading", "dialogue", "elise", "voice", "book")
ACTIONS = ("validate", "refuse", "delete")
STATUS = {"ok": "validated", "pending": "in_progress", "not_found": "refused", "todo": "todo", "new": "todo",
          "waiting_voice": "waiting_voice"}
# the loops whose files an action on this kind writes (never at the same time)
WRITERS = {"reading": ("readings", "elise"), "elise": ("elise", "readings"), "dialogue": ("dialogues",),
           "voice": ("voices", "text", "readings", "dialogues"), "book": ("books",)}
# kinds whose oracle counts a human validation or refusal (2026-10-10: readings, dialogues, Elise; the voices' oracle
# later: its loop was running)
HONOURED: set[str] = {"reading", "dialogue", "elise", "book"}


def now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S")


def status(loop_status: str | None) -> str:
    return STATUS.get(loop_status or "todo", loop_status or "todo")


def running(loops: tuple[str, ...], run=subprocess.run) -> list[str]:
    return [n for n in loops if run(["pgrep", "-f", f"tools[.]loop run {n}"], capture_output=True).returncode == 0]


# --- where each kind keeps an audio --------------------------------------------------------------------------

class Asset:
    """One audio of a kind, located on disk: its state entry, its in-place item, its game file, its best take."""

    def __init__(self, kind: str, zone: str | None, unit: str):
        if kind not in KINDS:
            raise ValueError(f"unknown kind {kind}")
        self.kind, self.zone, self.unit = kind, zone, unit
        zones = ROOT / "data" / "zones"
        if kind == "reading":
            from tools.readings import judge
            self.judge = judge
            quest, part, *rest = unit.split("_")
            self.sex = "f" if rest else "m"
            self.state_path, self.state_key = judge.state_file(zone), "readings"
            self.audio_path, self.path = judge.audio_file(zone), (judge.SECTION[part], quest)
        elif kind == "elise":
            from tools.elise import judge
            self.judge = judge
            quest, part, *rest = unit.split("_")
            self.sex = "f" if rest else "m"
            self.state_path, self.state_key = judge.STATE, "lines"
            self.audio_path, self.path = judge.audio_file(zone), (judge.SECTION[part], quest)
        elif kind == "book":
            from tools.books import judge
            self.judge = judge
            page = unit.split("_")[1]  # "book_<page>[_f]"
            self.sex = "f" if unit.endswith("_f") else "m"
            self.state_path, self.state_key = judge.STATE, "lines"
            self.audio_path, self.path = judge.audio_file(zone), (judge.SECTION, page)
        elif kind == "dialogue":
            from tools.dialogues import judge
            self.judge = judge
            parts = unit.split("_")
            self.sex = "f" if parts[-1] == "f" else "m"
            key = "_".join(parts[:2])
            self.state_path, self.state_key = judge.state_file(zone), "readings"
            self.audio_path, self.path = judge.audio_file(zone), (judge.SECTION, key)
        else:
            self.judge = None
        self.zones = zones

    # state entry and in-place item
    def state(self) -> dict:
        return storage.read_json(self.state_path) or {"schema": 1, self.state_key: {}}

    def entry(self, state: dict | None = None) -> dict:
        return ((state or self.state()).get(self.state_key) or {}).get(self.unit) or {}

    def audio(self) -> dict:
        return storage.read_json(self.audio_path) or {"schema": 1}

    def item(self, audio: dict | None = None) -> dict | None:
        section, key = self.path
        return (((audio or self.audio()).get(section) or {}).get(key) or {}).get(self.sex)


def _remove_item(asset: Asset) -> dict | None:
    audio = asset.audio()
    section, key = asset.path
    group = (audio.get(section) or {}).get(key) or {}
    item = group.pop(asset.sex, None)
    if item is None:
        return None
    if not any(k in group for k in ("m", "f")):
        audio[section].pop(key, None)
    storage.write_json(asset.audio_path, audio)
    return item


def _game_path(file: str) -> Path:
    return ROOT / "addon" / "ForeverSpeech" / "audio" / file.split("\\audio\\", 1)[-1].replace("\\", "/")


# --- refused audio in game -----------------------------------------------------------------------------------

def _npc(asset: Asset, entry: dict):
    if asset.kind in ("elise", "book"):
        from pipeline import narrator
        return narrator.NARRATOR_ID
    return entry.get("npc")


def _meta(asset: Asset, entry: dict, best: dict) -> dict:
    meta = {"id": asset.unit, "npc": _npc(asset, entry), "seed": best["seed"], "engine": best.get("engine", ""),
            "text": best.get("text", ""), "voice_seed": best.get("voice_seed")}
    if asset.kind in ("elise", "book"):
        from tools.elise import frame
        meta.update(model=frame.TTS_MODEL, voice_id=asset.judge.voice_id())
    return meta


def publish(asset: Asset, when: str | None = None) -> bool:
    """Puts the asset's best refused take in game, unless an audio is already in place for it or this very take is
    already published. Returns True when it wrote one."""
    state = asset.state()
    entry = asset.entry(state)
    best = entry.get("best") or {}
    take = ROOT / best["take"] if best.get("take") else None
    if entry.get("status") == "ok" or not take or not take.is_file():
        return False
    item = asset.item()
    if item and not item.get("refused"):
        return False  # a validated audio is in place (the judge's or a human's)
    if item and item.get("seed") == best["seed"]:
        return False
    placed = asset.judge.accept(asset.zone, take, _meta(asset, entry, best), best["scores"], when or now())
    placed.update(refused={"by": "judge", "at": when or now(), "failed": best.get("failed", [])})
    audio = asset.audio()
    section, key = asset.path
    group = audio.setdefault(section, {}).setdefault(key, {"npc": _npc(asset, entry)})
    if asset.kind == "dialogue":
        group.setdefault("page", entry.get("page"))
    group[asset.sex] = placed
    storage.write_json(asset.audio_path, audio)
    return True


def refused_assets(kind: str, zones: list[str] | None = None) -> list[Asset]:
    """The assets of a kind whose loop state says refused or in progress and that keep a best take."""
    out = []
    if kind in ("elise", "book"):
        from tools.books import judge as book_judge
        from tools.elise import judge as elise_judge
        judge = elise_judge if kind == "elise" else book_judge
        for unit, e in ((storage.read_json(judge.STATE) or {}).get("lines") or {}).items():
            if e.get("status") != "ok" and e.get("best") and (zones is None or e.get("zone") in zones):
                out.append(Asset(kind, e["zone"], unit))
        return out
    name = "readings.json" if kind == "reading" else "dialogue_readings.json"
    base = ROOT / "data" / "zones"
    for path in sorted(base.glob(f"**/{name}")):
        zone = str(path.parent.relative_to(base))
        if zones is not None and zone not in zones:
            continue
        for unit, e in ((storage.read_json(path) or {}).get("readings") or {}).items():
            if e.get("status") != "ok" and e.get("best"):
                out.append(Asset(kind, zone, unit))
    return out


def publish_refused(kind: str, zones: list[str] | None = None, log=print) -> int:
    """Every refused audio of a kind in game (inside its loop's actor, or when no writer runs)."""
    count = sum(1 for asset in refused_assets(kind, zones) if publish(asset))
    if count:
        log(f"review: {count} refused {kind}(s) put in game until a take passes")
    return count


# --- the user's decisions ------------------------------------------------------------------------------------

def load() -> dict:
    return storage.read_json(DECISIONS) or {"schema": 1, "decisions": []}


def pending(kind: str | None = None) -> list[dict]:
    return [d for d in load()["decisions"] if d["state"] == "queued" and (kind is None or d["kind"] == kind)]


def delete(asset: Asset) -> str:
    if asset.kind == "voice":
        from tools.voices import redo
        redo.main([asset.unit])
        return "model voice archived, its readings and dialogues deleted: made again by the next passes"
    item = _remove_item(asset)
    if item:
        _game_path(item["file"]).unlink(missing_ok=True)
        if item.get("master"):
            (ROOT / item["master"]).unlink(missing_ok=True)
    state = asset.state()
    entry = state.get(asset.state_key, {}).get(asset.unit)
    if entry:
        best = entry.pop("best", None)
        if best and best.get("take"):
            take = ROOT / best["take"]
            take.unlink(missing_ok=True)
            if take.parent.name == asset.unit:
                shutil.rmtree(take.parent, ignore_errors=True)
        for k in ("status", "seed", "scores"):
            entry.pop(k, None)
        entry["campaign_tries"] = 0
        entry["deleted"] = {"by": "human", "at": now()}
        storage.write_json(asset.state_path, state)
    return "deleted: made again by the next pass"


def validate(asset: Asset) -> str:
    """The asset's best refused take becomes its audio, validated by hand (its scores kept: the judge's view)."""
    state = asset.state()
    entry = state.get(asset.state_key, {}).get(asset.unit) or {}
    best = entry.get("best") or {}
    take = ROOT / best["take"] if best.get("take") else None
    item = asset.item()
    when = now()
    if take and take.is_file():
        placed = asset.judge.accept(asset.zone, take, _meta(asset, entry, best), best["scores"], when)
        scores, seed = best["scores"], best["seed"]
    elif item:  # already in place (a refused take published, or a refused-by-hand audio): keep that one
        placed, scores, seed = dict(item), item.get("scores"), item.get("seed")
    else:
        raise ValueError(f"{asset.kind} {asset.unit}: no take to validate")
    placed.pop("refused", None)
    placed["validated"] = {"by": "human", "at": when, "failed": best.get("failed") or (item or {}).get(
        "refused", {}).get("failed", [])}
    audio = asset.audio()
    section, key = asset.path
    group = audio.setdefault(section, {}).setdefault(key, {"npc": _npc(asset, entry)})
    if asset.kind == "dialogue":
        group.setdefault("page", entry.get("page"))
    group[asset.sex] = placed
    storage.write_json(asset.audio_path, audio)
    if take and take.is_file():
        take.unlink()
        if take.parent.name == asset.unit:
            shutil.rmtree(take.parent, ignore_errors=True)
    entry.pop("best", None)
    entry.update(status="ok", seed=seed, scores=scores, validated={"by": "human", "at": when})
    state.setdefault(asset.state_key, {})[asset.unit] = entry
    storage.write_json(asset.state_path, state)
    return "validated by hand: in place, never made again"


def refuse(asset: Asset) -> str:
    """A validated audio refused by hand: kept in game until a new take passes, made again by the next run."""
    audio = asset.audio()
    section, key = asset.path
    item = ((audio.get(section) or {}).get(key) or {}).get(asset.sex)
    if not item:
        raise ValueError(f"{asset.kind} {asset.unit}: no audio in place to refuse")
    item.pop("validated", None)
    item["refused"] = {"by": "human", "at": now()}
    storage.write_json(asset.audio_path, audio)
    state = asset.state()
    entry = state.setdefault(asset.state_key, {}).setdefault(asset.unit, {})
    entry.pop("validated", None)
    entry.update(status="not_found", campaign_tries=asset.judge.MAX_TRIES, refused={"by": "human", "at": now()})
    storage.write_json(asset.state_path, state)
    return "refused by hand: still played until a new take passes, made again by the next run"


def _apply(decision: dict) -> tuple[str, str]:
    """(state, note) of a decision once tried."""
    if running(WRITERS[decision["kind"]]):
        return "queued", f"waiting for {', '.join(running(WRITERS[decision['kind']]))} to finish"
    if decision["action"] in ("validate", "refuse") and decision["kind"] not in HONOURED:
        return "queued", "waiting for the loops' update (oracle and judge resealed)"
    asset = Asset(decision["kind"], decision.get("zone"), decision["unit"])
    if decision["action"] == "delete":
        return "applied", delete(asset)
    try:
        return "applied", (validate if decision["action"] == "validate" else refuse)(asset)
    except ValueError as err:
        return "failed", str(err)


def decide(kind: str, zone: str | None, unit: str, action: str) -> dict:
    """Records a decision (the latest one on an asset replaces a queued one) and applies it when it can."""
    if kind not in KINDS or action not in ACTIONS:
        raise ValueError(f"unknown kind or action: {kind} {action}")
    data = load()
    data["decisions"] = [d for d in data["decisions"]
                         if not (d["state"] == "queued" and (d["kind"], d.get("zone"), d["unit"]) == (kind, zone, unit))]
    decision = {"kind": kind, "zone": zone, "unit": unit, "action": action, "at": now(), "state": "queued"}
    decision["state"], decision["note"] = _apply(decision)
    if decision["state"] == "applied":
        decision["applied_at"] = now()
    data["decisions"].append(decision)
    storage.write_json(DECISIONS, data)
    if decision["state"] == "applied" and kind != "voice":
        from pipeline import build_index
        build_index.main([])
    return decision


def cancel(kind: str, zone: str | None, unit: str) -> bool:
    """Withdraws a decision still waiting in the queue."""
    data = load()
    kept = [d for d in data["decisions"]
            if not (d["state"] == "queued" and (d["kind"], d.get("zone"), d["unit"]) == (kind, zone, unit))]
    if len(kept) == len(data["decisions"]):
        return False
    data["decisions"] = kept
    storage.write_json(DECISIONS, data)
    return True


def apply_pending(kinds: tuple[str, ...] = KINDS, log=print) -> int:
    """Applies the queued decisions that can be (run.sh of each loop calls it before its run)."""
    data, applied = load(), 0
    for decision in data["decisions"]:
        if decision["state"] != "queued" or decision["kind"] not in kinds:
            continue
        decision["state"], decision["note"] = _apply(decision)
        if decision["state"] == "applied":
            decision["applied_at"] = now()
            applied += 1
            log(f"review: {decision['action']} {decision['kind']} {decision.get('zone') or ''} {decision['unit']}: "
                f"{decision['note']}")
    if applied:
        storage.write_json(DECISIONS, data)
        from pipeline import build_index
        build_index.main([])
    return applied


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("publish")
    p.add_argument("--kind", choices=("reading", "dialogue", "elise", "book"), action="append")
    a = sub.add_parser("apply")
    a.add_argument("--kind", choices=KINDS, action="append")
    args = ap.parse_args(argv)
    if args.cmd == "apply":
        print(f"review: {apply_pending(tuple(args.kind or KINDS))} decision(s) applied, "
              f"{len(pending())} waiting")
        return 0
    total = 0
    for kind in args.kind or ("reading", "dialogue", "elise", "book"):
        busy = running(WRITERS[kind])
        if busy:
            print(f"review: {kind}: {', '.join(busy)} running, its actor publishes them", file=sys.stderr)
            continue
        total += publish_refused(kind)
    if total:
        from pipeline import build_index
        build_index.main([])
    print(f"review: {total} refused audio(s) put in game")
    return 0


if __name__ == "__main__":
    sys.exit(main())
