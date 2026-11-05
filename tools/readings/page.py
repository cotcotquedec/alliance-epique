"""Listening page of a zone for the readings loop: data/voices/samples/qwen/pages/readings-<group>-<zone>.html.

NPC by NPC: its model voice, then each of its quest readings, the ones not found in this run first (their best
failed take), then those in place (the FLAC master: browsers do not all play Ogg), with the judge's scores.
"""

from __future__ import annotations

import html
import json
import os
from pathlib import Path

from tools.qwen_voices.design import STYLE
from tools.readings import frame, judge

PAGES = judge.SAMPLES / "pages"


def page_path(zone: str) -> Path:
    return PAGES / f"readings-{judge.flat(zone)}.html"


def _read(path: Path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def _chips(scores: dict, failed: list[str]) -> str:
    bad = lambda k: " bad" if k in failed else ""  # noqa: E731
    return (f'<div class="chips"><span class="chip{bad("en")}">anglais {scores["en"] * 100:.2f} %</span>'
            f'<span class="chip{bad("wer")}">mots mal lus {scores["wer"] * 100:.0f} %</span>'
            f'<span class="chip{bad("cps")}">{scores["cps"]} car./s</span>'
            f'<span class="chip{bad("sim")}">voix {scores.get("sim", 0):.2f}</span>'
            f'<span class="chip">{scores["secs"]} s</span></div>')


def write(zone: str) -> Path:
    e = html.escape
    out = page_path(zone)
    folder = judge.ZONES / zone
    units = frame.units(_read(folder / "scripts.json", None))
    audio, state = _read(folder / "audio.json", {}), _read(folder / "readings.json", {}).get("readings", {})
    records = json.loads(judge.voice_judge.VOICES_FILE.read_text(encoding="utf-8"))["npcs"]
    rel = lambda p: e(os.path.relpath(judge.ROOT / p, out.parent))  # noqa: E731
    by_npc: dict[int, list[dict]] = {}
    for u in units:
        by_npc.setdefault(u["npc"], []).append(u)
    sections, done, total = [], 0, 0
    for npc, items in by_npc.items():
        record = records.get(str(npc)) or {}
        voice = (record.get("qwen") or {}).get("ref")
        cards = []
        for u in items:
            total += 1
            item = ((audio.get(judge.SECTION[u["kind"]]) or {}).get(str(u["quest"])) or {}).get(u["sex"]) or {}
            entry = state.get(u["id"]) or {}
            tiles = []
            if item.get("master"):
                done += 1
                label = "en place" + (" (ElevenLabs)" if item.get("model") != judge.MODEL else "")
                tiles.append(f'<div class="tile best"><b>Lecture {e(label)}</b><small>graine {item.get("seed", "–")}'
                             f'</small><audio controls preload="none" src="{rel(item["master"])}"></audio>'
                             + (_chips(item["scores"], []) if item.get("scores") else "") + "</div>")
            elif entry.get("best") and (judge.ROOT / entry["best"]["take"]).is_file():
                best = entry["best"]
                tiles.append(f'<div class="tile"><b>Meilleur essai raté</b><small>{entry.get("tries", 0)} essai(s)'
                             f'</small><audio controls preload="none" src="{rel(best["take"])}"></audio>'
                             f'{_chips(best["scores"], best["failed"])}</div>')
            kind = ("Début" if u["kind"] == "detail" else "Fin") + (" · variante féminine" if u["sex"] == "f" else "")
            status = ("" if item.get("master") else " — pas trouvée dans cette exécution" if
                      entry.get("status") == "not_found" else " — à faire")
            cards.append((0 if entry.get("status") == "not_found" and not item.get("master") else 1,
                          f'<article class="card"><p class="who">{e(kind + status)}</p>'
                          f'<h2>{e(u["name"])} <small>quête {u["quest"]}</small></h2>'
                          + (f'<div class="tiles">{"".join(tiles)}</div>' if tiles else "")
                          + f'<details><summary>Texte</summary><p class="desc">{e(u["text"])}</p></details></article>'))
        head = (f'<div class="tiles"><div class="tile ref"><b>Voix modèle</b><small>référence du clonage</small>'
                f'<audio controls preload="none" src="{rel(voice)}"></audio></div></div>' if voice else
                '<p class="note">Pas encore de voix modèle (boucle voix).</p>')
        sections.append(f'<section><h2 style="margin-top:28px">{e(record.get("name") or str(npc))} '
                        f'<small>PNJ {npc}</small></h2>{head}'
                        + "".join(c for _, c in sorted(cards, key=lambda c: c[0])) + "</section>")
    name = (_read(folder / "npcs.json", {}) or {}).get("zone_name") or zone
    intro = (f"{done} lecture(s) en place sur {total}. Chaque lecture est lue par Qwen3-TTS Base, qui clone la voix "
             "modèle du PNJ, et validée par le juge : anglais, mots mal lus, débit et ressemblance avec la voix "
             f"modèle (au moins {judge.MIN_SIM:g}).")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text('<!doctype html><html lang="fr"><head><meta charset="utf-8">\n'
                   '<meta name="viewport" content="width=device-width,initial-scale=1">'
                   f'<title>Lectures · {e(name)}</title>\n<style>{STYLE}</style></head><body>'
                   f'<h1>Lectures de quêtes · {e(name)}</h1><p class="intro">{intro}</p>'
                   + "".join(sections) + "</body></html>\n", encoding="utf-8")
    return out
