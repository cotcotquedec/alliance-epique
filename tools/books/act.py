"""Actor of the books loop: one round (tools/books/actor.sh), as Elise's actor (tools/elise/act.py).

1. Takes left by an interrupted round are put in place first.
2. Up to ROUND page readings still to do (environment FS_ROUND_TAKES) get one take each: ElevenLabs reads the page
   whole in Elise's voice (tools/books/frame.py), with a seed it never had; the take is decoded to mono WAV at
   -20 LUFS (tools/elise/act.py `decode`) and put in place at once, without Whisper (tools/elise/act.py `place`,
   2026-11-01: the user trusts ElevenLabs, the judge is for Qwen TTS only). Before each take:
   - the credits left on the account must cover its text, else the round stops with the usage-limit exit code
     (75: the loop waits for the credits to come back), printing "credit limit reached|<reset epoch>";
   - the run's character budget (`--budget N`, environment FS_BOOKS_BUDGET; data/cache/loops/books/budget.json,
     counted over the whole run of the loop) must cover it, else the round stops with 76 (the loop stops).
3. Refused pages are put in game all the same (D15, pipeline/review.py), then the addon's index is rebuilt.

    .venv-voices/bin/python -m tools.books.act @books
"""

from __future__ import annotations

import json
import os
import sys

from pipeline import elevenlabs, storage
from tools.books import frame, judge, oracle
from tools.loop import progress

EXIT_LIMIT, EXIT_BUDGET, EXIT_HALT = 75, 76, 77
MARGIN = 50  # characters kept aside on the account
ROUND = 100  # page readings in one round (FS_ROUND_TAKES)
BUDGET_FILE = judge.ROOT / "data" / "cache" / "loops" / "books" / "budget.json"


class Budget:
    """The characters a run of the loop may spend (FS_BOOKS_BUDGET), counted across its rounds (FS_LOOP_PID)."""

    def __init__(self, path=BUDGET_FILE, env=os.environ):
        self.path = path
        self.limit = int(env.get("FS_BOOKS_BUDGET") or 0) or None
        run = env.get("FS_LOOP_PID") or "manual"
        data = storage.read_json(path) or {}
        self.data = data if data.get("run") == run else {"run": run, "budget": self.limit, "spent": 0}
        self.data["budget"] = self.limit

    def allows(self, chars: int) -> bool:
        return self.limit is None or self.data["spent"] + chars <= self.limit

    def spend(self, chars: int) -> None:
        self.data["spent"] += chars
        storage.write_json(self.path, self.data)

    @property
    def left(self) -> int | None:
        return None if self.limit is None else self.limit - self.data["spent"]


def section_of(_meta: dict) -> str:
    return judge.SECTION


def main(argv: list[str] | None = None, client=None, budget: Budget | None = None) -> int:
    zones = sys.argv[1:] if argv is None else argv
    if not zones:
        print("usage: python -m tools.books.act @books", file=sys.stderr)
        return 2
    say = lambda line: print(line, flush=True)  # noqa: E731
    board = progress.actor("books", zones)
    voice = judge.voice_id()
    if not voice:
        say("Elise has no voice yet: tools/elise/voice.py")
        return EXIT_HALT
    from tools.elise.act import decode, new_seed, place
    left = judge.candidates()
    if left:
        board.update(phase="placing takes left by an interrupted round")
        for take in left:
            place(take, judge, "page", section_of, say=say)
    budget = budget or Budget()
    size = int(os.environ.get("FS_ROUND_TAKES") or ROUND)
    try:
        client = client or elevenlabs.ElevenLabs()
        state = judge._read(judge.STATE, {"lines": {}})
        todo = [(zone, unit) for zone in zones for unit in oracle.zone_pages(zone, voice, state)["todo"]][:size]
        say(f"round: {len(todo)} book page(s)" + (f", budget left {budget.left} characters"
                                                  if budget.left is not None else ""))
        board.update(takes=len(todo), phase="reading and judging")
        counts = {"ok": 0, "failed": 0, "not_found": 0}
        judge.CANDIDATES.mkdir(parents=True, exist_ok=True)
        for zone, unit in todo:
            chars = len(unit["text"])
            if not budget.allows(chars):
                say(f"books: the run's budget is spent ({budget.data['spent']} of {budget.limit} characters, "
                    f"{chars} needed)")
                return EXIT_BUDGET
            sub = client.subscription()
            credits = int(sub.get("character_limit", 0)) - int(sub.get("character_count", 0))
            if credits < chars + MARGIN:
                say(f"ElevenLabs: {credits} characters left, {chars} needed: "
                    f"credit limit reached|{sub.get('next_character_count_reset_unix', '')}")
                return EXIT_LIMIT
            entry = (judge._read(judge.STATE, {"lines": {}})["lines"].get(unit["id"])) or {}
            seed = new_seed(set(entry.get("seeds", [])))
            stem = judge.CANDIDATES / f"{unit['id']}_s{seed}"
            stem.with_suffix(".mp3").write_bytes(client.speak(voice, unit["text"], frame.TTS_MODEL, seed=seed,
                                                              settings=frame.SETTINGS,
                                                              output_format=frame.OUTPUT_FORMAT))
            budget.spend(chars)
            secs = decode(stem.with_suffix(".mp3"), stem.with_suffix(".wav"))
            stem.with_suffix(".mp3").unlink()
            stem.with_suffix(".json").write_text(json.dumps(
                {"id": unit["id"], "zone": zone, "page": unit["page"], "kind": unit["kind"], "sex": unit["sex"],
                 "text": unit["text"], "seed": seed, "voice_id": voice, "model": frame.TTS_MODEL},
                ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
            say(f"actor: {unit['id']} s{seed}: {secs:.1f}s ({chars} characters)")
            status = place(stem.with_suffix(".wav"), judge, "page", section_of, secs, say=say)
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
    review.publish_refused("book", zones)  # a refused page is played in game until a take passes
    build_index.main([])
    say(f"round: {counts['ok']} page(s) in place, {counts['failed']} failed, {counts['not_found']} not found")
    board.update(phase="done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
