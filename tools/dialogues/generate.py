"""Generator of the dialogues loop (a separate process, like tools/readings/generate.py, whose Cloner it reuses):
one candidate take for each dialogue reading given, cloned from its NPC's model voice.

Reads a JSON list of jobs on stdin ({id, key, page, zone, sex, npc, text, seed, voice_seed, voice_ref}), writes for
each dialogue_candidates/<zone>/<id>_s<seed>.wav, then its .json meta last (the judge only takes a take whose meta
exists). Inside a loop, Qwen3 is the run's model server (tools/qwen_voices/server.py).

    echo '[...]' | .venv-voices/bin/python -m tools.dialogues.generate
"""

from __future__ import annotations

import json
import sys

from tools.dialogues import frame, judge
from tools.loop import progress
from tools.qwen_voices import backend, server
from tools.readings.generate import Cloner


def main() -> int:
    jobs = json.loads(sys.stdin.read())
    for zone in {j["zone"] for j in jobs}:
        (judge.CANDIDATES / judge.flat(zone)).mkdir(parents=True, exist_ok=True)
    size = backend.batch_size()
    slots = progress.Slots("dialogues", size, len(jobs))
    remote = server.connect("dialogues", "qwen")
    cloner = Cloner(server.RemoteQwen(remote, frame.REPO) if remote else None)
    for start in range(0, len(jobs), size):
        batch = jobs[start:start + size]
        takes = [judge.CANDIDATES / judge.flat(j["zone"]) / f"{j['id']}_s{j['seed']}.wav" for j in batch]
        slots.start([{"label": f"{j['id']} {j['name']}", "chars": max(map(len, frame.paragraphs(j["text"])), default=1),
                      "text_chars": len(j["text"])} for j in batch])
        secs = cloner.write_many([(t, j["voice_ref"], j["text"]) for t, j in zip(takes, batch)], batch[0]["seed"])
        slots.finish(secs)
        for job, take, s in zip(batch, takes, secs):
            meta = {**job, "engine": cloner.engine,
                    **({"batch_seed": batch[0]["seed"], "batch": len(batch)} if len(batch) > 1 else {})}
            take.with_suffix(".json").write_text(json.dumps(meta, ensure_ascii=False, indent=1) + "\n",
                                                 encoding="utf-8")
            print(f"generator: {job['id']} s{job['seed']}: {s:.1f}s", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
