"""Progress of a running loop, for the dashboard (tools/loop/dashboard.py). Display only: no oracle, judge or arbiter
reads it, and a write that fails never stops a loop. Standard library only (written from .venv and .venv-voices).

Files in data/cache/loops/<pass>/progress/, one writer each:
- loop.json   the engine: scope, start, attempt, zone, items left at start and now, state (acting, waiting...);
- actor.json  the actor: the zone's takes of this attempt, how many are generated and judged, the phase;
- slots.json  the generator: the batch of takes generated together (--parallel), each with its expected time;
- rates.json  the generator: learned rates (characters per audio second; wall seconds per audio second of a
              batch's longest take, by batch size), so that the next run estimates from the first batch.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

CPS = 14.0  # characters of French text per audio second, before anything is learned
WALL = 1.2  # wall seconds per audio second of a batch's longest take, before anything is learned (RTX 4090)
EMA = 0.3  # weight of the newest batch in the learned rates


def folder(name: str, root: Path = ROOT) -> Path:
    return root / "data" / "cache" / "loops" / name / "progress"


def read(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def write(path: Path, data: dict) -> None:
    """Atomic (the dashboard never reads half a file); never raises."""
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(f".{path.name}.{os.getpid()}")
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        os.replace(tmp, path)
    except OSError:
        pass


class Record:
    """One progress file, updated field by field."""

    def __init__(self, path: Path, **fields):
        self.path, self.data = path, {}
        self.update(**fields)

    def update(self, **fields) -> None:
        self.data.update(fields, pid=os.getpid(), updated=time.time())
        write(self.path, self.data)

    def add(self, key: str, n: int = 1) -> None:
        self.update(**{key: self.data.get(key, 0) + n})


def actor(name: str, zones: list[str], root: Path = ROOT) -> Record:
    """The actor's record for this attempt, a round over these categories (its counters start at 0)."""
    return Record(folder(name, root) / "actor.json", zones=list(zones), started=time.time(), phase="starting",
                  takes=0, generated=0, judged=0, ok=0, failed=0, not_found=0)


class Rates:
    """Expected generation time of a take, learned from the batches already generated."""

    def __init__(self, path: Path):
        self.path = path
        data = read(path)
        self.cps = float(data.get("cps", CPS))
        self.wall = {int(k): float(v) for k, v in (data.get("wall") or {}).items()}

    def wall_for(self, batch: int) -> float:
        if batch in self.wall:
            return self.wall[batch]
        if self.wall:  # the nearest batch size learned
            return self.wall[min(self.wall, key=lambda b: abs(b - batch))]
        return WALL

    def expect(self, chars: int, batch: int) -> float:
        """Wall seconds to generate `chars` characters in a batch of `batch` takes."""
        return self.wall_for(batch) * max(chars, 1) / self.cps

    def learn(self, chars: list[int], audio: list[float], longest: int, wall: float, batch: int) -> None:
        """A batch is done: `chars` and `audio` (seconds) of each take, the characters of the longest text generated
        (one paragraph for a reading), and the batch's wall time."""
        if sum(audio) > 0 and sum(chars) > 0:
            self.cps = (1 - EMA) * self.cps + EMA * sum(chars) / sum(audio)
        if longest > 0 and wall > 0:
            seen = wall / (longest / self.cps)
            self.wall[batch] = seen if batch not in self.wall else (1 - EMA) * self.wall[batch] + EMA * seen
        write(self.path, {"cps": round(self.cps, 3), "wall": {str(k): round(v, 3) for k, v in self.wall.items()}})


class Slots:
    """The generator's side: the batch being generated, one slot per take."""

    def __init__(self, name: str, parallel: int, total: int, root: Path = ROOT):
        self.rates = Rates(folder(name, root) / "rates.json")
        self.record = Record(folder(name, root) / "slots.json", parallel=parallel, total=total, done=0, batch=0,
                             batches=-(-total // max(parallel, 1)), slots=[], loading=True)
        self.started = 0.0

    def start(self, items: list[dict]) -> None:
        """A batch starts: items [{"label", "chars" (the longest text generated for it), "text_chars"}]."""
        self.started = time.time()
        self.items = items
        n = len(items)
        slots = [{"label": i["label"], "expected": round(self.rates.expect(i["chars"], n), 1)} for i in items]
        self.record.update(loading=False, batch=self.record.data["batch"] + 1, batch_started=self.started,
                           slots=slots)

    def finish(self, audio: list[float]) -> None:
        """The batch is done: the audio seconds of each take."""
        wall = time.time() - self.started
        self.rates.learn([i["text_chars"] for i in self.items], audio, max(i["chars"] for i in self.items), wall,
                         len(self.items))
        self.record.update(done=self.record.data["done"] + len(self.items), last_batch_s=round(wall, 1),
                           slots=[{**s, "audio": round(a, 1)} for s, a in zip(self.record.data["slots"], audio)],
                           batch_started=None)


def alive(pid) -> bool:
    try:
        os.kill(int(pid), 0)
    except (OSError, TypeError, ValueError):
        return False
    return True
