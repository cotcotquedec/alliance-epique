"""Actor of the voice loop: one round over one or more categories, in the oracle's order (runs in .venv-voices,
called by tools/voices/actor.sh; the loop chooses the categories of a round, tools/loop/engine.py).

1. Candidates left by an interrupted pass are judged first, then the kept best takes that pass the current
   thresholds are promoted (judge.rejudge_kept). An NPC whose voice text changed by hand since its failed takes
   gets a fresh start: those takes are archived (qwen_history: still counted, seeds never reused).
2. Each NPC of these categories still to do (oracle.pending; an NPC of two categories once) gets ONE candidate
   take: its voice text, read by Qwen3-TTS VoiceDesign from its description (the sealed frame,
   tools/qwen_voices/frame.py), with a random seed it never had (candidates/<npc>/s<seed>.wav and .json). The voice
   text is in the NPC's record (voices.json npcs[<npc>].voice_text): its persona's sample line, written there on
   its first take, or a text chosen by hand (from its quests, when the sample line keeps failing).
3. The sealed judge (tools/voices/judge.py) hears them: a good take becomes the NPC's voice, a bad one is deleted
   (or kept for review if it is the NPC's best so far). Inside a loop, the models are the run's model server
   (tools/qwen_voices/server.py), loaded once for the whole run, and each batch is judged while the next one is
   generated; outside a loop, the models load here and the takes are judged after all are generated.
4. Each category's listening page is rewritten (tools/voices/page.py).

    .venv-voices/bin/python -m tools.voices.act eastern-kingdoms/elwynn-forest [eastern-kingdoms/dun-morogh ...]
"""

from __future__ import annotations

import gc
import json
import queue
import random
import sys
import threading

from tools.loop import progress
from tools.qwen_voices import backend, server
from tools.qwen_voices.frame import TEMPERATURE, describe
from tools.voices import judge, oracle, page

ACCENTS = judge.ROOT / "data" / "accents.json"


def new_seed(used: set[int], rng=random.SystemRandom()) -> int:
    while True:
        seed = rng.randrange(1, 2 ** 31)
        if seed not in used:
            return seed


def voice_text(record: dict) -> dict:
    """The NPC's voice text ({"text", "source"}): the one in its record, else its persona's sample line."""
    return record.get("voice_text") or {"text": record["persona"]["sample_line"], "source": "persona.sample_line"}


def archive_changed_texts(ids: list[str], when: str | None = None) -> list[str]:
    """NPCs whose voice text was changed by hand after failed takes: those takes (another text) are archived in
    qwen_history, so that the new text starts with a fresh budget and its own best take. Returns them."""
    import shutil
    import time
    voices = json.loads(judge.VOICES_FILE.read_text(encoding="utf-8"))
    changed = []
    for n in ids:
        record = voices["npcs"][n]
        entry = record.get("qwen") or {}
        best_text = (entry.get("best") or {}).get("text")
        if entry.get("status") == "ok" or not best_text or best_text == voice_text(record)["text"]:
            continue
        entry.pop("best")
        shutil.rmtree(judge.REVIEW / n, ignore_errors=True)
        entry.update(archived_at=when or time.strftime("%Y-%m-%dT%H:%M:%S"),
                     archived_because="voice_text changé : essais d'un autre texte")
        record.setdefault("qwen_history", []).append(record.pop("qwen"))
        changed.append(n)
    if changed:
        judge._write(judge.VOICES_FILE, voices)
        print(f"voice text changed, earlier takes archived: {', '.join(changed)}", flush=True)
    return changed


def keep_voice_texts(ids: list[str]) -> None:
    """Writes the voice text of these NPCs in their record if it is not there yet."""
    voices = json.loads(judge.VOICES_FILE.read_text(encoding="utf-8"))
    missing = [n for n in ids if "voice_text" not in voices["npcs"][n]]
    for n in missing:
        voices["npcs"][n]["voice_text"] = voice_text(voices["npcs"][n])
    if missing:
        judge._write(judge.VOICES_FILE, voices)


def pending(zones: list[str]) -> list[str]:
    """The NPCs still to do in these categories, in order, each once."""
    voices = json.loads(judge.VOICES_FILE.read_text(encoding="utf-8"))["npcs"]
    return list(dict.fromkeys(n for zone in zones for n in oracle.pending(zone, voices)))


def main(argv: list[str] | None = None) -> int:
    zones = sys.argv[1:] if argv is None else argv
    if not zones:
        print("usage: python -m tools.voices.act <zone key>...", file=sys.stderr)
        return 2
    say = lambda line: print(line, flush=True)  # noqa: E731
    board = progress.actor("voices", zones)
    remote = server.connect("voices", "ears", say=say)
    hear = remote.hear if remote else None
    todo = pending(zones)
    left = judge.candidates(set(todo))
    if left:
        board.update(phase="judging takes left by an interrupted pass")
        say(f"round: {len(left)} candidate(s) from an interrupted pass, judged first")
        judge.judge(left, hear=hear)
    if judge.rejudge_kept(say=say):
        say("round: kept take(s) pass the current thresholds")
    archive_changed_texts(pending(zones))
    todo = pending(zones)
    say(f"round: {len(todo)} NPC(s) without a voice in {len(zones)} categor{'y' if len(zones) == 1 else 'ies'}")
    board.update(takes=len(todo))
    counts = {"ok": 0, "failed": 0, "not_found": 0}
    if todo:
        from tools.qwen_voices.design import Designer
        from tools.qwen_voices.frame import REPO
        keep_voice_texts(todo)
        voices = json.loads(judge.VOICES_FILE.read_text(encoding="utf-8"))["npcs"]
        accents = json.loads(ACCENTS.read_text(encoding="utf-8"))
        size = backend.batch_size()
        slots = progress.Slots("voices", size, len(todo))
        board.update(phase="generating and judging" if remote else "generating")
        # the generation thread uses the qwen server while the judge uses the ears server, side by side
        designer = Designer(server.RemoteQwen(server.connect("voices", "qwen", say=say), REPO) if remote
                            else None)
        jobs = []
        for n in todo:
            record, entry = voices[n], voices[n].get("qwen") or {}
            used = set(entry.get("seeds", []))
            used |= {s for old in record.get("qwen_history", []) for s in old.get("seeds", [])}
            seed = new_seed(used)
            folder = judge.CANDIDATES / n
            folder.mkdir(parents=True, exist_ok=True)
            jobs.append((n, seed, folder / f"s{seed}.wav", voice_text(record)["text"], describe(record, accents)))
        made: queue.Queue = queue.Queue()  # batches of takes written (meta last), None at the end

        def generate():
            try:
                for start in range(0, len(jobs), size):
                    batch = jobs[start:start + size]
                    batch_seed = batch[0][1]
                    slots.start([{"label": f"{n} {voices[n]['name']}", "chars": len(text), "text_chars": len(text)}
                                 for n, _, _, text, _ in batch])
                    secs = designer.write_many([(take, text, instruct) for _, _, take, text, instruct in batch],
                                               batch_seed)
                    slots.finish(secs)
                    for (n, seed, take, text, instruct), s in zip(batch, secs):
                        # batch_seed: the seed of the random state the take was drawn from (shared by its batch)
                        take.with_suffix(".json").write_text(json.dumps(
                            {"npc": int(n), "seed": seed, "engine": designer.engine, "temperature": TEMPERATURE,
                             "instruct": instruct, "text": text,
                             **({"batch_seed": batch_seed, "batch": len(batch)} if len(batch) > 1 else {})},
                            ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
                        tries = (voices[n].get("qwen") or {}).get("tries", 0) + 1
                        say(f"actor: {n} {voices[n]['name']} s{seed}: {s:.1f}s (try {tries})")
                    board.update(generated=board.data["generated"] + len(batch))
                    made.put([take for _, _, take, _, _ in batch])
            except BaseException as err:  # noqa: BLE001 - given to the main thread, which fails the round
                made.put(err)
            made.put(None)

        def judged(c: dict) -> None:
            for k in counts:
                counts[k] += c[k]
            board.update(judged=sum(counts.values()), **counts)

        if remote:  # each batch judged while the next one is generated
            worker = threading.Thread(target=generate, daemon=True)
            worker.start()
            while (takes := made.get()) is not None:
                if isinstance(takes, BaseException):
                    raise takes
                judged(judge.judge(takes, hear=hear))
            worker.join()
        else:  # alone (outside a loop): generate everything, free the GPU, then load Whisper and judge
            generate()
            while (takes := made.get()) is not None:
                if isinstance(takes, BaseException):
                    raise takes
            del designer
            gc.collect()
            board.update(phase="judging")
            judged(judge.judge(judge.candidates(set(todo))))
    voices = json.loads(judge.VOICES_FILE.read_text(encoding="utf-8"))["npcs"]
    for zone in zones:
        say(f"{zone}: {len(oracle.pending(zone, voices))} NPC(s) left; page: {page.write(zone, voices)}")
    say(f"round: {counts['ok']} new voice(s), {counts['failed']} failed, {counts['not_found']} not found in this run")
    board.update(phase="done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
