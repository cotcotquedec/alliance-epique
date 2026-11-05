"""Actor of the Elise loop: one round, over the categories the loop gives (tools/elise/actor.sh).

1. Takes left by an interrupted round are put in place first.
2. Each of her lines still to do gets one take: ElevenLabs reads it whole in her voice (tools/elise/frame.py), with a
   seed it never had; the take is decoded to mono WAV at -20 LUFS and put in place at once, without Whisper
   (`place`, 2026-11-01: the user trusts ElevenLabs, the judge is for Qwen TTS only; tools/elise/judge.py still
   holds the files and the state). Before
   each take, the credits left must cover its text: else the round stops with the usage-limit exit code (the loop
   waits for the credits to come back, tools/elise/arbiter.py), printing "credit limit reached|<reset epoch>".
3. The addon's index is rebuilt (pipeline/build_index.py): a new line plays in game after /reload.

    .venv-voices/bin/python -m tools.elise.act <zone>...
"""

from __future__ import annotations

import json
import random
import subprocess
import sys
import time
from pathlib import Path

from pipeline import elevenlabs
from tools.elise import frame, judge, oracle
from tools.loop import progress

EXIT_LIMIT, EXIT_HALT = 75, 77
MARGIN = 50  # characters kept aside on the account
TRUSTED = "ElevenLabs takes are kept without Whisper: the judge is for Qwen TTS only (the user, 2026-11-01)"


def new_seed(used: set[int], rng=random.SystemRandom()) -> int:
    while True:
        seed = rng.randrange(1, 2**31)
        if seed not in used:
            return seed


def decode(mp3: Path, wav: Path) -> float:
    """ElevenLabs' MP3 -> mono WAV at frame.SR, frame.LOUDNESS; returns its seconds."""
    import numpy as np
    import pyloudnorm as pyln
    import soundfile as sf
    raw = wav.with_suffix(".raw.wav")
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(mp3), "-ac", "1", "-ar", str(frame.SR), str(raw)],
                   check=True)
    audio, sr = sf.read(raw, dtype="float32")
    raw.unlink()
    meter = pyln.Meter(sr)
    audio = np.clip(pyln.normalize.loudness(audio, meter.integrated_loudness(audio), frame.LOUDNESS), -1, 1)
    sf.write(wav, audio.astype(np.float32), sr)
    return len(audio) / sr


def place(take: Path, judge, slot: str, section, secs: float | None = None,
          now=lambda: time.strftime("%Y-%m-%dT%H:%M:%S"), say=print) -> str:
    """Puts an ElevenLabs take in place without hearing it (TRUSTED), validated by that rule of the user's as if by
    hand (pipeline/review.py), so that the oracle counts it. `judge`: the loop's judge module (its files and state);
    `slot`: the take's field its audio is filed under (quest, page); `section(meta)`: its audio.json section; `secs`:
    its length, read from the file if not given."""
    meta = judge._read(take.with_suffix(".json"), None)
    unit, zone, when = meta["id"], meta["zone"], now()
    if secs is None:
        import soundfile as sf
        secs = sf.info(str(take)).duration
    scores = {"secs": round(secs, 1), "cps": round(len(meta["text"]) / max(secs, 0.01), 1)}
    data = judge._read(judge.audio_file(zone), {"schema": 1})
    item = data.setdefault(section(meta), {}).setdefault(str(meta[slot]), {"npc": judge.narrator.NARRATOR_ID})
    item[meta["sex"]] = {**judge.accept(zone, take, meta, scores, when),
                         "validated": {"by": "human", "at": when, "rule": TRUSTED}}
    judge._write(judge.audio_file(zone), data)
    state = judge._read(judge.STATE, {"schema": 1, "lines": {}})
    entry = state["lines"].get(unit) or {}
    entry = {**entry, "zone": zone, slot: meta[slot], "kind": meta["kind"], "sex": meta["sex"],
             "tries": entry.get("tries", 0) + 1, "campaign_tries": entry.get("campaign_tries", 0) + 1,
             "seeds": entry.get("seeds", []) + [meta["seed"]]}
    (judge.REVIEW / f"{unit}.wav").unlink(missing_ok=True)
    entry.pop("best", None)
    entry.update(status="ok", seed=meta["seed"], scores=scores)
    state["lines"][unit] = entry
    judge._write(judge.STATE, state)
    take.unlink()
    take.with_suffix(".json").unlink()
    judge._log({"at": when, "zone": zone, "line": unit, "seed": meta["seed"], "scores": scores, "failed": [],
                "status": "ok", "trusted": True, "chars": len(meta["text"])})
    say(f"placed: {unit} s{meta['seed']}: {secs:.1f}s, kept without Whisper")
    return "ok"


def section_of(meta: dict) -> str:
    return judge.SECTION[meta["kind"]]


def main(argv: list[str] | None = None, client=None) -> int:
    zones = sys.argv[1:] if argv is None else argv
    if not zones:
        print("usage: python -m tools.elise.act <zone>...", file=sys.stderr)
        return 2
    say = lambda line: print(line, flush=True)  # noqa: E731
    board = progress.actor("elise", zones)
    voice = judge.voice_id()
    if not voice:
        say("Elise has no voice yet: tools/elise/voice.py")
        return EXIT_HALT
    left = judge.candidates()
    if left:
        board.update(phase="placing takes left by an interrupted round")
        for take in left:
            place(take, judge, "quest", section_of, say=say)
    try:
        client = client or elevenlabs.ElevenLabs()
        state = judge._read(judge.STATE, {"lines": {}})
        todo = [(zone, unit) for zone in zones for unit in oracle.zone_lines(zone, voice, state)["todo"]]
        say(f"round: {len(todo)} line(s) of Elise in {len(zones)} categor{'y' if len(zones) == 1 else 'ies'}")
        board.update(takes=len(todo), phase="reading and judging")
        counts = {"ok": 0, "failed": 0, "not_found": 0}
        judge.CANDIDATES.mkdir(parents=True, exist_ok=True)
        for zone, unit in todo:
            sub = client.subscription()
            credits = int(sub.get("character_limit", 0)) - int(sub.get("character_count", 0))
            if credits < len(unit["text"]) + MARGIN:
                say(f"ElevenLabs: {credits} characters left, {len(unit['text'])} needed: "
                    f"credit limit reached|{sub.get('next_character_count_reset_unix', '')}")
                return EXIT_LIMIT
            entry = (judge._read(judge.STATE, {"lines": {}})["lines"].get(unit["id"])) or {}
            seed = new_seed(set(entry.get("seeds", [])))
            stem = judge.CANDIDATES / f"{unit['id']}_s{seed}"
            stem.with_suffix(".mp3").write_bytes(client.speak(voice, unit["text"], frame.TTS_MODEL, seed=seed,
                                                              settings=frame.SETTINGS,
                                                              output_format=frame.OUTPUT_FORMAT))
            secs = decode(stem.with_suffix(".mp3"), stem.with_suffix(".wav"))
            stem.with_suffix(".mp3").unlink()
            stem.with_suffix(".json").write_text(json.dumps(
                {"id": unit["id"], "zone": zone, "quest": unit["quest"], "kind": unit["kind"], "sex": unit["sex"],
                 "text": unit["text"], "seed": seed, "voice_id": voice, "model": frame.TTS_MODEL},
                ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
            say(f"actor: {unit['id']} s{seed}: {secs:.1f}s ({len(unit['text'])} characters)")
            status = place(stem.with_suffix(".wav"), judge, "quest", section_of, secs, say=say)
            counts["ok" if status == "ok" else "not_found" if status == "not_found" else "failed"] += 1
            board.update(generated=sum(counts.values()), judged=sum(counts.values()), **counts)
    except elevenlabs.ElevenLabsError as err:
        text = str(err)
        if text.startswith(("401", "403")) and "quota" not in text:
            say(f"ElevenLabs refused: {text}")
            return EXIT_HALT
        if text.startswith("429") or "quota" in text:
            say(f"ElevenLabs limit: {text}")
            return EXIT_LIMIT
        raise
    from pipeline import build_index, review
    review.publish_refused("elise", zones)  # a refused line is played in game until a take passes
    build_index.main([])
    say(f"round: {counts['ok']} line(s) in place, {counts['failed']} failed, {counts['not_found']} not found")
    board.update(phase="done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
