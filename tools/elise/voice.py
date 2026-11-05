"""Elise's voice (2026-10-10): designed once with ElevenLabs from her record (pipeline/narrator.py), chosen by ear,
then definitive. Only her lines change afterwards (the Elise loop, tools/elise/constitution.md).

- `design [--rounds 1]`: each round asks ElevenLabs Voice Design for 3 previews of her sample line (a few hundred
  characters of credits); they go to data/voices/samples/elise/design/<generated_voice_id>.mp3 and .json, and the
  listening page data/voices/samples/pages/elise.html is rewritten (bench: http://127.0.0.1:8765/media/data/voices/
  samples/pages/elise.html). Run again for more.
- `keep <generated_voice_id>`: that preview becomes her ElevenLabs voice (one voice slot), and her record goes to
  data/voices.json under NARRATOR_ID with an "elevenlabs" entry (voice ID, models, description); the preview is kept
  as her reference (data/voices/samples/elise/voice/ref.mp3 and ref.flac), to clone her elsewhere one day. Refused
  when she already has a voice: changing it is a human decision, by hand.

- `use <voice_id>`: a voice already in the account becomes hers, without designing one (decided on 2026-10-10:
  G6INpmIspgFpsST79Psc, the former archetype "FS base HumanFemaleOfficial"); her reference is one reading of her
  sample line in that voice (its characters of credits).

Refused while the voice loop runs (it writes data/voices.json).

    .venv/bin/python -m tools.elise.voice design
    .venv/bin/python -m tools.elise.voice keep <generated_voice_id>
    .venv/bin/python -m tools.elise.voice use <voice_id>
"""

from __future__ import annotations

import argparse
import html
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

from pipeline import elevenlabs, narrator

ROOT = Path(__file__).resolve().parents[2]
VOICES_FILE = ROOT / "data" / "voices.json"
FOLDER = ROOT / "data" / "voices" / "samples" / "elise"
DESIGN = FOLDER / "design"
VOICE = FOLDER / "voice"
PAGE = ROOT / "data" / "voices" / "samples" / "pages" / "elise.html"
DESIGN_MODEL = "eleven_multilingual_ttv_v2"
TTS_MODEL = "eleven_v4"  # her lines (tools/elise/frame.py uses this one)
# ElevenLabs Voice Design reads an English description best; her record says the same in French.
DESCRIPTION = ("Adult female night elf, the narrator of a fantasy role-playing game. Shy, mysterious and very wise. "
               "Calm, soft, slightly breathy mid-range voice, as if confiding a secret; slow and even pace, very "
               "clear diction, no theatrical emphasis, like a gentle audiobook storyteller. Native French speaker "
               "from France, standard French accent, no English accent.")
NPC = str(narrator.NARRATOR_ID)


def now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S")


def voice_loop_running() -> bool:
    return subprocess.run(["pgrep", "-f", "tools[.]loop run voices"], capture_output=True).returncode == 0


def previews() -> list[dict]:
    return sorted((json.loads(p.read_text(encoding="utf-8")) for p in DESIGN.glob("*.json")), key=lambda m: m["at"])


def write_page() -> Path:
    e = html.escape
    kept = (json.loads(VOICES_FILE.read_text(encoding="utf-8"))["npcs"].get(NPC) or {}).get("elevenlabs") or {}
    cards = []
    for m in previews():
        gid = m["generated_voice_id"]
        chosen = gid == kept.get("generated_voice_id")
        cards.append(f'<article class="card{" kept" if chosen else ""}"><h2>{e(m["at"].replace("T", " "))}'
                     f'{" · voix d&#39;Elise" if chosen else ""}</h2><audio controls preload="none" '
                     f'src="../elise/design/{e(gid)}.mp3"></audio>'
                     f'<pre>.venv/bin/python -m tools.elise.voice keep {e(gid)}</pre></article>')
    PAGE.parent.mkdir(parents=True, exist_ok=True)
    PAGE.write_text(
        '<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" '
        'content="width=device-width,initial-scale=1"><title>Voix d\'Elise</title><style>'
        ':root{--bg:#f5f1e8;--panel:#fffdf8;--ink:#221d16;--line:#e4dccb;--soft:#efe8d9;--ok:#2e8b57}'
        '@media (prefers-color-scheme:dark){:root{--bg:#13110e;--panel:#1c1915;--ink:#efe7d8;--line:#332e26;'
        '--soft:#26221c;--ok:#5cc98c}}body{margin:0 auto;max-width:800px;padding:16px;background:var(--bg);'
        'color:var(--ink);font:15px/1.5 system-ui,sans-serif}.card{background:var(--panel);border:1px solid '
        'var(--line);border-radius:12px;padding:12px;margin:12px 0}.card.kept{border-color:var(--ok)}h2{font-size:'
        '16px;margin:0 0 6px}audio{width:100%}pre{background:var(--soft);padding:6px;border-radius:6px;'
        'overflow-x:auto;white-space:pre-wrap}</style></head><body><h1>Voix d\'Elise, la narratrice</h1>'
        f'<p>Texte lu : « {e(narrator.PERSONA["sample_line"])} »</p><details><summary>Description envoyée à '
        f'ElevenLabs ({DESIGN_MODEL})</summary><p>{e(DESCRIPTION)}</p></details>'
        + ("".join(reversed(cards)) or "<p>Aucun extrait : tools.elise.voice design</p>") + "</body></html>\n",
        encoding="utf-8")
    return PAGE


def design(rounds: int, client=None) -> int:
    client = client or elevenlabs.ElevenLabs()
    DESIGN.mkdir(parents=True, exist_ok=True)
    text = narrator.PERSONA["sample_line"]
    for _ in range(rounds):
        for preview in client.design(DESCRIPTION, text, DESIGN_MODEL):
            gid = preview["generated_voice_id"]
            (DESIGN / f"{gid}.mp3").write_bytes(elevenlabs.preview_audio(preview))
            meta = {"generated_voice_id": gid, "model": DESIGN_MODEL, "description": DESCRIPTION, "text": text,
                    "duration_secs": preview.get("duration_secs"), "at": now()}
            (DESIGN / f"{gid}.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1) + "\n",
                                                encoding="utf-8")
            print(f"preview {gid}", flush=True)
    page = write_page()
    print(f"page: {page.relative_to(ROOT)} (bench: http://127.0.0.1:8765/media/{page.relative_to(ROOT)})")
    return 0


def keep(gid: str, client=None) -> int:
    meta_file = DESIGN / f"{gid}.json"
    if not meta_file.is_file():
        print(f"no preview {gid} in {DESIGN.relative_to(ROOT)}", file=sys.stderr)
        return 1
    record = json.loads(VOICES_FILE.read_text(encoding="utf-8"))["npcs"].get(NPC) or {}
    if record.get("elevenlabs"):
        print("Elise already has her voice: it is definitive (changing it is a human decision, by hand)",
              file=sys.stderr)
        return 1
    meta = json.loads(meta_file.read_text(encoding="utf-8"))
    client = client or elevenlabs.ElevenLabs()
    voice_id = client.create(narrator.NAME, DESCRIPTION, gid)
    VOICE.mkdir(parents=True, exist_ok=True)
    shutil.copy2(DESIGN / f"{gid}.mp3", VOICE / "ref.mp3")
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(VOICE / "ref.mp3"), "-c:a", "flac",
                    str(VOICE / "ref.flac")], check=True)
    (VOICE / "ref.txt").write_text(meta["text"] + "\n", encoding="utf-8")
    _save(record, {"voice_id": voice_id, "generated_voice_id": gid, "design_model": meta["model"],
                   "tts_model": TTS_MODEL, "description": meta["description"], "text": meta["text"],
                   "ref": str((VOICE / "ref.flac").relative_to(ROOT)), "created_at": now()})
    write_page()
    print(f"Elise: ElevenLabs voice {voice_id} kept (reference {VOICE.relative_to(ROOT)}/ref.flac)")
    return 0


def _save(record: dict, entry: dict) -> None:
    data = json.loads(VOICES_FILE.read_text(encoding="utf-8"))
    data["npcs"][NPC] = {**narrator.record(), **{k: v for k, v in record.items() if k != "elevenlabs"},
                         "elevenlabs": entry}
    tmp = VOICES_FILE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    tmp.replace(VOICES_FILE)


def use(voice_id: str, client=None) -> int:
    record = json.loads(VOICES_FILE.read_text(encoding="utf-8"))["npcs"].get(NPC) or {}
    if record.get("elevenlabs"):
        print("Elise already has her voice: it is definitive (changing it is a human decision, by hand)",
              file=sys.stderr)
        return 1
    client = client or elevenlabs.ElevenLabs()
    found = client.voice(voice_id)
    text = narrator.PERSONA["sample_line"]
    VOICE.mkdir(parents=True, exist_ok=True)
    (VOICE / "ref.mp3").write_bytes(client.speak(voice_id, text, TTS_MODEL))
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(VOICE / "ref.mp3"), "-c:a", "flac",
                    str(VOICE / "ref.flac")], check=True)
    (VOICE / "ref.txt").write_text(text + "\n", encoding="utf-8")
    _save(record, {"voice_id": voice_id, "account_name": found.get("name"), "tts_model": TTS_MODEL,
                   "description": found.get("description"), "text": text,
                   "ref": str((VOICE / "ref.flac").relative_to(ROOT)), "created_at": now(),
                   "source": "existing voice of the account"})
    print(f"Elise: ElevenLabs voice {voice_id} ({found.get('name')}) is hers; reference "
          f"{VOICE.relative_to(ROOT)}/ref.flac")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("design")
    d.add_argument("--rounds", type=int, default=1)
    k = sub.add_parser("keep")
    k.add_argument("generated_voice_id")
    u = sub.add_parser("use")
    u.add_argument("voice_id")
    sub.add_parser("page")
    args = ap.parse_args(argv)
    if args.cmd == "page":
        print(write_page())
        return 0
    if args.cmd in ("keep", "use") and voice_loop_running():
        print("the voice loop is running (it writes data/voices.json): wait for it to finish", file=sys.stderr)
        return 1
    if args.cmd == "use":
        return use(args.voice_id)
    return design(args.rounds) if args.cmd == "design" else keep(args.generated_voice_id)


if __name__ == "__main__":
    sys.exit(main())
