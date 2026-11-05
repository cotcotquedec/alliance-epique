"""Redo an NPC's model voice (a human decision, 2026-10-07): when its quest readings keep failing on the similarity
to its model voice, that voice clones badly; a new one fixes it (Garde Thomas: 5 of 8 readings, similarity at most
0.74, then 8 of 8 with a new voice, 0.74-0.86).

For each NPC given:
- its model voice is archived: voices.json npcs[<npc>].qwen moves to qwen_history (its tries stay counted, its seeds
  are never reused) and ref.wav / ref.txt to data/voices/samples/qwen/voices_history/<npc>/<n>-ref.*;
- all its quest readings, in every zone, are deleted (game ogg, FLAC master, audio.json entry, kept review takes)
  and their readings.json entries move to that file's "history": one NPC, one voice, at the start and the end of
  every quest;
- its takes waiting for a verdict (voice and readings candidates) are deleted: they were made with the old voice;
- the addon's index is rebuilt (the NPC reads with the client's TTS until its new readings are in place).
Then rerun the voice loop and the readings loop for these NPCs (`--all --npc 197`). Both levels drop (a validated
voice and its readings fewer): both runs need --reset-ratchet. In game, a recreated .ogg is heard only after a full restart of the game (S2), not /reload.

    .venv/bin/python -m tools.voices.redo 197 6306 279
"""

from __future__ import annotations

import json
import shutil
import sys
import time
from pathlib import Path

from tools.voices import judge

SAMPLES = judge.SAMPLES
HISTORY = SAMPLES / "voices_history"
ZONES = judge.ROOT / "data" / "zones"
GAME_AUDIO = judge.ROOT / "addon" / "ForeverSpeech" / "audio"


def _read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def archive_voice(voices: dict, npc: str, when: str, why: str) -> Path | None:
    record = voices["npcs"][npc]
    entry = record.pop("qwen", None)
    if not entry:
        return None
    folder, n = HISTORY / npc, len(record.get("qwen_history", [])) + 1
    folder.mkdir(parents=True, exist_ok=True)
    current = SAMPLES / "voices" / npc
    for name in ("ref.wav", "ref.txt"):
        if (current / name).exists():
            shutil.move(current / name, folder / f"{n}-{name}")
    shutil.rmtree(current, ignore_errors=True)
    shutil.rmtree(SAMPLES / "review" / npc, ignore_errors=True)
    entry.update(ref=str((folder / f"{n}-ref.wav").relative_to(judge.ROOT)), archived_at=when, archived_because=why)
    record.setdefault("qwen_history", []).append(entry)
    return folder


def delete_readings(npc: int, when: str) -> list[str]:
    """Deletes the NPC's readings in every zone; returns them ("<zone> <id>")."""
    gone = []
    for audio_path in sorted(ZONES.glob("**/audio.json")):
        zone = str(audio_path.parent.relative_to(ZONES))
        audio, changed = _read(audio_path), False
        for section in ("audio", "complete"):
            for quest in [q for q, item in (audio.get(section) or {}).items() if item.get("npc") == npc]:
                item = audio[section].pop(quest)
                changed = True
                for sex in ("m", "f"):
                    if sex in item and item[sex].get("master"):
                        (judge.ROOT / item[sex]["master"]).unlink(missing_ok=True)
                kind = "detail" if section == "audio" else "complete"
                gone += [f"{zone} {quest}_{kind}" + ("_f" if sex == "f" else "") for sex in ("m", "f") if sex in item]
        if changed:
            judge._write(audio_path, audio)
    shutil.rmtree(GAME_AUDIO / str(npc), ignore_errors=True)
    for state_path in sorted(ZONES.glob("**/readings.json")):
        zone = str(state_path.parent.relative_to(ZONES))
        state = _read(state_path)
        ids = [k for k, e in state.get("readings", {}).items() if e.get("npc") == npc]
        for unit in ids:
            entry = state["readings"].pop(unit)
            shutil.rmtree(SAMPLES / "reading_review" / zone.replace("/", "-") / unit, ignore_errors=True)
            entry.pop("best", None)
            state.setdefault("history", []).append({"id": unit, **entry, "archived_at": when,
                                                    "archived_because": "voix modèle du PNJ refaite"})
        if ids:
            judge._write(state_path, state)
    return gone


def delete_dialogues(npc: int, when: str) -> int:
    """Deletes the NPC's dialogue readings in every zone (tools/dialogues/): one NPC, one voice. Returns how many."""
    gone = 0
    for audio_path in sorted(ZONES.glob("**/dialogue_audio.json")):
        audio = _read(audio_path)
        keys = [k for k, item in (audio.get("dialogues") or {}).items() if item.get("npc") == npc]
        for key in keys:
            item = audio["dialogues"].pop(key)
            for sex in ("m", "f"):
                if sex in item and item[sex].get("master"):
                    (judge.ROOT / item[sex]["master"]).unlink(missing_ok=True)
                    gone += 1
        if keys:
            judge._write(audio_path, audio)
    for state_path in sorted(ZONES.glob("**/dialogue_readings.json")):
        zone = str(state_path.parent.relative_to(ZONES))
        state = _read(state_path)
        ids = [k for k, e in state.get("readings", {}).items() if e.get("npc") == npc]
        for unit in ids:
            entry = state["readings"].pop(unit)
            shutil.rmtree(SAMPLES / "dialogue_review" / zone.replace("/", "-") / unit, ignore_errors=True)
            entry.pop("best", None)
            state.setdefault("history", []).append({"id": unit, **entry, "archived_at": when,
                                                    "archived_because": "voix modèle du PNJ refaite"})
        if ids:
            judge._write(state_path, state)
    return gone


def delete_candidates(npc: str) -> int:
    """Deletes the NPC's takes waiting for a verdict (voice loop, readings loop); returns how many."""
    gone = 0
    folder = SAMPLES / "candidates" / npc
    if folder.exists():
        gone += len(list(folder.glob("*.wav")))
        shutil.rmtree(folder)
    for meta_path in sorted([*(SAMPLES / "reading_candidates").glob("*/*.json"),
                             *(SAMPLES / "dialogue_candidates").glob("*/*.json")]):
        if str(_read(meta_path).get("npc")) == npc:
            meta_path.with_suffix(".wav").unlink(missing_ok=True)
            meta_path.unlink()
            gone += 1
    return gone


def main(argv: list[str] | None = None) -> int:
    npcs = sys.argv[1:] if argv is None else argv
    if not npcs:
        print(__doc__)
        return 2
    when = time.strftime("%Y-%m-%dT%H:%M:%S")
    voices = _read(judge.VOICES_FILE)
    unknown = [n for n in npcs if n not in voices["npcs"]]
    if unknown:
        print(f"unknown NPC(s): {', '.join(unknown)}", file=sys.stderr)
        return 2
    for npc in npcs:
        folder = archive_voice(voices, npc, when, "voix modèle qui se clone mal (ressemblance des lectures sous le "
                                                  "seuil) : refaite à la demande de l'utilisateur")
        judge._write(judge.VOICES_FILE, voices)
        gone = delete_readings(int(npc), when)
        gone_dialogues = delete_dialogues(int(npc), when)
        waiting = delete_candidates(npc)
        print(f"{npc} {voices['npcs'][npc]['name']}: model voice archived ({folder}), {len(gone)} reading(s) "
              f"and {gone_dialogues} dialogue reading(s) deleted, {waiting} take(s) waiting for a verdict deleted")
    from pipeline import build_index
    build_index.main([])
    print(f"next: tools/voices/run.sh --all --npc {' --npc '.join(npcs)} --reset-ratchet, then "
          f"tools/readings/run.sh --all --npc {' --npc '.join(npcs)} --reset-ratchet")
    return 0


if __name__ == "__main__":
    sys.exit(main())
