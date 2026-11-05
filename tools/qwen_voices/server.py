"""Model servers of a voice or readings loop run (2026-10-08): load the models once, at the start of the run, and
serve the actors of every round, so that no round reloads them (the actors stay new processes, as the loop wants).
Two servers per pass, two processes, so that generating and judging run side by side without sharing one Python
interpreter (in one process they slowed each other down: 6 readings a minute, the server on one core at 100 %):
- qwen: Qwen3-TTS, VoiceDesign for voices (tools/qwen_voices/frame.py), Base for readings (tools/readings/frame.py);
- ears: the judge's models, Whisper for voices (tools/voices/judge.py), Whisper and ECAPA for readings
  (tools/readings/judge.py).
The judges' own sealed classes are loaded here and called unchanged: only where they run changes.

Unix socket data/cache/loops/<pass>/models-<role>.sock (multiprocessing.connection, one thread per client). PyTorch's
memory is capped below the GPU's (MEMORY_FRACTION), else WSL2 spills it to system memory and every batch crawls.
Started by the first actor of a run that needs it (`connect`, only inside a loop: FS_LOOP_PID set by
tools/loop/engine.py); stops by itself when that loop process is gone. Its state is in
data/cache/loops/<pass>/progress/models-<role>.json (dashboard), its output in logs/models-<role>-<time>.log.

    .venv-voices/bin/python -m tools.qwen_voices.server voices|readings|dialogues qwen|ears  (normally started by connect)
"""

from __future__ import annotations

import os
import subprocess
import sys
import threading
import time
from multiprocessing.connection import Client, Listener
from pathlib import Path

from tools.loop import progress

AUTH = b"foreverspeech-models"
PASSES = ("voices", "readings", "dialogues")
ROLES = ("qwen", "ears")
START_TIMEOUT = 15 * 60  # first run: the weights may still be downloading
# PyTorch's allocator, in the server's environment unless already set. Without it, on WSL2 the cached blocks of
# successive batches grow past the GPU's 24 GB and the driver spills to system memory instead of failing: measured
# 2026-10-08 (RTX 4090, readings, 8 takes together): 381 s per batch; 32 s with these settings and the cache emptied
# per batch (at most 19.8 GB with the judge's models). Not expandable_segments: on WSL2 it fails after a few rounds
# (INTERNAL ASSERT FAILED "!handles_.at(i)" in CUDACachingAllocator.cpp).
ALLOC_CONF = "garbage_collection_threshold:0.8,max_split_size_mb:256"
# Share of the GPU each server's PyTorch may hold, cached blocks included: at the cap it frees its cache and retries,
# where WSL2 would spill to system memory without a word. Same batch of 8 readings: 291 s uncapped (28 GB reserved for
# 8 GB used), 25 s capped. qwen: 8 samples at most per call (backend.SAMPLES), 8 GB used; ears: ECAPA only, Whisper
# runs on CTranslate2, outside PyTorch (about 4 GB). ECAPA on a long take needs about 3 GB (0.1, 2.4 GB: out of memory
# on the same take every round, 2026-10-08).
MEMORY_FRACTION = {"qwen": 0.5, "ears": 0.2}


def socket_path(name: str, role: str, root: Path = progress.ROOT) -> Path:
    return root / "data" / "cache" / "loops" / name / f"models-{role}.sock"


def state_file(name: str, role: str) -> Path:
    return progress.folder(name) / f"models-{role}.json"


# --- server ---------------------------------------------------------------------------------------------


class Models:
    """The models of one role of a pass, one call at a time."""

    def __init__(self, name: str, role: str):
        from tools.qwen_voices import backend
        self.name, self.role, self.lock = name, role, threading.Lock()
        self.voices = {}  # (ref wav, ref text) -> model voice prepared for cloning
        if name == "voices":
            from tools.qwen_voices.frame import REPO
            from tools.voices import judge as voice_judge
            repo, ears = REPO, voice_judge.Whisper
        else:
            from tools.readings import frame, judge as reading_judge
            repo, ears = frame.REPO, reading_judge.Ears
        if role == "qwen":
            self.qwen = backend.Qwen(repo)
            self.engine = self.qwen.engine
        else:
            self.ears = ears()
            self.engine = f"judge ({backend.torch_device()})"
        import torch
        if torch.cuda.is_available():
            torch.cuda.set_per_process_memory_fraction(MEMORY_FRACTION[role])

    def release(self):
        """Gives the batch's cached GPU memory back (see ALLOC_CONF), so that the next batch fits."""
        import torch
        if torch.cuda.is_available():
            torch.cuda.empty_cache()

    def design_many(self, items, language, temperature, seed):
        with self.lock:
            try:
                return self.qwen.design_many(items, language, temperature, seed)
            finally:
                self.release()

    def clone_many(self, jobs, language, seed, gap, max_tokens):
        """jobs: [(paragraphs, (ref wav, ref text))]; each model voice is prepared once for the whole run."""
        with self.lock:
            for _, ref in jobs:
                if ref not in self.voices:
                    self.voices[ref] = self.qwen.voice(*ref)
            try:
                return self.qwen.clone_many([(p, self.voices[ref]) for p, ref in jobs], language, seed, gap,
                                            max_tokens)
            finally:
                self.release()

    def hear(self, path):
        with self.lock:
            return self.ears.hear(Path(path))

    def scores(self, take, text, model_voice):
        with self.lock:
            return self.ears.scores(Path(take), text, Path(model_voice))


def serve(name: str, role: str) -> int:
    loop_pid = os.environ.get("FS_LOOP_PID")
    state = progress.Record(state_file(name, role), state="loading", started=time.time(), loop_pid=loop_pid)
    models = Models(name, role)
    path = socket_path(name, role)
    path.unlink(missing_ok=True)
    listener = Listener(str(path), family="AF_UNIX", authkey=AUTH)
    state.update(state="ready", ready=time.time(), engine=models.engine)
    print(f"models server ({role}): ready on {path} ({models.engine})", flush=True)

    def watch():  # the loop that started the server is gone: stop
        while loop_pid is None or progress.alive(loop_pid):
            time.sleep(5)
        print(f"models server ({role}): the loop is gone, stopping", flush=True)
        state.update(state="stopped")
        path.unlink(missing_ok=True)
        os._exit(0)

    def client(conn):
        with conn:
            while True:
                try:
                    op, args = conn.recv()
                except (EOFError, OSError):
                    return
                try:
                    conn.send(("ok", loop_pid if op == "ping" else getattr(models, op)(*args)))
                except Exception as err:  # noqa: BLE001 - sent back to the actor, which fails its round
                    conn.send(("error", f"{type(err).__name__}: {err}"))
                state.add("requests")

    threading.Thread(target=watch, daemon=True).start()
    while True:
        threading.Thread(target=client, args=(listener.accept(),), daemon=True).start()


# --- client ---------------------------------------------------------------------------------------------


class Remote:
    """A connection to one of the run's model servers; thread-safe (one call at a time per connection: give each
    thread its own Remote)."""

    def __init__(self, name: str, role: str):
        self.name, self.role = name, role
        self.conn = Client(str(socket_path(name, role)), family="AF_UNIX", authkey=AUTH)
        self.lock = threading.Lock()

    def call(self, op: str, *args):
        with self.lock:
            self.conn.send((op, args))
            status, value = self.conn.recv()
        if status != "ok":
            raise RuntimeError(f"models server ({self.name} {self.role}): {value}")
        return value

    def hear(self, path):
        return self.call("hear", str(path))


class RemoteQwen:
    """Stands in for backend.Qwen in Designer and Cloner (design_many, clone_many, voice, engine)."""

    def __init__(self, remote: Remote, frame_repo: str):
        from tools.qwen_voices import backend
        self.remote, self.engine = remote, backend.engine(frame_repo)

    def design_many(self, items, language, temperature, seed):
        return self.remote.call("design_many", items, language, temperature, seed)

    def voice(self, ref_wav: str, ref_text: str):
        return (str(ref_wav), ref_text)  # prepared once by the server

    def clone_many(self, jobs, language, seed, gap, max_tokens):
        return self.remote.call("clone_many", jobs, language, seed, gap, max_tokens)


class RemoteEars:
    """Stands in for the readings judge's Ears: judge_take only calls scores()."""

    def __init__(self, remote: Remote):
        self.remote = remote

    def scores(self, take, text, model_voice):
        return self.remote.call("scores", str(take), text, str(model_voice))


def connect(name: str, role: str, say=print) -> Remote | None:
    """The run's model server of this role, started if needed (its models load once per run). None outside a loop
    (no FS_LOOP_PID): the caller loads its own models, as before."""
    loop_pid = os.environ.get("FS_LOOP_PID")
    if not loop_pid:
        return None
    for _ in range(30):
        try:
            remote = Remote(name, role)
        except OSError:
            break
        if remote.call("ping") == loop_pid:
            return remote
        remote.conn.close()  # the server of a run just stopped: it stops within seconds
        time.sleep(2)
    else:
        raise RuntimeError(f"a models server of another loop still answers on {socket_path(name, role)}")
    log = (progress.ROOT / "data" / "cache" / "loops" / name / "logs"
           / f"models-{role}-{time.strftime('%Y%m%d-%H%M%S')}.log")
    log.parent.mkdir(parents=True, exist_ok=True)
    say(f"models server ({role}): starting, the models load once for the run (log {log.relative_to(progress.ROOT)})")
    with open(log, "w", encoding="utf-8") as out:
        proc = subprocess.Popen([sys.executable, "-m", "tools.qwen_voices.server", name, role], stdout=out,
                                stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, cwd=progress.ROOT,
                                start_new_session=True,
                                env={"PYTORCH_CUDA_ALLOC_CONF": ALLOC_CONF, **os.environ, "PYTHONUNBUFFERED": "1"})
    deadline = time.time() + START_TIMEOUT
    while time.time() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(f"models server ({role}) exited with {proc.returncode}: see {log}")
        try:
            remote = Remote(name, role)
            say(f"models server ({role}): ready")
            return remote
        except OSError:
            time.sleep(2)
    raise RuntimeError(f"models server ({role}) not ready after {START_TIMEOUT // 60} min: see {log}")


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 2 or argv[0] not in PASSES or argv[1] not in ROLES:
        print("usage: python -m tools.qwen_voices.server voices|readings|dialogues qwen|ears", file=sys.stderr)
        return 2
    return serve(*argv)


if __name__ == "__main__":
    sys.exit(main())
