"""Voice bench: THE local listening page over the live data (2026-10-07), for every check by ear. One zone at a time
(always one, the Forêt d'Elwynn by default: the whole game is never loaded), then a view:
- quest readings (readings loop): each reading of the zone with its state (in place, not found in this run, being
  tried, to do, waiting for its NPC's model voice), its audio or best failed take, the judge's scores and the NPC's
  model voice to compare; filters by state, NPC and kind (start, end);
- model voices (voice loop): each NPC's Qwen3 voice or best failed take, with the judge's scores.
- Elise (2026-10-10): every line of the narrator (the Elise loop), her voice, each line's audio or best refused
  take, filtered and paged by the server;
- refused readings (2026-10-09), over every category, filtered and paged by the server: each reading's best refused
  take;
- NPC dialogues (2026-10-10): every dialogue page over the game (the dialogues loop), paged by the server.
Every audio shows the same life cycle (pipeline/review.py: todo, in_progress, refused, validated) and the user's
decisions: validate a refused audio, refuse a validated one, delete one (made again by the next pass).

The page (tools/voices/bench.html) asks this server for the data on every load or refresh, read from the JSON files
(data/voices.json, data/zones/**/{npcs,scripts,audio,readings}.json): it follows the loops while they run. Stdlib
only; listens on 127.0.0.1 and serves only the page, its API and the audio under data/voices/samples/ and
data/audio/ (masters: every browser plays FLAC, not every one Ogg).

    .venv/bin/python -m tools.voices.bench [--port 8765]     # then open http://127.0.0.1:8765
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import re
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from tools.qwen_voices.frame import race_of
from pipeline import review
from tools.readings import frame as reading_frame
from tools.readings import judge as reading_judge
from tools.readings import oracle as reading_oracle
from tools.voices import judge, oracle

PAGE = Path(__file__).with_name("bench.html")
SAMPLES = judge.ROOT / "data" / "voices" / "samples"
MEDIA = (SAMPLES, judge.ROOT / "data" / "audio")  # the only folders whose audio is served
DEFAULT_ZONE = "eastern-kingdoms/elwynn-forest"
ACCENTS = judge.ROOT / "data" / "accents.json"
RANGE = re.compile(r"bytes=(\d*)-(\d*)")


def _read(path: Path, default=None):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def _audio(path: Path | str | None) -> str | None:
    """URL of an audio file under MEDIA, if it exists."""
    if not path:
        return None
    path = judge.ROOT / path if not Path(path).is_absolute() else Path(path)
    if not path.is_file() or not any(path.is_relative_to(m) for m in MEDIA):
        return None
    return "/media/" + urllib.parse.quote(str(path.relative_to(judge.ROOT)))


def zone_name(key: str) -> str:
    if key == "@elise/levels":  # Elise's level-up lines (pipeline/level_lines/)
        return "Répliques de niveau"
    if key == "@elise/companions":  # Elise's companion lines (pipeline/companion_lines/)
        return "Répliques des compagnons"
    if key.endswith("/@intros"):  # Elise's zone introductions (pipeline/zone_intros/)
        return "Présentations des zones (" + ("Kalimdor" if key.startswith("kalimdor") else "Royaumes de l'Est") + ")"
    return (_read(oracle.zones_dir() / key / "npcs.json", {}) or {}).get("zone_name") or key


def npc_view(n: str, record: dict, accents: dict) -> dict:
    entry, persona = record.get("qwen") or {}, record.get("persona") or {}
    state = oracle.settled(entry) or ("pending" if entry.get("tries") else "new")
    race = race_of(record, accents)
    best = entry.get("best") or {}
    return {
        "id": int(n), "name": record["name"], "title": record.get("title"),
        "race": race or "?", "race_fr": accents["races"][race]["name_fr"] if race else "race inconnue",
        "sex": persona.get("sex"), "age": persona.get("age"), "status": state, "tries": entry.get("tries", 0),
        "campaign_tries": entry.get("campaign_tries", 0),
        "voice": {"src": _audio(entry.get("ref")), "seed": entry.get("seed"), "scores": entry.get("scores"),
                  "created_at": entry.get("created_at")} if state == "ok" else None,
        "best": {"src": _audio(best.get("take")), "seed": best.get("seed"), "scores": best.get("scores"),
                 "failed": best.get("failed", [])} if best and state != "ok" else None,
        "text": (record.get("voice_text") or {}).get("text") or persona.get("sample_line"),
        "text_source": (record.get("voice_text") or {}).get("source") or "persona.sample_line",
        "instruct": entry.get("instruct") or best.get("instruct"),
        "summary": persona.get("summary"),
    }


READING_ORDER = {"not_found": 0, "pending": 1, "todo": 2, "waiting_voice": 3, "ok": 4}


def reading_view(unit: dict, audio: dict, state: dict, voices: dict) -> dict:
    item = ((audio.get(reading_judge.SECTION[unit["kind"]]) or {}).get(str(unit["quest"])) or {}).get(unit["sex"]) or {}
    entry, record = state.get(unit["id"]) or {}, voices.get(str(unit["npc"])) or {}
    status = reading_oracle.settled(unit, audio, {"readings": state}) or (
        "waiting_voice" if not reading_oracle.has_voice(voices, unit["npc"]) else
        "pending" if entry.get("tries") else "todo")
    best = entry.get("best") or {}
    in_place = status == "ok"
    return {
        "id": unit["id"], "quest": unit["quest"], "kind": unit["kind"], "sex": unit["sex"], "name": unit["name"],
        "npc": unit["npc"], "npc_name": record.get("name") or str(unit["npc"]), "status": status, "text": unit["text"],
        "tries": entry.get("tries", 0), "campaign_tries": entry.get("campaign_tries", 0),
        "reading": {"src": _audio(item.get("master")), "seed": item.get("seed"),
                    "scores": item.get("scores")} if in_place else None,
        "best": {"src": _audio(best.get("take")), "seed": best.get("seed"), "scores": best.get("scores"),
                 "failed": best.get("failed", [])} if best and not in_place else None,
        "voice": _audio((record.get("qwen") or {}).get("ref")) if reading_oracle.has_voice(voices, unit["npc"]) else None,
        "rkind": "reading", "unit": unit["id"], "in_game": bool(item.get("refused")),
    }


def decisions() -> dict[tuple, dict]:
    """The control page's decisions still waiting (pipeline/review.py), by (kind, zone, unit)."""
    return {(d["kind"], d.get("zone"), d["unit"]): d for d in review.pending()}


class Bench:
    def __init__(self):
        self.order = oracle.zones_in_order()  # level order: read once (a few seconds)

    def zones(self) -> list[dict]:
        voices = _read(judge.VOICES_FILE)["npcs"]
        out = []
        for key in self.order:
            ids = [n for n in oracle.zone_npcs(key) if oracle.speaks(voices.get(n))]
            if not ids:
                continue
            states = [oracle.settled(voices[n].get("qwen")) for n in ids]
            r = reading_oracle.zone_readings(key, voices)
            out.append({"key": key, "name": zone_name(key), "speakers": len(ids), "ok": states.count("ok"),
                        "not_found": states.count("not_found"), "readings": r["ok"] + r["not_found"]
                        + r["waiting_voice"] + len(r["todo"]), "readings_ok": r["ok"],
                        "readings_not_found": r["not_found"]})
        return out

    def readings(self, key: str) -> dict:
        voices = _read(judge.VOICES_FILE)["npcs"]
        folder = oracle.zones_dir() / key
        units = reading_frame.units(_read(folder / "scripts.json"))
        audio, state = _read(folder / "audio.json", {}), _read(folder / "readings.json", {}).get("readings", {})
        waiting = decisions()
        rows = [{**reading_view(u, audio, state, voices), "zone": key} for u in units]
        for r in rows:
            r["decision"] = waiting.get(("reading", key, r["unit"]))
        return {"key": key, "name": zone_name(key), "readings": rows,
                "thresholds": {"en": judge.MAX_EN, "wer": judge.MAX_WER, "cps": judge.CPS,
                               "sim": reading_judge.MIN_SIM, "max_tries": reading_judge.MAX_TRIES}}

    def rejected(self, query: dict) -> dict:
        """The refused readings of the whole game (best refused take kept), filtered and paged on the server:
        zone, npc, kind, reason (a failed criterion), status (check: pending and not found; pending; not_found;
        decided: a decision of the user waits), q (quest or NPC name), sort (near: closest to passing first; zone: level
        order), page, per."""
        get = lambda k, d="": query.get(k, [d])[0]  # noqa: E731
        voices, waiting = _read(judge.VOICES_FILE)["npcs"], decisions()
        rows = []
        for key in self.order:
            folder = oracle.zones_dir() / key
            state = _read(folder / "readings.json", {}).get("readings", {})
            if not any(e.get("best") for e in state.values()):
                continue
            units = reading_frame.units(_read(folder / "scripts.json"))
            audio = _read(folder / "audio.json", {})
            for u in units:
                if not (state.get(u["id"]) or {}).get("best"):
                    continue
                r = reading_view(u, audio, state, voices)
                if r["best"] and r["status"] in ("pending", "not_found"):
                    rows.append({**r, "zone": key, "decision": waiting.get(("reading", key, u["id"]))})
        zone, npc, kind, reason = get("zone"), get("npc"), get("kind"), get("reason")
        status, q = get("status", "check"), get("q").strip().lower()
        facets = {"zones": {}, "reasons": {}}

        def keep(r, skip=""):
            return ((skip == "zone" or not zone or r["zone"] == zone) and (not npc or str(r["npc"]) == npc)
                    and (not kind or r["kind"] == kind)
                    and (skip == "reason" or not reason or reason in r["best"]["failed"])
                    and (status == "check" or (status == "decided" and r["decision"])
                         or (status in ("pending", "not_found") and r["status"] == status))
                    and (not q or q in r["name"].lower() or q in r["npc_name"].lower()))
        for r in rows:
            if keep(r, "zone"):
                facets["zones"][r["zone"]] = facets["zones"].get(r["zone"], 0) + 1
            if keep(r, "reason"):
                for f in r["best"]["failed"]:
                    facets["reasons"][f] = facets["reasons"].get(f, 0) + 1
        shown = [r for r in rows if keep(r)]
        if get("sort", "near") == "near":
            shown.sort(key=lambda r: reading_judge.badness(r["best"]["scores"]))
        per = max(1, min(int(get("per", "20") or 20), 100))
        pages = max(1, -(-len(shown) // per))
        page = max(1, min(int(get("page", "1") or 1), pages))
        return {"items": shown[(page - 1) * per: page * per], "total": len(shown), "page": page, "pages": pages,
                "all": len(rows), "decided": sum(1 for r in rows if r["decision"]),
                "facets": {"zones": [{"key": k, "name": zone_name(k), "count": facets["zones"][k]}
                                     for k in self.order if k in facets["zones"]],
                           "reasons": facets["reasons"]},
                "thresholds": {"en": judge.MAX_EN, "wer": judge.MAX_WER, "cps": judge.CPS,
                               "sim": reading_judge.MIN_SIM, "max_tries": reading_judge.MAX_TRIES}}

    def elise(self, query: dict) -> dict:
        """Elise's lines over every category (the Elise loop, tools/elise/), filtered and paged on the server: zone,
        kind (detail, complete, zone; quest: detail and complete), status (validated, in_progress, refused, todo; empty:
        all), q (quest name or text), page, per. With her voice
        (reference take) and the counts by status."""
        from tools.elise import frame as elise_frame, judge as elise_judge, oracle as elise_oracle
        get = lambda k, d="": query.get(k, [d])[0]  # noqa: E731
        voices = _read(judge.VOICES_FILE)["npcs"]
        voice = elise_judge.voice_id(voices)
        state = _read(elise_judge.STATE, {"lines": {}})
        rows, waiting = [], decisions()
        from pipeline import companion_lines, level_lines, zone_intros
        for key in zone_intros.keys(oracle.zones_dir()) + level_lines.keys(oracle.zones_dir()) \
                + companion_lines.keys(oracle.zones_dir()) + self.order:
            folder = oracle.zones_dir() / key
            units = elise_frame.units(_read(folder / "scripts.json"))
            if not units:
                continue
            audio = _read(folder / "audio.json", {})
            for u in units:
                entry = (state.get("lines") or {}).get(u["id"]) or {}
                status = review.status(elise_oracle.settled(u, audio, state, voice) or (
                    "pending" if entry.get("campaign_tries") else "todo"))
                item = ((audio.get(elise_judge.SECTION[u["kind"]]) or {}).get(str(u["quest"])) or {}).get(
                    u["sex"]) or {}
                best = entry.get("best") or {}
                rows.append({
                    "rkind": "elise", "unit": u["id"], "in_game": bool(item.get("refused")),
                    "decision": waiting.get(("elise", key, u["id"])),
                    "id": u["id"], "zone": key, "quest": u["quest"], "kind": u["kind"], "sex": u["sex"],
                    "name": u["name"], "text": u["text"], "status": status, "tries": entry.get("tries", 0),
                    "campaign_tries": entry.get("campaign_tries", 0),
                    "reading": {"src": _audio(item.get("master")), "seed": item.get("seed"),
                                "scores": item.get("scores")} if status == "validated" else None,
                    "best": {"src": _audio(best.get("take")), "scores": best.get("scores"),
                             "failed": best.get("failed", [])} if best and status != "validated" else None,
                })
        zone, kind, status, q = get("zone"), get("kind"), get("status"), get("q").strip().lower()
        keep = lambda r, skip="": ((skip == "zone" or not zone or r["zone"] == zone)  # noqa: E731
                                   and (not kind or r["kind"] == kind
                                        or (kind == "quest" and r["kind"] in ("detail", "complete")))
                                   and (skip == "status" or not status or r["status"] == status)
                                   and (not q or q in r["name"].lower() or q in r["text"].lower()))
        counts, zones = {}, {}
        for r in rows:
            if keep(r, "status"):
                counts[r["status"]] = counts.get(r["status"], 0) + 1
            if keep(r, "zone"):
                zones[r["zone"]] = zones.get(r["zone"], 0) + 1
        shown = [r for r in rows if keep(r)]
        per = max(1, min(int(get("per", "20") or 20), 100))
        pages = max(1, -(-len(shown) // per))
        page = max(1, min(int(get("page", "1") or 1), pages))
        record = (voices.get(str(elise_judge.narrator.NARRATOR_ID)) or {})
        eleven = record.get("elevenlabs") or {}
        return {"items": shown[(page - 1) * per: page * per], "total": len(shown), "page": page, "pages": pages,
                "all": len(rows), "counts": counts,
                "facets": {"zones": [{"key": k, "name": zone_name(k), "count": zones[k]}
                                     for k in self.order if k in zones]},
                "voice": {"name": record.get("name"), "account_name": eleven.get("account_name"),
                          "voice_id": voice, "model": eleven.get("tts_model"), "src": _audio(eleven.get("ref")),
                          "text": eleven.get("text")},
                "thresholds": {"en": judge.MAX_EN, "wer": judge.MAX_WER, "cps": judge.CPS,
                               "max_tries": elise_judge.MAX_TRIES}}

    def dialogues(self, query: dict) -> dict:
        """The NPCs' dialogue pages over every category (the dialogues loop, tools/dialogues/), filtered and paged on
        the server: zone, status (validated, in_progress, refused, todo, waiting_voice), q (NPC or text), page, per."""
        from tools.dialogues import frame as dialogue_frame, judge as dialogue_judge, oracle as dialogue_oracle
        get = lambda k, d="": query.get(k, [d])[0]  # noqa: E731
        voices, waiting, rows = _read(judge.VOICES_FILE)["npcs"], decisions(), []
        for key in self.order:
            folder = oracle.zones_dir() / key
            units = dialogue_frame.units(_read(folder / "scripts.json"))
            if not units:
                continue
            audio = _read(folder / "dialogue_audio.json", {})
            state = _read(folder / "dialogue_readings.json", {"readings": {}})
            for u in units:
                entry = (state.get("readings") or {}).get(u["id"]) or {}
                loop = dialogue_oracle.settled(u, audio, state) or (
                    "waiting_voice" if not dialogue_oracle.has_voice(voices, u["npc"]) else
                    "pending" if entry.get("tries") else "todo")
                item = ((audio.get(dialogue_judge.SECTION) or {}).get(u["key"]) or {}).get(u["sex"]) or {}
                best, record = entry.get("best") or {}, voices.get(str(u["npc"])) or {}
                rows.append({
                    "rkind": "dialogue", "unit": u["id"], "zone": key, "id": u["id"], "npc": u["npc"],
                    "npc_name": u["name"], "page": u["page"], "first": u["first"], "quests": u["quests"],
                    "sex": u["sex"], "text": u["text"], "status": review.status(loop), "loop_status": loop,
                    "tries": entry.get("tries", 0), "campaign_tries": entry.get("campaign_tries", 0),
                    "in_game": bool(item.get("refused")), "decision": waiting.get(("dialogue", key, u["id"])),
                    "reading": {"src": _audio(item.get("master")), "seed": item.get("seed"),
                                "scores": item.get("scores")} if loop == "ok" else None,
                    "best": {"src": _audio(best.get("take")), "scores": best.get("scores"),
                             "failed": best.get("failed", [])} if best and loop != "ok" else None,
                    "voice": _audio((record.get("qwen") or {}).get("ref"))})
        zone, status, q = get("zone"), get("status"), get("q").strip().lower()
        keep = lambda r, skip="": ((skip == "zone" or not zone or r["zone"] == zone)  # noqa: E731
                                   and (skip == "status" or not status or r["status"] == status)
                                   and (not q or q in r["npc_name"].lower() or q in r["text"].lower()))
        counts, zones = {}, {}
        for r in rows:
            if keep(r, "status"):
                counts[r["status"]] = counts.get(r["status"], 0) + 1
            if keep(r, "zone"):
                zones[r["zone"]] = zones.get(r["zone"], 0) + 1
        shown = [r for r in rows if keep(r)]
        per = max(1, min(int(get("per", "20") or 20), 100))
        pages = max(1, -(-len(shown) // per))
        page = max(1, min(int(get("page", "1") or 1), pages))
        return {"items": shown[(page - 1) * per: page * per], "total": len(shown), "page": page, "pages": pages,
                "counts": counts, "facets": {"zones": [{"key": k, "name": zone_name(k), "count": zones[k]}
                                                      for k in self.order if k in zones]},
                "thresholds": {"en": judge.MAX_EN, "wer": judge.MAX_WER, "cps": judge.CPS,
                               "sim": reading_judge.MIN_SIM, "max_tries": dialogue_judge.MAX_TRIES}}

    def zone(self, key: str) -> dict:
        voices, accents = _read(judge.VOICES_FILE)["npcs"], _read(ACCENTS)
        ids = [n for n in oracle.zone_npcs(key) if oracle.speaks(voices.get(n))]
        waiting = decisions()
        npcs = [{**npc_view(n, voices[n], accents), "rkind": "voice", "unit": n, "zone": None,
                 "decision": waiting.get(("voice", None, n))} for n in ids]
        return {"key": key, "name": zone_name(key), "npcs": npcs,
                "thresholds": {"en": judge.MAX_EN, "wer": judge.MAX_WER, "cps": judge.CPS,
                               "max_tries": judge.MAX_TRIES}}


def handler(bench: Bench):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):  # quiet
            pass

        def _send(self, code: int, body: bytes, kind: str, extra: dict | None = None):
            self.send_response(code)
            self.send_header("Content-Type", kind)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            for k, v in (extra or {}).items():
                self.send_header(k, v)
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)

        def _json(self, value):
            self._send(200, json.dumps(value, ensure_ascii=False).encode(), "application/json; charset=utf-8")

        def _file(self, path: Path):
            """Audio, with byte ranges (Safari needs them to play)."""
            data, kind = path.read_bytes(), mimetypes.guess_type(path.name)[0] or "application/octet-stream"
            match = RANGE.fullmatch(self.headers.get("Range", ""))
            if not match:
                return self._send(200, data, kind, {"Accept-Ranges": "bytes"})
            start = int(match[1]) if match[1] else max(len(data) - int(match[2] or 0), 0)
            end = min(int(match[2]), len(data) - 1) if match[1] and match[2] else len(data) - 1
            self._send(206, data[start:end + 1], kind,
                       {"Accept-Ranges": "bytes", "Content-Range": f"bytes {start}-{end}/{len(data)}"})

        def do_GET(self):
            url = urllib.parse.urlparse(self.path)
            try:
                if url.path == "/":
                    return self._send(200, PAGE.read_bytes(), "text/html; charset=utf-8")
                if url.path == "/api/zones":
                    return self._json({"default": DEFAULT_ZONE, "zones": bench.zones()})
                if url.path == "/api/zone":
                    key = urllib.parse.parse_qs(url.query).get("key", [""])[0]
                    if key not in bench.order:
                        return self._send(404, b"unknown zone", "text/plain")
                    return self._json(bench.zone(key))
                if url.path == "/api/readings":
                    key = urllib.parse.parse_qs(url.query).get("key", [""])[0]
                    if key not in bench.order:
                        return self._send(404, b"unknown zone", "text/plain")
                    return self._json(bench.readings(key))
                if url.path == "/api/dialogues":
                    return self._json(bench.dialogues(urllib.parse.parse_qs(url.query)))
                if url.path == "/api/elise":
                    return self._json(bench.elise(urllib.parse.parse_qs(url.query)))
                if url.path == "/api/rejected":
                    return self._json(bench.rejected(urllib.parse.parse_qs(url.query)))
                if url.path.startswith("/media/"):
                    path = (judge.ROOT / urllib.parse.unquote(url.path[len("/media/"):])).resolve()
                    if any(path.is_relative_to(m.resolve()) for m in MEDIA) and path.is_file():
                        return self._file(path)
                self._send(404, b"not found", "text/plain")
            except (BrokenPipeError, ConnectionResetError):
                pass

        do_HEAD = do_GET

        def do_POST(self):
            """The control page's decisions (pipeline/review.py): /api/decide {kind, zone, unit, action},
            /api/cancel {kind, zone, unit}."""
            url = urllib.parse.urlparse(self.path)
            try:
                body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
                kind, zone, unit = str(body.get("kind", "")), body.get("zone") or None, str(body.get("unit", ""))
                if kind not in review.KINDS or not unit or (zone is not None and zone not in bench.order):
                    return self._send(400, b"kind, zone and unit expected", "text/plain")
                if url.path == "/api/decide":
                    return self._json(review.decide(kind, zone, unit, str(body.get("action", ""))))
                if url.path == "/api/cancel":
                    return self._json({"cancelled": review.cancel(kind, zone, unit)})
                self._send(404, b"not found", "text/plain")
            except ValueError as e:
                self._send(409, str(e).encode(), "text/plain; charset=utf-8")
            except (BrokenPipeError, ConnectionResetError):
                pass

    return Handler


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--port", type=int, default=8765)
    args = ap.parse_args(argv)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler(Bench()))
    print(f"voice bench: http://127.0.0.1:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
