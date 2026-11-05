"""Generator of the readings loop (a separate process, so that Qwen3 and the judge run side by side,
tools/readings/act.py): one candidate take for each reading given, cloned from its NPC's model voice.

Reads a JSON list of jobs on stdin ({id, zone, quest, kind, sex, npc, text, seed, voice_seed, voice_ref}: the actor
gives the NPC's model voice), writes for each reading_candidates/<zone>/<id>_s<seed>.wav, then its .json meta last
(the judge only takes a take whose meta exists). Inside a loop, Qwen3 is the run's model server
(tools/qwen_voices/server.py: loaded once per run); otherwise it loads here. Each model voice is prepared once.

    echo '[...]' | .venv-voices/bin/python -m tools.readings.generate
"""

from __future__ import annotations

import json
import sys

from tools.loop import progress
from tools.qwen_voices import backend, server
from tools.readings import frame, judge


class Cloner:
    """Qwen3-TTS Base on this machine's backend (tools/qwen_voices/backend.py): clones a model voice (reference
    audio and its exact transcript). `qwen`: the loop's model server (tools/qwen_voices/server.py RemoteQwen)."""

    def __init__(self, qwen=None):
        import numpy as np
        import pyloudnorm as pyln
        import soundfile as sf
        import soxr
        self.np, self.pyln, self.sf, self.soxr = np, pyln, sf, soxr
        self.qwen = qwen or backend.Qwen(frame.REPO)
        self.engine = self.qwen.engine
        self.refs = {}

    def ref(self, voice_ref: str):
        """The model voice (ref.wav, repo-relative, and its exact transcript ref.txt beside it), prepared once."""
        if voice_ref not in self.refs:
            wav = judge.ROOT / voice_ref
            text = wav.with_suffix(".txt").read_text(encoding="utf-8").strip()
            self.refs[voice_ref] = self.qwen.voice(str(wav), text)
        return self.refs[voice_ref]

    def write_many(self, takes: list[tuple[object, str, str]], seed: int) -> list[float]:
        """Takes [(dest, voice_ref, text)] generated in one batch (backend.batch_size), the batch seeded with
        `seed`. Returns their durations."""
        jobs = [(frame.paragraphs(text), self.ref(voice_ref)) for _, voice_ref, text in takes]
        results = self.qwen.clone_many(jobs, frame.LANGUAGE, seed, frame.GAP, frame.MAX_TOKENS)
        return [self.save(dest, audio, sr) for (dest, _, _), (audio, sr) in zip(takes, results)]

    def save(self, dest, audio, sr: int) -> float:
        np = self.np
        if sr != frame.SR:
            audio = self.soxr.resample(audio, sr, frame.SR)
        meter = self.pyln.Meter(frame.SR)
        if len(audio) <= int(meter.block_size * frame.SR):  # Qwen3 now and then gives (almost) nothing: seen
            # 2026-10-10, the loudness meter raised and stopped the round; padded with silence, the judge refuses it
            audio = np.concatenate([np.asarray(audio, dtype=np.float32), np.zeros(frame.SR, dtype=np.float32)])
        loudness = meter.integrated_loudness(audio)
        if np.isfinite(loudness):
            audio = np.clip(self.pyln.normalize.loudness(audio, loudness, frame.LOUDNESS), -1, 1)
        self.sf.write(dest, audio.astype(np.float32), frame.SR)
        return len(audio) / frame.SR


def main() -> int:
    jobs = json.loads(sys.stdin.read())  # each job has its zone (a round may cover several categories)
    for zone in {j["zone"] for j in jobs}:
        (judge.CANDIDATES / judge.flat(zone)).mkdir(parents=True, exist_ok=True)
    size = backend.batch_size()
    slots = progress.Slots("readings", size, len(jobs))
    names = {n: r.get("name", n) for n, r in json.loads(judge.voice_judge.VOICES_FILE.read_text(
        encoding="utf-8"))["npcs"].items()}
    remote = server.connect("readings", "qwen")
    cloner = Cloner(server.RemoteQwen(remote, frame.REPO) if remote else None)
    for start in range(0, len(jobs), size):
        batch = jobs[start:start + size]
        takes = [judge.CANDIDATES / judge.flat(j["zone"]) / f"{j['id']}_s{j['seed']}.wav" for j in batch]
        slots.start([{"label": f"{j['id']} {names.get(str(j['npc']), j['npc'])}",
                      "chars": max(map(len, frame.paragraphs(j["text"])), default=1), "text_chars": len(j["text"])}
                     for j in batch])
        secs = cloner.write_many([(t, j["voice_ref"], j["text"]) for t, j in zip(takes, batch)], batch[0]["seed"])
        slots.finish(secs)
        for job, take, s in zip(batch, takes, secs):
            # batch_seed: the seed of the random state the take was drawn from (shared by its batch)
            meta = {**job, "engine": cloner.engine,
                    **({"batch_seed": batch[0]["seed"], "batch": len(batch)} if len(batch) > 1 else {})}
            take.with_suffix(".json").write_text(json.dumps(meta, ensure_ascii=False, indent=1) + "\n",
                                                 encoding="utf-8")
            print(f"generator: {job['id']} (PNJ {job['npc']}) s{job['seed']}: {s:.1f}s", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
