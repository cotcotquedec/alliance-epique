"""Quest scripts of a zone (data/zones/<zone>/scripts.json): the text each NPC reads.

Two kinds of script per quest, in two sections of the file:
- `scripts`: the acceptance text (kind "detail", D6), said by the quest giver;
- `complete`: the completion text (kind "complete", decided 2026-10-06), said by the NPC the quest is turned
  in to.

For every quest with that French text and an NPC speaker that has a persona, `text` is the text made impersonal
(pipeline/narration.py): player name and lone class removed, "camarade" after a word, stage directions out; only
the gender agreements stay, as `<masculine/feminine>` markers (`gendered`), read twice (D8). A text no NPC says
(quest started by an object or an item, turned in to an object) is said by the narrator, Elise (pipeline/narrator.py),
once her record is in data/voices.json.

`source` is the origin of the text read (2026-10-21): that of its description, else of its objectives, for a start
text, and of its completion for an end text, taken from the quest's `source.origins` (pipeline/foreverdb/origins.py:
`wowhead`, `capture`, `foreverdb:vmangos`...); `origins` gives each text read its own. Before, it was always
"wowhead_fr"; `python -m pipeline.foreverdb.origins` rewrites both in the existing scripts, never their text.

No acting direction since 2026-10-07: Qwen3 reads the plain text, so a script is computed here, without Claude.
Scripts written before keep their direction fields (`segments`, `overall`, `render`, `plain`, `target_cps`),
unused. An existing script is never rewritten, unless --force (that would redo its audio).
"""

from __future__ import annotations

from pathlib import Path

from pipeline import narrator, storage
from pipeline.narration import completion_template, speech_template

SCHEMA = 2  # 2 (2026-10-07): no acting direction
VERSION = "narration-1"  # generator of a script without direction
KINDS = ("detail", "complete")
SECTION = {"detail": "scripts", "complete": "complete"}  # section of scripts.json for each kind
NO_SPEAKER = {"detail": "no_npc_giver", "complete": "no_npc_ender"}
READ = {"detail": ("description", "objectives"), "complete": ("completion",)}  # the quest texts a script reads


def giver_npc(quest: dict) -> int | None:
    return next((s["id"] for s in quest.get("starters", []) if s.get("type") == "npc"), None)


def ender_npc(quest: dict) -> int | None:
    return next((s["id"] for s in quest.get("enders", []) if s.get("type") == "npc"), None)


def speaker(quest: dict, kind: str) -> int | None:
    return giver_npc(quest) if kind == "detail" else ender_npc(quest)


def text_template(quest: dict, kind: str) -> dict:
    if kind == "detail":
        return speech_template(quest.get("description"), quest.get("objectives"))
    return completion_template(quest.get("completion"))


def text_origins(quest: dict, kind: str) -> tuple[str, dict]:
    """(source, {field: origin}) of the texts a script reads: the first of READ[kind] that the quest has gives the
    source. A registry without `source.origins` falls back to the channel of the text (`source.texts`)."""
    src = quest.get("source") or {}
    known = {**(src.get("texts") or {}), **(src.get("origins") or {})}
    origins = {f: known.get(f) or "unknown" for f in READ[kind] if quest.get(f)}
    return next(iter(origins.values()), "unknown"), origins


def section(data: dict | None, kind: str) -> dict:
    """The scripts of one kind in a scripts.json (or audio.json-like) document."""
    return (data or {}).get(SECTION[kind], {})


def plan(quests: dict, voices: dict, existing: dict, force: bool = False,
         only: set[int] | None = None, kind: str = "detail") -> tuple[list[dict], dict[str, list[int]]]:
    """(scripts to write, skipped quest ids by reason) for one kind; `existing`: the scripts of that kind. A quest
    already scripted is kept even if its text or persona changed since (that would redo its audio); force=True
    writes it again."""
    jobs, skipped = [], {"no_text": [], NO_SPEAKER[kind]: [], "no_persona": [], "done": []}
    for key in sorted(quests, key=int):
        quest = quests[key]
        qid = int(key)
        if only and qid not in only:
            continue
        tpl = text_template(quest, kind)
        npc = speaker(quest, kind)
        if not tpl["text"]:
            skipped["no_text"].append(qid)
            continue
        if npc is None and str(narrator.NARRATOR_ID) in voices:
            npc = narrator.NARRATOR_ID  # D9: no NPC says it, the narrator does (once she has her record)
        if npc is None:
            skipped[NO_SPEAKER[kind]].append(qid)
            continue
        entry = voices.get(str(npc))
        if not entry:
            skipped["no_persona"].append(qid)
            continue
        if not force and str(qid) in existing:
            skipped["done"].append(qid)
            continue
        jobs.append({"quest": quest, "npc": npc, "entry": entry, "template": tpl, "kind": kind})
    return jobs, skipped


def script_record(job: dict) -> dict:
    quest, tpl = job["quest"], job["template"]
    source, origins = text_origins(quest, job.get("kind", "detail"))
    return {
        "quest_id": quest["id"],
        "kind": job.get("kind", "detail"),
        "name": quest.get("name"),
        "npc_id": job["npc"],
        "npc_name": job["entry"]["name"],
        **({"narrator": True} if narrator.is_narrator(job["npc"]) else {}),
        "source": source,
        "origins": origins,
        "text": tpl["text"],
        "gendered": tpl["gendered"],
        "stage_directions": tpl["directions"],
        "generator": {"version": VERSION, "at": storage.now()},
    }


def generate(folder: Path, jobs: list[dict], log=print) -> dict:
    """Writes the scripts of the jobs in the zone's scripts.json. A direction recorded as failed before
    2026-10-07 (scripts.json `failed`) is dropped once its quest has a script."""
    path = folder / "scripts.json"
    data = storage.read_json(path) or {"schema": SCHEMA, "scripts": {}}
    for job in jobs:
        qid, kind = str(job["quest"]["id"]), job.get("kind", "detail")
        data.setdefault(SECTION[kind], {})[qid] = script_record(job)
        ((data.get("failed") or {}).get(kind) or {}).pop(qid, None)
        log(f"  {qid} {kind} {job['quest'].get('name')} ({job['entry']['name']})")
    if jobs:
        for name in SECTION.values():
            if name in data:
                data[name] = storage.by_id(data[name])
        if not any((data.get("failed") or {}).values()):
            data.pop("failed", None)
        data["schema"] = SCHEMA
        data["updated_at"] = storage.now()
        storage.write_json(path, data)
    return {"generated": len(jobs)}


# --- NPC dialogues (2026-10-10) ------------------------------------------------------------------------------
# The text of each page of an NPC's dialogue window (data/zones/<zone>/dialogues.json, pipeline/foreverdb/
# dialogues.py), said by that NPC: scripts.json section "dialogues", keyed "<npc>_<page>". Same rules as a
# completion text (impersonal, `<masculine/feminine>` markers kept for the player's sex, D8); the page's female
# text when the NPC's persona is a woman and the database has one. Never without the NPC's persona.

DIALOGUES = "dialogues"


def dialogue_id(npc: int | str, page: str) -> str:
    return f"{npc}_{page}"


def plan_dialogues(dialogues: dict | None, voices: dict, existing: dict, force: bool = False,
                   only: set[int] | None = None) -> tuple[list[dict], dict[str, list[str]]]:
    """(dialogue scripts to write, skipped page ids by reason) for a zone's dialogues.json."""
    jobs, skipped = [], {"no_text": [], "no_persona": [], "done": []}
    for nid, npc in sorted(((dialogues or {}).get("npcs") or {}).items(), key=lambda kv: int(kv[0])):
        if only and int(nid) not in only:
            continue
        entry = voices.get(str(nid))
        female = ((entry or {}).get("persona") or {}).get("sex") == "female"
        for page in npc.get("pages", []):
            key = dialogue_id(nid, page["id"])
            tpl = completion_template(page.get("text_female") if female and page.get("text_female") else page["text"])
            if not tpl["text"]:
                skipped["no_text"].append(key)
            elif not entry:
                skipped["no_persona"].append(key)
            elif not force and key in existing:
                skipped["done"].append(key)
            else:
                jobs.append({"npc": int(nid), "entry": entry, "page": page, "template": tpl, "key": key})
    return jobs, skipped


def dialogue_record(job: dict) -> dict:
    page, tpl = job["page"], job["template"]
    return {"kind": "dialogue", "npc_id": job["npc"], "npc_name": job["entry"]["name"], "page": page["id"],
            "first": page.get("first", False), "quests": page.get("quests", []), "source": "foreverdb",
            "text": tpl["text"], "gendered": tpl["gendered"], "stage_directions": tpl["directions"],
            "generator": {"version": VERSION, "at": storage.now()}}


def generate_dialogues(folder: Path, jobs: list[dict], log=print) -> dict:
    path = folder / "scripts.json"
    data = storage.read_json(path) or {"schema": SCHEMA, "scripts": {}}
    section = data.setdefault(DIALOGUES, {})
    for job in jobs:
        section[job["key"]] = dialogue_record(job)
    if jobs:
        data[DIALOGUES] = dict(sorted(section.items(), key=lambda kv: [int(x) for x in kv[0].split("_")]))
        data["schema"] = SCHEMA
        data["updated_at"] = storage.now()
        storage.write_json(path, data)
        log(f"  {len(jobs)} dialogue page(s)")
    return {"generated": len(jobs)}
