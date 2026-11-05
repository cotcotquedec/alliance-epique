import json

import pytest

from pipeline import storage
from pipeline.wowhead.parse import parse_quest_menu
from pipeline.zones import catalog as zones

ELWYNN = "eastern-kingdoms/elwynn-forest"
MENU = 'WH.setPageData("menu.def.quests", ' + json.dumps([
    ["continents", "Continents", None, None, {"heading": True}],
    ["0", "Royaumes de l'Est", "/forever/fr/quests/eastern-kingdoms", [
        ["12", "Forêt d'Elwynn", "/forever/fr/quests/eastern-kingdoms/elwynn-forest"],
        ["2839", "Vallée d'Alterac", "/forever/fr/quests/eastern-kingdoms/alterac-valley"],
    ]],
    ["6", "Champs de bataille", "/forever/fr/quests/battlegrounds", [
        ["2597", "Vallée d'Alterac", "/forever/fr/quests/battlegrounds/alterac-valley"],
    ]],
    ["-2", "Non classés", "/forever/fr/quests/uncategorized"],
]) + ");"


@pytest.fixture
def data_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(storage, "ZONES_FILE", tmp_path / "zones.json")
    monkeypatch.setattr(storage, "ZONES_DIR", tmp_path / "zones")
    return tmp_path


def make_catalog():
    return zones.build_catalog(parse_quest_menu(MENU))


def test_menu_leaves_and_keys():
    catalog = make_catalog()
    assert list(catalog["zones"]) == [ELWYNN, "eastern-kingdoms/alterac-valley",
                                      "battlegrounds/alterac-valley", "uncategorized"]
    zone = catalog["zones"][ELWYNN]
    assert (zone["id"], zone["group"], zone["group_name"], zone["state"]) == (12, "eastern-kingdoms", "Royaumes de l'Est", "todo")


def test_rebuild_keeps_fetch_state():
    old = make_catalog()
    old["zones"][ELWYNN].update(state="fetched", summary={"quests": 76})
    new = zones.build_catalog(parse_quest_menu(MENU), old)
    assert new["zones"][ELWYNN]["state"] == "fetched" and new["zones"][ELWYNN]["summary"] == {"quests": 76}


@pytest.mark.parametrize("ref", [ELWYNN, "elwynn-forest", "12", "forêt d'elwynn"])
def test_resolve(ref):
    assert zones.resolve(make_catalog(), ref) == ELWYNN


def test_resolve_ambiguous_and_unknown():
    with pytest.raises(SystemExit, match="ambiguous"):
        zones.resolve(make_catalog(), "alterac-valley")
    with pytest.raises(SystemExit, match="unknown"):
        zones.resolve(make_catalog(), "nowhere")


def test_zone_order_by_median_level_of_the_side():
    from pipeline.zones.__main__ import zone_order
    listings = {
        "kalimdor/the-barrens": [{"side": 2, "level": 12}, {"side": 2, "level": 15}, {"side": 1, "level": 24}],
        "eastern-kingdoms/duskwood": [{"side": 1, "level": 20}, {"side": 3, "level": 25}, {"side": 1, "level": 30}],
        "eastern-kingdoms/elwynn-forest": [{"side": 1, "level": 2}, {"side": 3, "level": 5}, {"side": 1, "level": 60}],
        "kalimdor/durotar": [{"side": 2, "level": 4}],
        "eastern-kingdoms/empty": [],
    }
    order = zone_order(listings, "alliance")
    assert [z[0] for z in order] == ["eastern-kingdoms/elwynn-forest", "kalimdor/the-barrens",
                                     "eastern-kingdoms/duskwood"]  # Horde-only and empty zones left out
    assert order[0][1:] == (5.0, 3, 2, 60)  # no level filter: the level-60 quest is kept
    assert order[1][1:] == (24.0, 1, 24, 24)  # median of the Alliance quests only


def test_zone_progress_reads_the_data_files(data_dir, monkeypatch):
    from pipeline.zones import __main__ as cli
    folder = data_dir / "zones" / "eastern-kingdoms" / "westfall"
    folder.mkdir(parents=True)
    npc = [{"type": "npc", "id": 235}]
    quests = {"9": {"id": 9, "side": "alliance", "description": "Texte.", "objectives": "Faire.", "starters": npc},
              "10": {"id": 10, "side": "both", "description": "Texte.", "objectives": "Faire.", "starters": npc},
              "11": {"id": 11, "side": "horde", "description": "Texte.", "objectives": "Faire.", "starters": npc},
              "12": {"id": 12, "side": "alliance", "description": None, "objectives": None, "starters": npc}}
    storage.write_json(folder / "quests.json", {"quests": quests})
    assert cli.zone_progress("eastern-kingdoms/westfall", "alliance", {}) == {
        "quests": 3, "personas_todo": 1, "scripts_done": 0, "scripts_todo": 2, "unvoiceable": 1,
        "audio_done": 0, "audio_todo": 0}
    voices = {"235": {"name": "Gryan Stoutmantle", "persona": {"summary": "x"}}}
    storage.write_json(folder / "scripts.json", {"scripts": {"9": {"npc_id": 235}}})
    storage.write_json(folder / "audio.json", {"audio": {"9": {"m": {"master": "a.flac"}}}})
    p = cli.zone_progress("eastern-kingdoms/westfall", "alliance", voices)
    assert (p["personas_todo"], p["scripts_done"], p["scripts_todo"], p["audio_done"]) == (0, 1, 1, 1)
    assert cli.zone_progress("eastern-kingdoms/duskwood", "alliance", voices) is None  # not fetched
    # imported from the Forever Database, which has no quest there: nothing to do
    assert cli.zone_progress("eastern-kingdoms/duskwood", "alliance", voices, imported=True) == {
        "quests": 0, "personas_todo": 0, "scripts_done": 0, "scripts_todo": 0, "unvoiceable": 0,
        "audio_done": 0, "audio_todo": 0}


def test_claude_usage_limit_is_recognised():
    from pipeline.llm import LLMLimit, _failure
    assert isinstance(_failure("claude exited with 1: Claude AI usage limit reached|1791300000"), LLMLimit)
    assert isinstance(_failure("claude failed: error_during_execution You've hit your limit · resets 3pm"), LLMLimit)
    assert not isinstance(_failure("claude failed: error_max_turns"), LLMLimit)


def test_completion_report(data_dir, monkeypatch):
    from pipeline.zones import report
    folder = data_dir / "zones" / "eastern-kingdoms" / "westfall"
    folder.mkdir(parents=True)
    giver, ender = [{"type": "npc", "id": 235}], [{"type": "npc", "id": 7}]
    quests = {"9": {"id": 9, "level": 10, "side": "alliance", "description": "Texte.", "objectives": "Faire.",
                    "completion": "Merci.", "starters": giver, "enders": ender},
              "10": {"id": 10, "level": 12, "side": "both", "description": "Texte.", "objectives": "Faire.",
                     "completion": None, "starters": giver, "enders": giver},
              "11": {"id": 11, "level": 12, "side": "horde", "description": "Texte.", "objectives": "x",
                     "starters": [{"type": "npc", "id": 99}]}}
    storage.write_json(folder / "quests.json", {"quests": quests})
    storage.write_json(folder / "scripts.json", {"scripts": {"9": {}, "10": {}}, "complete": {"9": {}}})
    storage.write_json(folder / "audio.json", {"audio": {"9": {"m": {"file": "9_detail.ogg"}}}, "complete": {}})
    from tools.voices import judge
    monkeypatch.setattr(judge, "ROOT", data_dir)
    (data_dir / "ref.wav").write_bytes(b"RIFF")  # a validated model voice: scores within the thresholds, file there
    voices = {"235": {"persona": {"summary": "x"}},
              "7": {"persona": {"summary": "y"}, "qwen": {"status": "ok", "ref": "ref.wav",
                                                         "scores": {"en": 0, "wer": 0, "cps": 15}}}}
    assert report.pick(report.fetched_zones(), ["eastern-kingdoms/westfall"]) == ["eastern-kingdoms/westfall"]
    row = report.zone_report("eastern-kingdoms/westfall", voices)
    assert row.pop("_ids") == {"npcs": {235, 7}, "personas": {235, 7}, "qwen": {7}}
    assert row == {"zone": "eastern-kingdoms/westfall", "npcs": 2, "personas": 2, "qwen": 1, "quests": 2,
                   "scripts_start": (2, 2), "audio_start": (1, 2), "scripts_end": (1, 1), "audio_end": (0, 1),
                   "no_french": 1, "narrator": 0}  # quest 10 has no completion text
    table = report.render([row])
    assert "2/2 ok" in table and "1/2" in table and "Script fin" in table
    # an NPC speaking in two zones counts once in the total; the % row reads the total
    other = {**row, "zone": "b", "_ids": {"npcs": {235, 9}, "personas": {235}, "qwen": {9}}}
    first = {**row, "_ids": {"npcs": {235, 7}, "personas": {235, 7}, "qwen": {7}}}
    t = report.total([first, other])
    assert (t["npcs"], t["personas"], t["qwen"], t["quests"]) == (3, 2, 2, 4)
    pct = report.percentages(t)
    assert pct["personas"] == "67 %" and pct["scripts_start"] == "100 %" and pct["audio_start"] == "50 %"
    assert pct["no_french"] == "50 %"  # 1 quest without French text in each zone, 2 of 4
    with pytest.raises(SystemExit, match="duskwood"):
        report.pick(report.fetched_zones(), ["eastern-kingdoms/duskwood"])


def test_completion_report_todo(data_dir):
    from pipeline.zones import report
    folder = data_dir / "zones" / "eastern-kingdoms" / "westfall"
    folder.mkdir(parents=True)
    giver, ender = [{"type": "npc", "id": 235, "name": "Gryan"}], [{"type": "npc", "id": 7, "name": "Inconnu"}]
    quests = {"9": {"id": 9, "name": "Les Défias", "side": "alliance", "description": "Texte.", "objectives": "x",
                    "completion": "Merci.", "starters": giver, "enders": ender},
              "10": {"id": 10, "name": "Sans texte", "side": "alliance", "description": None, "objectives": None,
                     "completion": None, "starters": giver, "enders": giver},
              "11": {"id": 11, "name": "Un objet", "side": "alliance", "description": "Texte.", "objectives": "x",
                     "starters": [{"type": "object", "id": 5}]}}
    storage.write_json(folder / "quests.json", {"quests": quests})
    storage.write_json(folder / "scripts.json", {"scripts": {"9": {}}})
    voices = {"235": {"persona": {"summary": "x"}}}
    todo = dict(report.zone_todo("eastern-kingdoms/westfall", voices, {235: {"name": "Gryan Stoutmantle"}}))
    assert todo["PNJ absents des registres (relancer l'import de la base, tools/base/run.sh)"] == ["7 Inconnu"]
    assert todo["PNJ sans voix modèle (boucle voix)"] == ["235 Gryan Stoutmantle"]
    assert todo["début : quêtes sans texte français (capture en jeu)"] == ["10 Sans texte"]
    assert todo["début : quêtes sans PNJ (narrateur, D9)"] == ["11 Un objet"]
    assert todo["début : audio à produire"] == ["9 Les Défias"]
    assert todo["fin : scripts à écrire"] == ["9 Les Défias (sans fiche)"]
    text = report.render_todo("eastern-kingdoms/westfall", list(todo.items()))
    assert "- PNJ sans voix modèle (boucle voix) (1) : 235 Gryan Stoutmantle" in text
