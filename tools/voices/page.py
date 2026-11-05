"""Listening page of a zone for the voice loop: data/voices/samples/qwen/pages/<group>-<zone>.html.

The NPCs not found in this run first (MAX_TRIES failed takes: their best take, for the human), then
the NPCs still in progress, then the validated voices, each with its scores.
"""

from __future__ import annotations

import html
import json
import os
from pathlib import Path

from tools.qwen_voices.design import STYLE
from tools.qwen_voices.frame import race_of
from tools.voices import judge, oracle

PAGES = judge.SAMPLES / "pages"
ACCENTS = judge.ROOT / "data" / "accents.json"
SEX_FR = {"male": "homme", "female": "femme"}


def page_path(zone: str) -> Path:
    return PAGES / (zone.replace("/", "-") + ".html")


def _chips(scores: dict) -> str:
    failed = judge.verdict(scores)
    labels = [f"anglais {scores['en'] * 100:.2f} %", f"mots mal lus {scores['wer'] * 100:.0f} %",
              f"{scores['cps']} car./s"]
    if failed:
        labels.append("rejet : " + ", ".join(judge.REASONS[f] for f in failed))
    return "".join(f'<span class="chip">{label}</span>' for label in labels)


def _tile(title: str, note: str, src: Path, out: Path, kind: str = "", scores: dict | None = None) -> str:
    rel = html.escape(os.path.relpath(src, out.parent))
    return (f'<div class="tile {kind}"><b>{html.escape(title)}</b><small>{html.escape(note)}</small>'
            f'<audio controls preload="none" src="{rel}"></audio>{_chips(scores) if scores else ""}</div>')


def _card(n: str, record: dict, accents: dict, out: Path) -> tuple[int, str]:
    entry, persona = record.get("qwen") or {}, record["persona"]
    state = oracle.settled(entry)
    tiles = []
    if state == "ok":
        tiles.append(_tile("voix validée", f"graine {entry['seed']}, {entry['tries']} essai(s)",
                           judge.ROOT / entry["ref"], out, "best", entry["scores"]))
    best = entry.get("best")
    if best and state != "ok" and (judge.ROOT / best["take"]).is_file():
        tiles.append(_tile("meilleur essai raté", f"graine {best['seed']}, {entry.get('tries', 0)} essai(s)",
                           judge.ROOT / best["take"], out, "", best["scores"]))
    race = race_of(record, accents) or accents["default"]
    who = f"{accents['races'][race]['name_fr']} · {SEX_FR.get(persona.get('sex'), '')} · {persona.get('age') or ''}"
    label = {"ok": "", "not_found": " — pas trouvé dans cette exécution, à écouter"}.get(state, f" — en cours, {entry.get('tries', 0)} essai(s)")
    instruct = entry.get("instruct") or (best or {}).get("instruct") or ""
    text = (record.get("voice_text") or {}).get("text") or persona["sample_line"]
    body = (f'<article class="card"><p class="who">{html.escape(who)}{html.escape(label)}</p>'
            f'<h2>{html.escape(record["name"])} <small>PNJ {n}</small></h2>'
            f'<div class="tiles">{"".join(tiles)}</div>'
            f'<p class="label">Texte lu</p><p class="line">« {html.escape(text)} »</p>'
            + (f'<details><summary>Description envoyée à Qwen3</summary><p class="desc">{html.escape(instruct)}</p>'
               '</details>' if instruct else "") + '</article>')
    return {"not_found": 0, None: 1, "ok": 2}[state], body


def write(zone: str, voices: dict) -> Path:
    accents = json.loads(ACCENTS.read_text(encoding="utf-8"))
    out = page_path(zone)
    ids = [n for n in oracle.zone_npcs(zone) if oracle.speaks(voices.get(n))]
    cards = sorted((_card(n, voices[n], accents, out) + (int(n),) for n in ids), key=lambda c: (c[0], c[2]))
    states = [c[0] for c in cards]
    npc_file = oracle.zones_dir() / zone / "npcs.json"
    name = (json.loads(npc_file.read_text(encoding="utf-8")).get("zone_name") if npc_file.exists() else None) or zone
    intro = (f"{states.count(2)} voix validée(s), {states.count(0)} PNJ pas trouvé(s) à écouter, {states.count(1)} en "
             f"cours. Chaque voix est créée par Qwen3-TTS VoiceDesign (cadre scellé) et validée par le juge : "
             f"anglais ≤ {judge.MAX_EN * 100:g} %, mots mal lus ≤ {judge.MAX_WER * 100:g} %, "
             f"{judge.CPS[0]:g} à {judge.CPS[1]:g} caractères par seconde ; {judge.MAX_TRIES} essais par exécution, "
             "les PNJ pas trouvés repartent à l'exécution suivante.")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        '<!doctype html><html lang="fr"><head><meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        f'<title>Voix des PNJ · {html.escape(name)}</title>\n<style>{STYLE}</style></head><body>'
        f'<h1>Voix des PNJ · {html.escape(name)}</h1><p class="intro">{intro}</p>'
        + "".join(c[1] for c in cards) + "</body></html>\n", encoding="utf-8")
    return out
