"""One-shot (2026-10-13): the misread words of the kept takes again, with the tolerant measure (tools/voices/names.py).

The judge now lets a proper noun written another way by Whisper count as read. The best failed takes kept for the
readings and the dialogue pages were scored before; their transcript is in the tries logs
(data/cache/loops/<readings|dialogues>/tries.jsonl, "heard", by zone, unit and seed). For each one, the misread words
are computed again from that transcript and the take's own text; its `failed` criteria follow (the readings judge's
verdict). The refused audio already in game for that very take gets the same scores. Nothing is generated nor moved:
the loops' next pass promotes a kept take that now passes (`rejudge_kept`), and the oracles count a refused audio in
game whose scores pass as validated.

    .venv/bin/python -m tools.voices.rescore_names [--dry-run]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from tools.readings import judge as reading_judge
from tools.voices import judge as voice_judge, names

ROOT = voice_judge.ROOT
ZONES = ROOT / "data" / "zones"
KINDS = (("readings", "readings.json", "audio.json"), ("dialogues", "dialogue_readings.json", "dialogue_audio.json"))


def heard_by_take(loop: str) -> dict[tuple, str]:
    out = {}
    path = ROOT / "data" / "cache" / "loops" / loop / "tries.jsonl"
    if not path.exists():
        return out
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        if e.get("heard") is not None:
            out[(e.get("zone"), e.get("reading"), e.get("seed"))] = e["heard"]
    return out


def _items(audio: dict):
    """Every in-place variant of an audio.json or dialogue_audio.json: (variant dict)."""
    for section in audio.values():
        if isinstance(section, dict):
            for group in section.values():
                if isinstance(group, dict):
                    for sex in ("m", "f"):
                        if isinstance(group.get(sex), dict):
                            yield group[sex]


def main(argv: list[str] | None = None) -> int:
    dry = "--dry-run" in (sys.argv[1:] if argv is None else argv)
    report = {}
    for loop, state_name, audio_name in KINDS:
        heard = heard_by_take(loop)
        counts = {"kept": 0, "rescored": 0, "now_pass": 0, "no_transcript": 0}
        for state_path in sorted(ZONES.glob(f"**/{state_name}")):
            zone = str(state_path.parent.relative_to(ZONES))
            state = json.loads(state_path.read_text(encoding="utf-8"))
            new_scores = {}
            for unit, entry in (state.get("readings") or {}).items():
                best = entry.get("best")
                if entry.get("status") == "ok" or not best or not best.get("scores"):
                    continue
                counts["kept"] += 1
                transcript = heard.get((zone, unit, best["seed"]))
                if transcript is None or not best.get("text"):
                    counts["no_transcript"] += 1
                    continue
                wer = round(names.tolerant_wer(best["text"], transcript, voice_judge.words), 3)
                if wer >= best["scores"]["wer"]:
                    continue
                best["scores"] = {**best["scores"], "wer": wer}
                best["failed"] = reading_judge.verdict(best["scores"])
                new_scores[best["seed"]] = best["scores"]
                counts["rescored"] += 1
                counts["now_pass"] += not best["failed"]
            if new_scores and not dry:
                state_path.write_text(json.dumps(state, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
                audio_path = state_path.with_name(audio_name)
                if audio_path.exists():
                    audio = json.loads(audio_path.read_text(encoding="utf-8"))
                    touched = False
                    for item in _items(audio):
                        if item.get("refused") and item.get("seed") in new_scores:
                            item["scores"] = new_scores[item["seed"]]
                            touched = True
                    if touched:
                        audio_path.write_text(json.dumps(audio, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        report[loop] = counts
        print(f"{loop}: {counts}" + (" (dry run)" if dry else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
