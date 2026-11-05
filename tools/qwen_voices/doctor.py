"""Checks the voice environment of this machine before a long run (tools/qwen_voices/backend.py): the backend,
the GPU, the system tools, then (unless --quick) one short take of each model, written to data/cache/doctor/,
heard by the judge. Nothing in the data is touched.

    .venv-voices/bin/python -m tools.qwen_voices.doctor [--quick] [--npc 823]

With --npc, the readings check clones that NPC's model voice (default: the first NPC with one): listen to
data/cache/doctor/clone.wav, it must sound like data/voices/samples/qwen/voices/<npc>/ref.wav.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
from pathlib import Path

from tools.qwen_voices import backend

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "data" / "cache" / "doctor"
TEXT = "Bonjour, aventurier. Les loups rôdent près de la ferme : soyez prudent sur la route de Comté-de-l'Or."


def step(title: str, run) -> bool:
    start = time.time()
    try:
        detail = run()
    except Exception as err:  # noqa: BLE001 - a check reports any failure
        print(f"FAIL  {title}: {type(err).__name__}: {err}", flush=True)
        return False
    print(f"ok    {title}: {detail} ({time.time() - start:.1f}s)", flush=True)
    return True


def gpu() -> str:
    name = backend.name()
    if name == "cuda":
        import torch
        props = torch.cuda.get_device_properties(0)
        return f"cuda, {props.name}, {props.total_memory / 2 ** 30:.0f} GiB, torch {torch.__version__}"
    return name


def tools() -> str:
    missing = [t for t in ("ffmpeg", "oggenc", "claude") if not shutil.which(t)]
    if missing:
        raise RuntimeError(f"missing: {', '.join(missing)} (README, Installer)")
    return "ffmpeg, oggenc, claude"


def first_voice(npc: str | None) -> tuple[str, dict]:
    voices = json.loads((ROOT / "data" / "voices.json").read_text(encoding="utf-8"))["npcs"]
    with_voice = {n: r for n, r in voices.items() if (r.get("qwen") or {}).get("status") == "ok"}
    if npc:
        return npc, with_voice[npc]
    return next(iter(with_voice.items()))


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--quick", action="store_true", help="backend and tools only, no model")
    p.add_argument("--npc", help="NPC whose model voice is cloned (default: the first one with a voice)")
    args = p.parse_args(argv)
    ok = step("backend", gpu) and step("system tools", tools)
    if args.quick or not ok:
        return 0 if ok else 1
    OUT.mkdir(parents=True, exist_ok=True)
    from tools.qwen_voices.design import Designer
    from tools.qwen_voices.frame import describe
    from tools.readings.generate import Cloner
    from tools.voices.judge import Whisper
    accents = json.loads((ROOT / "data" / "accents.json").read_text(encoding="utf-8"))
    npc, record = first_voice(args.npc)
    ears = {}

    def design():
        designer = Designer()
        secs = designer.write(OUT / "design.wav", TEXT, describe(record, accents), 1)
        return f"{record['name']}, {secs:.1f}s of audio -> {OUT / 'design.wav'}"

    def clone():
        cloner = Cloner()
        secs = cloner.write(OUT / "clone.wav", record["qwen"]["ref"], TEXT, 1)
        return f"{record['name']} ({npc}), {secs:.1f}s of audio -> {OUT / 'clone.wav'}"

    def judge():
        ears["w"] = ears.get("w") or Whisper()
        probs, heard, secs = ears["w"].hear(OUT / "clone.wav")
        return f"p(en) {probs.get('en', 0):.4f}, heard: {heard!r}"

    ok = step("Qwen3 VoiceDesign", design) and step("Qwen3 Base (clone)", clone) and step("Whisper", judge)
    if ok:
        def ecapa():
            from tools.readings.judge import Ears
            sim = Ears().similarity(OUT / "clone.wav", ROOT / record["qwen"]["ref"])
            return f"similarity to the model voice {sim:.3f} (readings need 0.75)"
        ok = step("ECAPA", ecapa)
    print("all good" if ok else "something failed: see above", flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
