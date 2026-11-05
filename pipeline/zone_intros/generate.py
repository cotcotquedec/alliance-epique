"""Claude writes Elise's introduction of each zone (pipeline/llm.py), from the zone's dossier (zones.py) and a
versioned prompt (prompt_v<N>.md), pinned model, JSON schema. Checked before it is kept: length, no figure, no
bracket, no player placeholder; a text that breaks a rule is asked again with what is wrong (ATTEMPTS at most).

Each text is a script of data/zones/<group>/@intros/scripts.json, section "zones", keyed by area ID, said by Elise
(npc_id NARRATOR_ID): the Elise loop reads it there (tools/elise/frame.py). Only the zones without one are written,
unless --force or --zone: a new text means a new audio (the Elise loop redoes a changed text, credits included).
"""

from __future__ import annotations

import hashlib
import json
import re
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from pipeline import narrator, storage
from pipeline.llm import LLMError, LLMLimit, claude_json
from pipeline.zone_intros import SECTION, folder, zones as zone_list

PROMPT_VERSION = 2  # v1 (2026-10-11); v2 (2026-10-11): from the Alliance's side, the territory in the dossier
PROMPT_FILE = Path(__file__).with_name(f"prompt_v{PROMPT_VERSION}.md")
MODEL = "claude-opus-5-5"  # writing, not extraction: the best model (about 50 zones)
EFFORT = "high"
ATTEMPTS = 3
WORDS = (55, 100)  # the prompt asks 60 to 90; a little slack before asking again
PARALLEL = 4

SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["text", "names"],
    "properties": {
        "text": {"type": "string", "description": "La réplique d'Elise, en français."},
        "names": {"type": "array", "items": {"type": "string"},
                  "description": "Les noms propres de la réplique, sans celui de la zone."},
    },
}

_lock = threading.Lock()


def problems(text: str) -> list[str]:
    """What breaks the prompt's rules in a text (empty: kept)."""
    out = []
    words = len(re.findall(r"[\wÀ-ÿ'’-]+", text))
    if not WORDS[0] <= words <= WORDS[1]:
        out.append(f"{words} mots : il en faut entre 60 et 90")
    if re.search(r"\d", text):
        out.append("un nombre en chiffres")
    if re.search(r"[()\[\]<>$*#_]", text):
        out.append("une parenthèse ou un symbole")
    if len([p for p in re.split(r"\n\s*\n", text) if p.strip()]) > 2:
        out.append("plus de deux paragraphes")
    return out


def user_message(dossier: dict, issues: list[str] | None = None) -> str:
    msg = "Dossier de la zone (JSON) :\n\n" + json.dumps(dossier, ensure_ascii=False, indent=1)
    if issues:
        msg += ("\n\nTa réponse précédente ne respectait pas les règles : " + " ; ".join(issues)
                + ". Écris une nouvelle réplique.")
    return msg


def inputs_hash(dossier: dict) -> str:
    raw = json.dumps({"dossier": dossier, "prompt": PROMPT_FILE.read_text(encoding="utf-8"), "schema": SCHEMA,
                      "model": MODEL, "effort": EFFORT}, ensure_ascii=False, sort_keys=True)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def write_one(dossier: dict, call=claude_json, bare: bool = False) -> dict:
    """The script of one zone: Claude's text, checked, with how it was made."""
    system = PROMPT_FILE.read_text(encoding="utf-8")
    issues, cost = None, 0.0
    for attempt in range(1, ATTEMPTS + 1):
        answer = call(system, user_message(dossier, issues), SCHEMA, MODEL, EFFORT, bare=bare)
        cost += answer.cost_usd
        text = "\n\n".join(p.strip() for p in re.split(r"\n\s*\n", answer.data["text"].strip()) if p.strip())
        issues = problems(text)
        if not issues:
            return {"npc_id": narrator.NARRATOR_ID, "name": dossier["name"], "area": dossier["area"],
                    "map": dossier["map"], "name_en": dossier["name_en"], "text": text,
                    "names": answer.data.get("names") or [],
                    "generator": {"prompt_version": PROMPT_VERSION, "model": answer.model, "effort": EFFORT,
                                  "inputs_hash": inputs_hash(dossier), "attempts": attempt,
                                  "cost_usd": round(cost, 4)},
                    "created_at": storage.now()}
    raise LLMError(f"zone {dossier['area']} ({dossier['name']}): still {', '.join(issues)} after {ATTEMPTS} attempts")


def scripts_file(group: str) -> Path:
    return folder(group) / "scripts.json"


def existing() -> dict[int, dict]:
    out = {}
    for group in zone_list.GROUPS:
        for key, script in ((storage.read_json(scripts_file(group)) or {}).get(SECTION) or {}).items():
            out[int(key)] = script
    return out


def save(group: str, area: int, script: dict) -> None:
    with _lock:
        path = scripts_file(group)
        data = storage.read_json(path) or {"schema": 1}
        section = data.setdefault(SECTION, {})
        section[str(area)] = script
        data[SECTION] = storage.by_id(section)
        storage.write_json(path, data)


def generate(areas: list[int] | None = None, force: bool = False, call=claude_json, bare: bool = False,
             parallel: int = PARALLEL, log=print) -> dict:
    """Writes the missing introductions (or those of `areas`, again). Returns {"written", "failed", "skipped"}."""
    known = zone_list.zones()
    unknown = [a for a in areas or [] if a not in known]
    if unknown:
        raise SystemExit(f"unknown zone(s) {unknown}: python -m pipeline.zone_intros list")
    done = existing()
    todo = [a for a in (areas or known) if force or areas or a not in done]
    report = {"written": 0, "failed": [], "skipped": len(known) - len(todo) if not areas else 0}
    if not todo:
        log("every zone has its introduction (--force or --zone to write one again)")
        return report
    registries = zone_list._registries(storage.ZONES_DIR)
    log(f"writing {len(todo)} introduction(s) with {MODEL}")

    def job(area):
        dossier = zone_list.dossier(area, registries=registries)
        return area, write_one(dossier, call, bare)

    with ThreadPoolExecutor(max_workers=max(1, parallel)) as pool:
        futures = [pool.submit(job, a) for a in todo]
        for future in as_completed(futures):
            try:
                area, script = future.result()
            except LLMLimit:
                for f in futures:
                    f.cancel()
                raise
            except LLMError as err:
                report["failed"].append(str(err))
                log(f"failed: {err}")
                continue
            save(known[area]["group"], area, script)
            report["written"] += 1
            log(f"{area} {script['name']}: {len(script['text'].split())} words, "
                f"{script['generator']['attempts']} attempt(s)")
    return report
