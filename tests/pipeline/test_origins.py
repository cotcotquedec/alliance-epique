import pytest

from pipeline.foreverdb import origins


@pytest.fixture(autouse=True)
def upstreams(monkeypatch):
    texts = {
        "questie": {783: {"name": "Menace intérieure", "objectivesText": "Parler au maréchal McBride."}},
        "vmangos": {783: {"name": "Menace intérieure", "details": "J'espère, jeune $c."},
                    40: {"objectivesText": "Tuer des loups."}},
        "client_cache": {},
        "wowhead": {95350: {"details": "Un texte de Forever."}},
    }
    monkeypatch.setattr(origins, "upstreams", lambda: texts)


def test_database_origin_follows_the_database_order():
    fr = {"name": "Menace intérieure", "objectivesText": ["Parler au maréchal McBride."],
          "details": "J'espère, jeune $c."}
    assert origins.database_origin(783, "name", fr) == "foreverdb:questie"  # questie before vmangos
    assert origins.database_origin(783, "objectives", fr) == "foreverdb:questie"  # a list of lines is joined
    assert origins.database_origin(783, "description", fr) == "foreverdb:vmangos"
    assert origins.database_origin(40, "objectives", {"objectivesText": ["Tuer des loups."]}) == "foreverdb:vmangos"
    assert origins.database_origin(95350, "description", {"details": "Un texte de Forever."}) == "foreverdb:wowhead"


def test_azerothcore_is_read_from_the_entry_and_a_changed_text_is_unknown():
    assert origins.database_origin(1, "completion", {"completion": "x", "azerothcore": ["completion"]}) \
        == "foreverdb:azerothcore"
    assert origins.database_origin(783, "description", {"details": "Autre texte."}) == "foreverdb:unknown"


def test_record_origins_keeps_the_channel_of_other_texts():
    record = {"name": "Menace intérieure", "description": "Texte de Wowhead.", "objectives": "Texte capturé.",
              "progress": None}
    channels = {"name": "foreverdb", "description": "wowhead", "objectives": "capture"}
    assert origins.record_origins(783, record, channels, {"name": "Menace intérieure"}) == {
        "name": "foreverdb:questie", "description": "wowhead", "objectives": "capture"}
