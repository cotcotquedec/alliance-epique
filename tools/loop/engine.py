"""The loop: PLAN -> ACT -> ARBITRATE -> CRITIQUE, then back to PLAN with a fresh context.

- PLAN: the oracle names the next zone; the files an attempt may change are snapshotted.
- ACT: the pass's actor (tools/<pass>/actor.sh <zone>) does one task: one zone. Its output is shown live
  and kept in logs/.
- ARBITRATE: the seal is checked, the oracle asked again, the arbiter applied against the ratchet:
  commit (the ratchet tightens), wait, retry, stop, or rollback (snapshot restored, the attempt's files
  put in quarantine).
- CRITIQUE: the pass's critic writes what is missing in the backlog; it decides nothing.
Nothing is carried from one attempt to the next but the ratchet, the arbiter's counters and the oracle's
last answer: each actor run is a new process.

The loop only writes in its run folder (data/cache/loops/<pass>/: logs, journal, last.json, backlog,
quarantine, snapshot) and, through the ratchet code, ratchet.json. See tools/loop/README.md.
"""

from __future__ import annotations

import collections
import json
import os
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Callable

from pipeline import storage
from tools.loop import arbiter, progress, ratchet, seal
from tools.loop.arbiter import Rules, State

TAIL_LINES = 200  # output lines kept for the arbiter and the critic

EXIT_DONE, EXIT_ORACLE, EXIT_STOP, EXIT_LOSS, EXIT_SEAL = 0, 1, 2, 3, 4


@dataclass(frozen=True)
class Pass:
    name: str  # "base", "text", "voices", "readings", "elise", "dialogues" or "books": tools/<name>/
    sealed: tuple[str, ...]  # read-only objects, repo-relative
    tracked: tuple[str, ...]  # globs (repo-relative) of the files an attempt may change: snapshot and rollback
    oracle: Callable[[], dict]  # {"done": bool, "next": zone | None, "level": {counter: int}}
    rules: Rules
    critic: Callable[[str, int, str, dict, Path], None]  # (zone, exit code, output tail, oracle answer, run dir)

    @property
    def actor(self) -> str:
        return f"tools/{self.name}/actor.sh"

    @property
    def seal(self) -> str:
        return f"tools/{self.name}/SEAL"


def focus(answer: dict, zones: list[str] | None) -> dict:
    """The oracle's answer limited to some categories (their keys, "eastern-kingdoms/elwynn-forest", from the run's
    scope: tools/loop/scope.py): the next one is the first of them still to do, and the goal is reached when none
    is left. The level stays global. None: every category."""
    if zones is None:
        return answer
    wanted = [k for k in answer.get("todo", []) if k in zones]
    return {**answer, "done": not wanted, "next": wanted[0] if wanted else None, "todo": wanted}


def run_dir_of(spec: Pass, root: Path = storage.REPO_ROOT) -> Path:
    return root / "data" / "cache" / "loops" / spec.name


# --- progress, for the dashboard (tools/loop/dashboard.py) ----------------------------------------------

UNITS = {"voices": "NPCs", "readings": "readings", "elise": "lines", "dialogues": "pages", "books": "book pages"}  # what `remaining` counts; else categories
ROUND = 200  # voices, readings: items to do in one round, several categories (--round, environment FS_ROUND_TAKES)


def zone_counts(name: str, todo: list[str]) -> dict[str, int]:
    """Items still to do in each of these categories (voices: NPCs, readings: readings); {} for the other passes."""
    if name == "voices":
        from tools.voices import judge as voice_judge, oracle as voice_oracle
        voices = json.loads(voice_judge.VOICES_FILE.read_text(encoding="utf-8"))["npcs"]
        return {k: len(voice_oracle.pending(k, voices)) for k in todo}
    if name == "readings":
        from tools.readings import oracle as reading_oracle
        voices = json.loads(reading_oracle.voice_oracle.judge.VOICES_FILE.read_text(encoding="utf-8"))["npcs"]
        return {k: len(reading_oracle.zone_readings(k, voices)["todo"]) for k in todo}
    if name == "dialogues":
        from tools.dialogues import oracle as dialogue_oracle
        voices = json.loads(dialogue_oracle.reading_oracle.voice_oracle.judge.VOICES_FILE.read_text(encoding="utf-8"))["npcs"]
        return {k: len(dialogue_oracle.zone_dialogues(k, voices)["todo"]) for k in todo}
    if name == "books":
        from tools.books import judge as book_judge, oracle as book_oracle
        voice, state = book_judge.voice_id(), book_judge._read(book_judge.STATE, {"lines": {}})
        return {k: len(book_oracle.zone_pages(k, voice, state)["todo"]) for k in todo}
    if name == "elise":
        from tools.elise import judge as elise_judge, oracle as elise_oracle
        voice, state = elise_judge.voice_id(), elise_judge._read(elise_judge.STATE, {"lines": {}})
        return {k: len(elise_oracle.zone_lines(k, voice, state)["todo"]) for k in todo}
    return {}


def remaining(name: str, answer: dict, zones: list[str] | None) -> int:
    """Items still to do in the run's scope: the oracle's `remaining` for every category, else counted again in
    the categories of the scope (voices, readings), else the categories left."""
    todo = answer.get("todo") or []
    try:
        if zones is None and "remaining" in answer:
            return int(answer["remaining"])
        return sum(zone_counts(name, todo).values()) if name in UNITS else len(todo)
    except Exception:  # display only: never stops the loop
        return len(todo)


def round_of(name: str, answer: dict, budget: int | None = None) -> list[str]:
    """The categories of the next attempt. Voices and readings: the oracle's categories in order, until about
    `budget` items (always at least one category), so that a round fills the GPU's batches and the models load once
    for many categories; the other passes: the oracle's next category alone."""
    if name not in UNITS:
        return [answer["next"]]
    budget = budget or int(os.environ.get("FS_ROUND_TAKES") or ROUND)
    todo = answer.get("todo") or [answer["next"]]
    counts = zone_counts(name, todo)
    picked, items = [], 0
    for key in todo:
        if picked and items + counts.get(key, 0) > budget:
            break
        picked.append(key)
        items += counts.get(key, 0)
    return picked


# --- PLAN / rollback: snapshot of the tracked files -----------------------------------------------------


def _tracked(root: Path, patterns: tuple[str, ...]) -> dict[str, Path]:
    return {str(p.relative_to(root)): p for pattern in patterns for p in sorted(root.glob(pattern)) if p.is_file()}


def snapshot(root: Path, patterns: tuple[str, ...], dest: Path) -> None:
    shutil.rmtree(dest, ignore_errors=True)
    for rel, path in _tracked(root, patterns).items():
        (dest / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest / rel)


def rollback(root: Path, patterns: tuple[str, ...], snap: Path, quarantine: Path) -> list[str]:
    """Puts the files the attempt changed or created in quarantine, then restores the snapshot. Returns them."""
    saved = {str(p.relative_to(snap)): p for p in snap.rglob("*") if p.is_file()}
    changed = []
    for rel, path in _tracked(root, patterns).items():
        if rel not in saved or saved[rel].read_bytes() != path.read_bytes():
            (quarantine / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, quarantine / rel)
            changed.append(rel)
            if rel not in saved:
                path.unlink()
    for rel, path in saved.items():
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, root / rel)
    return changed


# --- ACT ----------------------------------------------------------------------------------------------


def run_actor(cmd: list[str], log_path: Path, cwd: Path, echo=None) -> tuple[int, str]:
    """Runs the actor, shows its output live and keeps it in `log_path`; (exit code, output tail)."""
    echo = echo or sys.stdout
    tail: collections.deque[str] = collections.deque(maxlen=TAIL_LINES)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, "PYTHONUNBUFFERED": "1"}  # live output from the Python steps
    with open(log_path, "w", encoding="utf-8") as log, subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1, cwd=cwd, env=env,
            errors="replace") as proc:
        for line in proc.stdout:
            echo.write(line)
            echo.flush()
            log.write(line)
            log.flush()
            tail.append(line)
    return proc.returncode, "".join(tail)


# --- the loop -----------------------------------------------------------------------------------------


def _stamp(t: datetime) -> str:
    return t.isoformat(timespec="seconds")


def run(spec: Pass, state: State = State(), root: Path = storage.REPO_ROOT, run_dir: Path | None = None,
        act: Callable[[str, Path], tuple[int, str]] | None = None, sleep=time.sleep,
        clock=lambda: datetime.now().astimezone(), say=print, zones: list[str] | None = None,
        reset_ratchet: bool = False, label: str = "") -> int:
    """Runs the loop of a pass; returns the process exit code (EXIT_DONE: the goal is reached). `zones`:
    only these categories (keys; the goal is then reached when they are done). `reset_ratchet`: the ratchet starts again
    from the level at launch (a drop the human wants, or counters that changed); otherwise a level below it
    stops the loop (data lost between two runs). `label`: what the run covers, for the dashboard."""
    run_dir = run_dir or run_dir_of(spec, root)
    os.environ["FS_LOOP_PID"] = str(os.getpid())  # the actors' model server lives as long as this loop
    board = progress.Record(run_dir / "progress" / "loop.json", **{
        "pass": spec.name, "scope": label, "started": time.time(), "state": "starting", "attempt": 0,
        "max_attempts": state.max_attempts, "unit": UNITS.get(spec.name, "categories"),
        "parallel": os.environ.get("FS_TTS_BATCH") or "auto", "round": os.environ.get("FS_ROUND_TAKES") or ROUND,
        "npcs": os.environ.get("FS_NPCS") or None})
    try:
        code = _run(spec, state, root, run_dir, act, sleep, clock, say, zones, reset_ratchet, board)
    except BaseException:
        board.update(state="interrupted")
        raise
    board.update(state={EXIT_DONE: "done"}.get(code, "stopped"), exit_code=code)
    return code


def _run(spec, state, root, run_dir, act, sleep, clock, say, zones, reset_ratchet, board) -> int:
    def ask() -> dict:
        return focus(spec.oracle(), zones)

    run_dir.mkdir(parents=True, exist_ok=True)
    ratchet_path = run_dir / "ratchet.json"
    # the actor gets the round's categories (one, except for voices and readings: round_of)
    act = act or (lambda zone, log: run_actor([str(root / spec.actor), *zone.split()], log, root))

    def journal(record: dict) -> None:
        storage.write_json(run_dir / "last.json", record)
        with open(run_dir / "journal.jsonl", "a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")

    def sealed_ok() -> bool:
        problems = seal.check(root / spec.seal, list(spec.sealed), root)
        for p in problems:
            say(f"{spec.name} loop: SEAL BROKEN, {p}")
        if problems:
            say(f"{spec.name} loop: review the read-only objects, then: tools/loop/seal.sh {spec.name}")
        return not problems

    if not sealed_ok():
        return EXIT_SEAL
    try:
        answer = ask()
    except Exception as err:  # any oracle failure stops the loop
        say(f"{spec.name} loop: STOPPED, the oracle failed: {err}")
        return EXIT_ORACLE
    if reset_ratchet and ratchet_path.exists():
        say(f"{spec.name} loop: ratchet reset, was {ratchet.load(ratchet_path)}; starts again at {answer['level']}")
        ratchet_path.unlink()
    reference = ratchet.load(ratchet_path)
    if reference and arbiter.dropped(reference, answer["level"]):
        say(f"{spec.name} loop: STOPPED, DATA LOSS since the last run: level {answer['level']} below the ratchet "
            f"{reference} ({ratchet_path}). Check data/ (git diff); if the drop is wanted, rerun with "
            "--reset-ratchet.")
        return EXIT_LOSS
    reference = ratchet.tighten(ratchet_path, answer["level"], _stamp(clock()))
    left = remaining(spec.name, answer, zones)
    board.update(remaining_start=left, remaining=left, level_start=answer["level"], level=answer["level"],
                 zones_left=len(answer.get("todo") or []))
    if answer["done"]:
        say(f"{spec.name} loop: nothing to do, goal reached at {reference}")
        return EXIT_DONE

    while True:
        # PLAN
        targets = round_of(spec.name, answer)
        zone = " ".join(targets)
        started = clock()
        tag = f"{started.strftime('%Y%m%d-%H%M%S')}-attempt-{state.attempt + 1}"
        log_path = run_dir / "logs" / f"{tag}.log"
        snapshot(root, spec.tracked, run_dir / "snapshot")
        board.update(state="acting", attempt=state.attempt + 1, zone=targets[0], zones=targets,
                     attempt_started=time.time(), resume_at=None)
        shown = targets[0] if len(targets) == 1 else f"{targets[0]} and {len(targets) - 1} more categories"
        say(f"\n{spec.name} loop: attempt {state.attempt + 1}/{state.max_attempts}, zone {shown}, "
            f"ratchet {reference}, log {log_path.relative_to(root) if log_path.is_relative_to(root) else log_path}")
        # ACT
        code, tail = act(zone, log_path)
        # ARBITRATE
        record = {"pass": spec.name, "attempt": state.attempt + 1, "zone": targets[0],
                  **({"zones": targets} if len(targets) > 1 else {}), "started": _stamp(started),
                  "exit_code": code, "ratchet_before": reference, "log": str(log_path)}
        if not sealed_ok():
            journal({**record, "action": "stop", "reason": "seal broken during the attempt"})
            return EXIT_SEAL
        try:
            after = ask()
        except Exception as err:
            say(f"{spec.name} loop: STOPPED, the oracle failed after attempt {state.attempt + 1}: {err}")
            journal({**record, "action": "stop", "reason": f"oracle failed: {err}"})
            return EXIT_ORACLE
        now = clock()
        action, wait, reason = arbiter.decide(code, reference, after, tail, state, now, spec.rules)
        state = arbiter.next_state(state, code, reference, after, spec.rules)
        quarantined = None
        if action in ("rollback", "stop"):  # what was not settled goes up to the human
            quarantine = run_dir / "quarantine" / tag
            quarantine.mkdir(parents=True, exist_ok=True)
            if log_path.exists():
                shutil.copy2(log_path, quarantine / log_path.name)
            if action == "rollback":
                quarantined = rollback(root, spec.tracked, run_dir / "snapshot", quarantine / "files")
            (quarantine / "reason.txt").write_text(reason + "\n", encoding="utf-8")
        else:  # commit: the ratchet tightens
            reference = ratchet.tighten(ratchet_path, after["level"], _stamp(now))
        # CRITIQUE
        for target in targets:
            try:
                spec.critic(target, code, tail, after, run_dir)
            except Exception as err:  # the critic never blocks the loop
                say(f"{spec.name} loop: critic failed on {target}: {err}")
        resume = _stamp(now + timedelta(seconds=wait)) if action in ("retry", "wait") else None
        journal({**record, "finished": _stamp(now), "level_after": after["level"], "next": after["next"],
                 "action": action, "wait_s": wait, "reason": reason, "resume_at": resume,
                 "rolled_back": quarantined, "ratchet_after": reference, "counters": asdict(state)})
        board.update(state="waiting" if wait and action in ("retry", "wait") else "arbitrated", action=action,
                     reason=reason, resume_at=resume, level=after["level"], zones_left=len(after.get("todo") or []),
                     remaining=remaining(spec.name, after, zones))
        say(f"{spec.name} loop: exit {code} -> {action}: {reason}" + (f"; next attempt at {resume}" if resume else ""))
        if action == "done":
            return EXIT_DONE
        if action == "rollback":
            return EXIT_LOSS
        if action == "stop":
            return EXIT_STOP
        sleep(wait)
        answer = after
