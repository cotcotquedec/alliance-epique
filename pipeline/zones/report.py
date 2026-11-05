"""Completion report, category by category, read from the data files only (no network, no paid call).

    python -m pipeline.zones report (--all | --group G [--category C]...) [--todo] [--full] [--json]
    tools/report.sh --group eastern-kingdoms --category elwynn-forest

Per category (a Wowhead quest category within its group, D12), Alliance quests (or both sides), whatever their
level:
- NPCs: those who speak a text (the giver of a quest, the ender of a completion text); then how many have a persona
  and a model voice (Qwen3, validated by the voice loop's judge, tools/voices);
- quests found; start and end scripts written, then start and end audio, each over what can be voiced
  (a French text and an NPC speaker; narrator quests, D9, and quests without text are left out).
Also what cannot be voiced yet: quests without a French text (start or end; an in-game capture will bring
it) and quests without an NPC speaker (narrator voice, D9).
A category is a Wowhead quest category within its group (tools/loop/scope.py): --all, a group, or some categories
of a group. Only the table is printed; with --todo, the list of what is left to do follows it, quest by quest and
NPC by NPC.

Reading the table: PNJ, those who say a text (giver, ender), each counted once in the total even if it speaks in
several categories. Scripts and audio: done / possible; a quest is possible only with a French text and an NPC
(otherwise: Sans FR, an in-game capture will bring it; Sans PNJ, narrator, D9). Voix: model voice validated by the
voice loop. %: personas and voices over the NPCs, scripts and audio over the possible ones, Sans FR and Sans PNJ
over the quests.
"""

from __future__ import annotations

import json
import statistics

from pipeline import storage
from pipeline import scripts
from pipeline.personas import generate as personas
from pipeline.zones import catalog as zones

SIDE = "alliance"
AUDIO_SECTION = {"detail": "audio", "complete": "complete"}  # section of a zone's audio.json for each kind
COLUMNS = [("zone", "Catégorie"), ("npcs", "PNJ"), ("personas", "Fiches"), ("qwen", "Voix"),
           ("quests", "Quêtes"), ("scripts_start", "Script début"), ("scripts_end", "Script fin"),
           ("audio_start", "Audio début"), ("audio_end", "Audio fin"), ("no_french", "Sans FR"),
           ("narrator", "Sans PNJ")]
SHOWN = 12  # items per to-do line without --full


def fetched_zones(side_only: bool = False) -> list[str]:
    """Keys of the zones with a quest registry, lowest median level of their Alliance quests first (the
    loops' order). side_only: only the zones that have Alliance quests (or quests of both sides)."""
    from pipeline.zones.__main__ import selected
    found = []
    for path in storage.ZONES_DIR.glob("**/quests.json"):
        key = str(path.parent.relative_to(storage.ZONES_DIR))
        quests = [q for q in (storage.read_json(path) or {}).get("quests", {}).values() if selected(q, SIDE, None)]
        if side_only and not quests:
            continue
        levels = [q["level"] for q in quests if isinstance(q.get("level"), int) and q["level"] > 0]
        found.append((statistics.median(levels) if levels else 99, key))
    return [key for _, key in sorted(found)]


def pick(all_keys: list[str], wanted: list[str] | None) -> list[str]:
    """The categories of `all_keys` (level order) that are wanted (keys from tools/loop/scope.py; None: all)."""
    if wanted is None:
        return all_keys
    picked = [k for k in all_keys if k in wanted]
    missing = [w for w in wanted if w not in all_keys]
    if missing:
        raise SystemExit(f"zone not fetched (no quests.json): {', '.join(missing)}")
    return picked


def qwen_ok(record: dict | None) -> bool:
    """A Qwen3 model voice validated by the voice loop's judge (voices.json npcs[<npc>].qwen), by the voice
    oracle's own rule: status ok, scores within the judge's thresholds, file in place."""
    from tools.voices import oracle
    return oracle.settled((record or {}).get("qwen")) == "ok"


def zone_report(key: str, voices: dict) -> dict:
    from pipeline.zones.__main__ import _speakers, selected  # the same rules as the passes
    folder = zones.zone_dir(key)
    quests = (storage.read_json(folder / "quests.json") or {}).get("quests", {})
    picked = {k: q for k, q in quests.items() if selected(q, SIDE, None)}
    script_file, audio_file = storage.read_json(folder / "scripts.json"), storage.read_json(folder / "audio.json")
    speakers = _speakers(picked)
    with_persona = {n for n in speakers if str(n) in voices}
    with_qwen = {n for n in speakers if qwen_ok(voices.get(str(n)))}
    row = {"zone": key, "npcs": len(speakers), "personas": len(with_persona),
           "qwen": len(with_qwen), "quests": len(picked),
           "_ids": {"npcs": speakers, "personas": with_persona, "qwen": with_qwen}}
    no_french, narrator = set(), set()
    for kind, label in (("detail", "start"), ("complete", "end")):
        written = scripts.section(script_file, kind)
        jobs, skipped = scripts.plan(picked, voices, written, kind=kind)
        possible = len(jobs) + len(skipped["no_persona"]) + len(skipped["done"])
        done = [str(q) for q in skipped["done"]]
        audio = (audio_file or {}).get(AUDIO_SECTION[kind], {})
        row[f"scripts_{label}"] = (len(done), possible)
        row[f"audio_{label}"] = (sum(1 for k in done if (audio.get(k) or {}).get("m")), possible)
        no_french |= set(skipped["no_text"])
        narrator |= set(skipped[scripts.NO_SPEAKER[kind]])
    row["no_french"], row["narrator"] = len(no_french), len(narrator)
    return row


def zone_todo(key: str, voices: dict, npc_records: dict) -> list[tuple[str, list[str]]]:
    """What is left to do in a zone, in pipeline order: [(what, ["783 Menace intérieure", ...]), ...]
    (labels in French: shown to the user as they are)."""
    from pipeline.zones.__main__ import _speakers, selected
    folder = zones.zone_dir(key)
    quests = (storage.read_json(folder / "quests.json") or {}).get("quests", {})
    picked = {k: q for k, q in quests.items() if selected(q, SIDE, None)}
    script_file, audio_file = storage.read_json(folder / "scripts.json"), storage.read_json(folder / "audio.json")

    def quest(qid) -> str:
        return f"{qid} {picked[str(qid)].get('name') or '?'}"

    names = {}
    for q in picked.values():
        for s in q.get("starters", []) + q.get("enders", []):
            names.setdefault(s["id"], s.get("name"))

    def npc(nid) -> str:
        return f"{nid} {(npc_records.get(nid) or {}).get('name') or names.get(nid) or '?'}"

    speakers = sorted(_speakers(picked))
    out = [("PNJ absents des registres (relancer l'import de la base, tools/base/run.sh)",
            [npc(n) for n in speakers if n not in npc_records]),
           ("PNJ sans fiche de personnalité", [npc(n) for n in speakers if n in npc_records and str(n) not in voices]),
           ("PNJ sans voix modèle (boucle voix)", [npc(n) for n in speakers if str(n) in voices
                                                 and not qwen_ok(voices[str(n)])])]
    for kind, label in (("detail", "début"), ("complete", "fin")):
        written = scripts.section(script_file, kind)
        jobs, skipped = scripts.plan(picked, voices, written, kind=kind)
        audio = (audio_file or {}).get(AUDIO_SECTION[kind], {})
        out += [(f"{label} : quêtes sans texte français (capture en jeu)", [quest(q) for q in skipped["no_text"]]),
                (f"{label} : quêtes sans PNJ (narrateur, D9)",
                 [quest(q) for q in skipped[scripts.NO_SPEAKER[kind]]]),
                (f"{label} : scripts à écrire", [quest(j["quest"]["id"]) for j in jobs]
                 + [quest(q) + " (sans fiche)" for q in skipped["no_persona"]]),
                (f"{label} : audio à produire", [quest(q) for q in skipped["done"] if not (audio.get(str(q)) or {}).get("m")])]
    return out


def render_todo(key: str, todo: list[tuple[str, list[str]]], show_all: bool = False) -> str:
    lines = [f"Reste à faire, {key} :"]
    for what, items in todo:
        if not items:
            continue
        shown = items if show_all else items[:SHOWN]
        more = f" … (+{len(items) - len(shown)}, --full)" if len(items) > len(shown) else ""
        lines.append(f"- {what} ({len(items)}) : " + ", ".join(shown) + more)
    if len(lines) == 1:
        lines.append("- rien, la zone est complète")
    return "\n".join(lines)


def total(rows: list[dict]) -> dict:
    """Sums over the zones; NPCs are counted once even when they speak in several zones (class trainers,
    capital cities)."""
    out = {"zone": "TOTAL"}
    for name, _ in COLUMNS[1:]:
        if name in ("npcs", "personas", "qwen") and all("_ids" in r for r in rows):
            out[name] = len(set().union(*(r["_ids"][name] for r in rows)))
            continue
        values = [r[name] for r in rows]
        out[name] = tuple(map(sum, zip(*values))) if values and isinstance(values[0], tuple) else sum(values)
    return out


def _pct(part: int, whole: int) -> str:
    return f"{100 * part / whole:.0f} %" if whole else "-"


def percentages(t: dict) -> dict:
    """The TOTAL row as percentages: personas and voices over the NPCs, scripts and audio over what can be
    voiced, quests without French text or without NPC over the quests."""
    out = {"zone": "%"}
    for name, _ in COLUMNS[1:]:
        value = t[name]
        if isinstance(value, tuple):
            out[name] = _pct(*value)
        elif name in ("personas", "qwen"):
            out[name] = _pct(value, t["npcs"])
        elif name in ("no_french", "narrator"):
            out[name] = _pct(value, t["quests"])
        else:
            out[name] = "100 %"
    return out


def _cell(value) -> str:
    if isinstance(value, tuple):
        done, possible = value
        return f"{done}/{possible}" + (" ok" if possible and done == possible else "")
    return str(value)


def render(rows: list[dict]) -> str:
    t = total(rows)
    shown = rows + ([t] if len(rows) > 1 else []) + [percentages(t)]
    cells = [[title for _, title in COLUMNS]] + [[_cell(r[name]) for name, _ in COLUMNS] for r in shown]
    widths = [max(len(line[i]) for line in cells) for i in range(len(COLUMNS))]
    first_total = len(rows) + 1  # line index of TOTAL (or of % with one zone)
    lines = []
    for n, line in enumerate(cells):
        if n == first_total:
            lines.append("  ".join("-" * w for w in widths))
        lines.append("  ".join(c.ljust(w) if i == 0 else c.rjust(w) for i, (c, w) in enumerate(zip(line, widths))))
        if n == 0:
            lines.append("  ".join("-" * w for w in widths))
    return "\n".join(lines)


def main(wanted: list[str] | None = None, as_json: bool = False, todo: bool = False, show_all: bool = False) -> None:
    import signal
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)  # `tools/report.sh | head` ends quietly
    voices = personas.load_voices()["npcs"]
    keys = pick(fetched_zones(side_only=wanted is None), wanted)
    rows = [zone_report(key, voices) for key in keys]
    todos = {}
    if todo:
        npc_records, _, _ = personas.zone_registries(sorted(p.parent for p in storage.ZONES_DIR.glob("**/npcs.json")))
        todos = {key: zone_todo(key, voices, npc_records) for key in keys}
    if as_json:
        shown = [{k: v for k, v in r.items() if k != "_ids"} for r in rows]
        print(json.dumps({"zones": shown, "todo": {k: dict(v) for k, v in todos.items()}}, ensure_ascii=False, indent=1))
        return
    print(render(rows))  # the table only; the to-do lists with --todo
    for key, items in todos.items():
        print("\n" + render_todo(key, items, show_all))
