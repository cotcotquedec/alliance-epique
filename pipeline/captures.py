"""In-game captures (D1): read the addon's SavedVariables file (read-only) and compare what the game showed with the
base. The file is Lua: Lua 5.1 itself reads it (.data/lua-5.1.5, else LuaJIT of .luarocks, else `lua` on the PATH) and
prints it as JSON; nothing is ever written next to the game.

- `gossip <SavedVariables>`: spike S11, the NPCs' dialogue texts captured at GOSSIP_SHOW
  (ForeverSpeechCaptures.gossip) matched against the base's dialogue pages (data/zones/**/dialogues.json) with the
  index v9 rule (pipeline/match.py): exact, fuzzy (score >= 0.7), or none (NPC absent from the base, or text that
  differs). Player names are never printed.

    python -m pipeline.captures gossip "/Volumes/Games/.../SavedVariables/ForeverSpeech.lua" [--json]
"""

from __future__ import annotations

import argparse
import collections
import json
import shutil
import subprocess
import sys
from pathlib import Path

from pipeline import storage
from pipeline.match import THRESHOLD, from_markup, match_page, player_phrases, words

LUA_CANDIDATES = (storage.REPO_ROOT / ".data" / "lua-5.1.5" / "src" / "lua",
                  storage.REPO_ROOT / ".luarocks" / "bin" / "luajit")

# A small JSON writer in Lua 5.1: a table whose keys are 1..n is an array, any other an object.
_DUMP = r"""
local path, name = arg[1], arg[2]
dofile(path)
local function esc(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == '\\' then return '\\\\' end
    return string.format('\\u%04x', c:byte())
  end) .. '"'
end
local function dump(v, out)
  local t = type(v)
  if t == 'table' then
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    if n > 0 and #v == n then
      out[#out + 1] = '['
      for i = 1, n do if i > 1 then out[#out + 1] = ',' end dump(v[i], out) end
      out[#out + 1] = ']'
    else
      out[#out + 1] = '{'
      local first = true
      for k, x in pairs(v) do
        if not first then out[#out + 1] = ',' end
        first = false
        out[#out + 1] = esc(tostring(k)) .. ':'
        dump(x, out)
      end
      out[#out + 1] = '}'
    end
  elseif t == 'string' then out[#out + 1] = esc(v)
  elseif t == 'number' then out[#out + 1] = string.format('%.14g', v)
  elseif t == 'boolean' then out[#out + 1] = tostring(v)
  else out[#out + 1] = 'null' end
end
local out = {}
dump(_G[name], out)
io.write(table.concat(out))
"""


def lua() -> str:
    for path in LUA_CANDIDATES:
        if path.is_file():
            return str(path)
    found = shutil.which("lua5.1") or shutil.which("luajit") or shutil.which("lua")
    if not found:
        raise SystemExit("no Lua 5.1 interpreter: tools/prepare_db.sh builds .data/lua-5.1.5")
    return found


def load(path: Path, name: str = "ForeverSpeechCaptures") -> dict:
    """One global table of a SavedVariables file, as JSON data (the file is only read)."""
    proc = subprocess.run([lua(), "-e", _DUMP.replace("arg[1]", repr(str(path))).replace("arg[2]", repr(name))],
                          capture_output=True, text=True, encoding="utf-8")
    if proc.returncode:
        raise SystemExit(f"Lua could not read {path}: {proc.stderr.strip()}")
    return json.loads(proc.stdout or "null") or {}


def base_pages(zones_dir: Path | None = None, voices: dict | None = None) -> dict[int, list[dict]]:
    """NPC -> its base dialogue pages [{page, words (every token), text}] over all categories."""
    out: dict[int, list[dict]] = {}
    for path in sorted((zones_dir or storage.ZONES_DIR).glob("**/dialogues.json")):
        for nid, npc in ((storage.read_json(path) or {}).get("npcs") or {}).items():
            female = ((((voices or {}).get(nid) or {}).get("persona") or {}).get("sex")) == "female"
            for page in npc.get("pages", []):
                for text in filter(None, (page["text"], page.get("text_female"))):
                    out.setdefault(int(nid), []).append({"page": page["id"], "text": text,
                                                         "words": words(from_markup(text), None),
                                                         "female_text": text is page.get("text_female"),
                                                         "female_npc": female})
    return out


def gossip(captures: dict, pages: dict[int, list[dict]]) -> dict:
    """S11: every captured gossip text against the base pages of its NPC."""
    rows, counts = [], collections.Counter()
    for unit, seen in sorted((captures.get("gossip") or {}).items()):
        for cap in seen if isinstance(seen, list) else [seen]:
            npc = cap.get("npcID")
            drop = player_phrases(cap.get("playerName"), cap.get("playerClass"), cap.get("playerRace"))
            base = pages.get(npc) if isinstance(npc, int) else None
            if not base:
                verdict, best, score = "npc_absent", None, 0.0
            else:
                index, score, exact = match_page(cap.get("text") or "", base, drop)
                verdict = "exact" if exact else "fuzzy" if index is not None else "differs"
                best = base[index]["page"] if index is not None else None
            counts[verdict] += 1
            rows.append({"unit": unit, "npc": npc, "name": cap.get("name"), "api": cap.get("api"),
                         "verdict": verdict, "page": best, "score": round(score, 3), "text": cap.get("text"),
                         "npc_pages": len(base or [])})
    apis = collections.Counter(r["api"] for r in rows)
    npcs = {r["npc"] for r in rows}
    return {"captures": len(rows), "npcs": len(npcs), "apis": dict(apis), "verdicts": dict(counts),
            "npcs_absent": len({r["npc"] for r in rows if r["verdict"] == "npc_absent"}), "threshold": THRESHOLD,
            "rows": rows}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m pipeline.captures", description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="command", required=True)
    p = sub.add_parser("gossip", help="spike S11: captured dialogue texts against the base")
    p.add_argument("savedvariables", type=Path)
    p.add_argument("--json", action="store_true")
    p.add_argument("--rows", action="store_true", help="every capture (texts, never the player's name)")
    args = ap.parse_args(argv)
    voices = (storage.read_json(storage.DATA_DIR / "voices.json") or {}).get("npcs") or {}
    report = gossip(load(args.savedvariables), base_pages(voices=voices))
    if args.json:
        print(json.dumps(report if args.rows else {k: v for k, v in report.items() if k != "rows"},
                         ensure_ascii=False, indent=1))
        return 0
    print(f"{report['captures']} captures of {report['npcs']} NPCs, APIs {report['apis']}")
    print(f"verdicts: {report['verdicts']} ({report['npcs_absent']} NPCs absent from the base)")
    if args.rows:
        for r in report["rows"]:
            print(f"{r['verdict']:<10} {r['score']:.2f} {r['npc']} {r['name']}: {r['text'][:90]!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
