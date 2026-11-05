import json
from pathlib import Path

import pytest

from pipeline import narrator, storage
from pipeline.llm import Answer, LLMError
from pipeline.zone_intros import generate, zones

DB = Path(__file__).parent / "fixtures" / "forever_zones"
CATALOG = {
    "eastern-kingdoms/elwynn-forest": {"id": 12, "group": "eastern-kingdoms", "name": "Forêt d'Elwynn"},
    "eastern-kingdoms/riverglades": {"id": 16591, "group": "eastern-kingdoms", "name": "Rives Claires"},
    "classes/warrior": {"id": -81, "group": "classes", "name": "Guerrier"},
}
TEXT = ("Sous les grands chênes, la lumière tombe en flaques dorées, et l'on entend au loin les cloches de l'abbaye. "
        "Tout respire la paix des champs et des vignes. Pourtant, cette douceur est fragile. Les kobolds creusent les "
        "mines, et les loups s'approchent des fermes.\n\nCe sont vos premiers pas, et ils comptent. À Goldshire, une "
        "auberge vous attend. Ne vous éloignez pas trop des gardes, et gardez votre arme à portée de main.")


@pytest.fixture(autouse=True)
def no_cache():
    zones._database.cache_clear()
    yield
    zones._database.cache_clear()


def test_clean_name_drops_the_english_name_and_junk():
    assert zones.clean_name("Marche de l'Ouest (Westfall)") == "Marche de l'Ouest"
    assert zones.clean_name("Supprimez-MOI") is None and zones.clean_name(None) is None


def test_the_zones_of_the_continents_with_map_id_and_french_name():
    found = zones.zones(DB, CATALOG)
    assert list(found) == [12, 41, 40, 16591]  # map order
    assert found[12] == {"area": 12, "map": 1429, "name": "Forêt d'Elwynn", "name_en": "Elwynn Forest",
                         "group": "eastern-kingdoms", "categories": ["eastern-kingdoms/elwynn-forest"]}
    assert found[41]["name"] == "Défilé de Deuillevent" and found[41]["group"] == "eastern-kingdoms"
    assert found[16591]["name"] == "Rives Claires"  # Forever's new zone: the category's name


def test_the_dossier_comes_from_the_registries():
    quests = {"7": {"id": 7, "name": "Kobolds", "objectives": "Tuer 10 kobolds.", "description": "Les kobolds !",
                    "zone_id": 87, "level": 5, "side": "alliance", "starters": [{"type": "npc", "id": 197}]},
              "8": {"id": 8, "name": "Horde", "zone_id": 12, "level": 9, "side": "horde"}}
    npcs = {"197": {"name": "Maréchal McBride", "title": None}}
    d = zones.dossier(12, DB, catalog=CATALOG, registries=(quests, npcs))
    assert d["places"] == ["Goldshire"] and d["people"] == ["Maréchal McBride"]
    assert d["territory"] == "terre de l'Alliance"
    assert zones.territory(1637) == "horde" and zones.territory(17) == "contested"
    assert d["quests"] == ["Kobolds : Tuer 10 kobolds."] and d["levels"] == [5, 5] and d["quest_count"] == 1


def test_problems_of_a_text():
    assert generate.problems(TEXT) == []
    assert generate.problems("Trop court.")[0].startswith("2 mots")
    assert "un nombre en chiffres" in generate.problems(TEXT.replace("les loups", "10 loups"))
    assert "une parenthèse ou un symbole" in generate.problems(TEXT + " (note)")


def test_generate_asks_again_with_what_is_wrong_then_saves_the_script(tmp_path, monkeypatch):
    monkeypatch.setattr(storage, "ZONES_DIR", tmp_path)
    monkeypatch.setattr(generate, "folder", lambda group: tmp_path / group / "@intros")
    real_zones, real_dossier = zones.zones, zones.dossier
    monkeypatch.setattr(generate.zone_list, "zones", lambda *a, **k: real_zones(DB, CATALOG))
    monkeypatch.setattr(generate.zone_list, "dossier",
                        lambda area, **k: real_dossier(area, DB, catalog=CATALOG, registries=({}, {})))
    monkeypatch.setattr(generate.zone_list, "_registries", lambda *a: ({}, {}))
    asked = []

    def call(system, prompt, schema, model, effort, bare=False):
        asked.append(prompt)
        text = "Trop court." if len(asked) == 1 else TEXT
        return Answer({"text": text, "names": ["Goldshire"]}, model, 0.01)

    report = generate.generate([12], call=call, parallel=1, log=lambda *_: None)
    assert report["written"] == 1 and "ne respectait pas les règles" in asked[1]
    script = json.loads((tmp_path / "eastern-kingdoms" / "@intros" / "scripts.json").read_text())["zones"]["12"]
    assert script["npc_id"] == narrator.NARRATOR_ID and script["map"] == 1429 and script["text"] == TEXT
    assert script["generator"]["attempts"] == 2 and script["generator"]["prompt_version"] == generate.PROMPT_VERSION


def test_generate_gives_up_after_the_attempts(monkeypatch):
    calls = []

    def call(*a, **k):
        calls.append(1)
        return Answer({"text": "Trop court.", "names": []}, "m", 0.0)
    with pytest.raises(LLMError):
        generate.write_one(zones.dossier(12, DB, catalog=CATALOG, registries=({}, {})), call=call)
    assert len(calls) == generate.ATTEMPTS
