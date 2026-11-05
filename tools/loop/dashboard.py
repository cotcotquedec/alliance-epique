"""Dashboard of a running loop: the whole run, the current category, and each take of the batch being generated
(--parallel), redrawn every second. Reads only the progress files (tools/loop/progress.py); run it beside the loop,
in another terminal or tmux pane. Ctrl-C quits the dashboard, never the loop.

    tools/loop/dashboard.sh [voices|readings|dialogues|elise|books|text|base] [--once]     (default: the loop updated last)
"""

from __future__ import annotations

import argparse
import shutil
import sys
import time
from datetime import datetime

from tools.loop import progress

PASSES = ("voices", "readings", "dialogues", "elise", "books", "text", "base")


def clock(seconds: float | None) -> str:
    if seconds is None or seconds < 0:
        return "--:--:--"
    s = int(seconds)
    return f"{s // 3600:02d}:{s % 3600 // 60:02d}:{s % 60:02d}"


def bar(fraction: float, width: int) -> str:
    cells = min(max(fraction, 0.0), 1.0) * width
    full, eighths = int(cells), int((cells - int(cells)) * 8)
    return "[" + ("█" * full + ("▏▎▍▌▋▊▉"[eighths - 1] if eighths and full < width else "")).ljust(width, "·") + "]"


def pct(done: float, total: float) -> float:
    return done / total if total else 0.0


def latest() -> str:
    found = [(progress.read(progress.folder(p) / "loop.json").get("updated", 0), p) for p in PASSES]
    return max(found)[1]


def render(name: str, now: float, width: int = 100) -> list[str]:
    """The dashboard's lines, from the progress files of a pass."""
    folder = progress.folder(name)
    loop, actor, slots = (progress.read(folder / f) for f in ("loop.json", "actor.json", "slots.json"))
    if not loop:
        return [f"{name} loop: never run with progress (data/cache/loops/{name}/progress/loop.json missing)"]
    width = max(width, 60)
    wide = width - 50
    running = loop.get("state") in ("starting", "acting", "waiting", "arbitrated") and progress.alive(loop.get("pid"))
    state = loop.get("state", "?") if running or loop.get("state") in ("done", "stopped", "interrupted") \
        else "not running (killed?)"
    end = now if running else loop.get("updated", now)
    lines = [f"{name} loop {loop.get('scope', '')}".rstrip()
             + f"   parallel {slots.get('parallel') or loop.get('parallel', '?')}"
             + (f"   round ~{loop['round']}" if loop.get("round") else "")
             + (f"   NPCs {loop['npcs']}" if loop.get("npcs") else ""),
             f"elapsed {clock(end - loop.get('started', end))}   state {state}"
             + (f" (exit {loop['exit_code']})" if "exit_code" in loop else "")
             + (f", next attempt at {loop['resume_at'][11:19]}" if loop.get("resume_at") and running else ""),
             ""]
    for at, role in enumerate(("qwen", "ears"), 2):  # the model servers of this run (tools/qwen_voices/server.py)
        models = progress.read(folder / f"models-{role}.json")
        if not models or models.get("loop_pid") != str(loop.get("pid")):
            continue
        up = progress.alive(models.get("pid")) and models.get("state") != "stopped"
        lines.insert(at, f"{'models' if role == 'qwen' else '':<9} {models.get('engine', '')} " + (
            f"loaded once in {models['ready'] - models['started']:.0f}s, {models.get('requests', 0)} requests"
            if up and models.get("state") == "ready" else
            f"loading... {clock(now - models.get('started', now))}" if up else "server stopped"))

    # the whole run: items settled since the start, live within the current attempt
    started_attempt = loop.get("attempt_started") or 0
    current = actor if actor.get("started", 0) >= started_attempt and loop.get("state") == "acting" else {}
    total = loop.get("remaining_start", 0)
    settled = max(total - loop.get("remaining", total), 0) + current.get("ok", 0) + current.get("not_found", 0)
    settled = min(settled, total)
    spent = end - loop.get("started", end)
    eta = spent * (total - settled) / settled if settled else None
    unit = loop.get("unit", "items")
    lines.append(f"run       {bar(pct(settled, total), wide)} {settled}/{total} {unit} {pct(settled, total):5.0%}"
                 f"   left ~{clock(eta)}" if total else f"run       nothing to do at start ({unit})")
    lvl, lvl0 = loop.get("level") or {}, loop.get("level_start") or {}
    if "tries" in lvl:
        lines.append(f"          takes judged {lvl.get('tries', 0) - lvl0.get('tries', 0) + current.get('judged', 0)}"
                     f" this run; attempt {loop.get('attempt', 0)}, {loop.get('zones_left', '?')} categories left")

    # the current category: its takes, generated then judged
    if current:
        takes = current.get("takes", 0)
        fresh = slots.get("updated", 0) >= started_attempt  # the generator of this attempt (readings: its own process)
        generated = max(current.get("generated", 0), slots.get("done", 0) if fresh else 0)
        targets = current.get("zones") or [loop.get("zone", "?")]
        where = targets[0] if len(targets) == 1 else f"{len(targets)} categories, {targets[0]} … {targets[-1]}"
        lines += ["", f"round     {where}: {current.get('phase', '?')}, {clock(now - current['started'])}"]
        if takes:
            lines.append(f"generated {bar(pct(generated, takes), wide)} {generated}/{takes} takes")
            lines.append(f"judged    {bar(pct(current.get('judged', 0), takes), wide)} {current.get('judged', 0)}/"
                         f"{takes}: {current.get('ok', 0)} kept, {current.get('failed', 0)} failed, "
                         f"{current.get('not_found', 0)} not found")
    elif loop.get("state") == "acting":
        lines += ["", f"round     {loop.get('zone', '?')}: starting"]

    # the batch: one bar per take generated together
    if current and slots.get("updated", 0) >= started_attempt:
        if slots.get("loading"):
            lines += ["", "batch     loading the model..."]
        elif slots.get("slots"):
            began = slots.get("batch_started")
            age = now - began if began else None
            lines += ["", f"batch {slots.get('batch', 0)}/{slots.get('batches', 0)}"
                          + (f"   {clock(age)}" if began else f"   done in {slots.get('last_batch_s', 0):.0f}s")]
            label_w = max(min(max(len(s["label"]) for s in slots["slots"]), 34), 10)
            slot_w = max(width - label_w - 26, 10)
            for i, s in enumerate(slots["slots"], 1):
                expected = s.get("expected") or 1
                if began:  # an estimate: the batch gives every take at once, when the longest is done
                    f = min(age / expected, 0.99)
                    tail = f"{f:4.0%} ~{max(expected - age, 0):4.0f}s"
                else:
                    f, tail = 1.0, f"done {s.get('audio', 0):5.1f}s"
                lines.append(f"{i:>2} {s['label'][:label_w]:<{label_w}} {bar(f, slot_w)} {tail}")
    lines += ["", f"updated {datetime.fromtimestamp(now).strftime('%H:%M:%S')}  (Ctrl-C quits the dashboard, "
                  "not the loop)"]
    return lines


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="tools/loop/dashboard.sh", description=__doc__.split("\n")[0])
    ap.add_argument("name", nargs="?", choices=PASSES, metavar="pass", help="voices, readings, dialogues, elise, books, text or base")
    ap.add_argument("--once", action="store_true", help="print once and quit")
    ap.add_argument("--every", type=float, default=1.0, help="seconds between two refreshes (default 1)")
    args = ap.parse_args(argv)
    if args.once:
        print("\n".join(render(args.name or latest(), time.time(), shutil.get_terminal_size().columns)))
        return 0
    out = sys.stdout
    out.write("\x1b[?25l\x1b[2J")  # hide the cursor, clear once
    try:
        while True:
            size = shutil.get_terminal_size()
            lines = render(args.name or latest(), time.time(), size.columns)[:size.lines - 1]
            out.write("\x1b[H" + "".join(line[:size.columns] + "\x1b[K\n" for line in lines) + "\x1b[J")
            out.flush()
            time.sleep(args.every)
    except KeyboardInterrupt:
        return 0
    finally:
        out.write("\x1b[?25h")
        out.flush()


if __name__ == "__main__":
    sys.exit(main())
