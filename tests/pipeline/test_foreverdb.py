import json

import pytest

from pipeline import storage
from pipeline.foreverdb import importer
from pipeline.zones import catalog as zones


class FakeDB:
    stamp = "db test"

    def __init__(self):
        self.quests = {
            "783": {"id": 783, "level": 1, "reqLevel": 1, "side": "A", "zone": {"zone": 9},
                    "startedBy": [{"t": "npc", "id": 823, "name": "Deputy Willem"}],
                    "finishedBy": [{"t": "npc", "id": 197, "name": "Marshal McBride"}], "rewards": {"xp": 40}},
            "40": {"id": 40, "level": 9, "side": "B", "zone": {"zone": 12},
                   "startedBy": [{"t": "npc", "id": 240, "name": "Marshal Dughan"}], "finishedBy": []},
            "95350": {"id": 95350, "level": 13, "side": "B", "zone": {"zone": 1637},
                      "startedBy": [{"t": "npc", "id": 259119, "name": "Alaana Stormwalker"}]},
            "7": {"id": 7, "side": "A", "zone": {"zone": 9}, "startedBy": [{"t": "item", "id": 5}]},
        }
        self.quests_fr = {
            "783": {"name": "Menace intérieure", "objectivesText": ["Parler au maréchal McBride."],
                    "details": "J'espère, jeune $c.$B$BEt ce n'est pas tout.",
                    "completion": "Ah, parfait. $B $B Sur tous les fronts, $N. $gMonsieur:Madame; !"},
            "40": {"details": "Texte classique de la base.", "completion": "Merci."},
            "7": {"details": "Kill the kobolds and come back to me."},
        }
        self.npcs = {"823": {"name": "Deputy Willem", "react": "A", "minLevel": 1, "maxLevel": 18,
                             "faction": {"name": "Stormwind"}, "zone": {"name": "Elwynn Forest"}},
                     "197": {"name": "Marshal McBride", "react": "A"}}
        self.npcs_fr = {"823": {"name": "Adjoint Willem"}, "197": {"name": "Maréchal McBride"}}
        self.zones = {"9": {"parent": 12}, "12": {}, "1637": {"parent": 1519}}
        self.displays = {823: 2072}

    def parents(self, zone_id):
        return importer.ForeverDB.parents(self, zone_id)


CATALOG = {"zones": {"eastern-kingdoms/elwynn-forest": {"id": 12, "name": "Forêt d'Elwynn"},
                     "uncategorized": {"id": -2, "name": "Non classés"}}}


def test_convert_text():
    assert importer.convert_text("Ah. $B $B Sur tous les fronts, $N. $gMonsieur:Madame; jeune $c, $R.") == \
        "Ah.\n\nSur tous les fronts, <nom>. <Monsieur/Madame> jeune <classe>, <race>."
    assert importer.convert_text(["Trouver :", "", "La clé."]) == "Trouver :\n\nLa clé."
    assert importer.convert_text("Pris ?") == "Pris ?"
    assert importer.convert_text("  ") is None and importer.convert_text(None) is None


def test_zones_from_the_listings_then_the_zone_chain():
    db = FakeDB()
    split = importer.zone_of_quests(db, CATALOG, {"eastern-kingdoms/elwynn-forest": [40]})
    assert split["eastern-kingdoms/elwynn-forest"] == [7, 40, 783]  # 40 listed, 783 and 7 via Northshire (9)
    assert split["uncategorized"] == [95350]  # Orgrimmar is not in the catalogue


def test_quest_record_keeps_wowhead_texts_and_fills_the_gaps():
    db = FakeDB()
    wowhead = {"id": 40, "description": "Texte Forever de Wowhead.", "completion": None,
               "capture": {"text": "x"}, "wowhead": {"http": 200}, "forever": {"status": "changed"}}
    rec = importer.quest_record(db, 40, 12, wowhead)
    assert rec["description"] == "Texte Forever de Wowhead."  # never replaced by the Classic text
    assert rec["completion"] == "Merci."  # the gap is filled
    assert rec["source"]["texts"] == {"description": "wowhead", "completion": "foreverdb"}
    assert rec["capture"] == {"text": "x"} and rec["forever"] == {"status": "changed"}
    new = importer.quest_record(db, 783, 12, None)
    assert new["name"] == "Menace intérieure" and new["objectives"] == "Parler au maréchal McBride."
    assert new["completion"].endswith("Sur tous les fronts, <nom>. <Monsieur/Madame> !")
    assert new["starters"] == [{"type": "npc", "id": 823, "name": "Adjoint Willem"}]
    assert new["enders"][0]["name"] == "Maréchal McBride" and new["side"] == "alliance" and new["xp"] == 40
    assert new["status"] == "complete"
    # a reimport keeps the database text it wrote (and would take a newer one)
    again = importer.quest_record(db, 783, 12, new)
    assert again["source"]["texts"]["description"] == "foreverdb"
    english = importer.quest_record(db, 7, 12, None)
    assert english["description"] is None and "description" in english["not_french"]  # D5


def test_import_zone_merges_and_never_drops(tmp_path, monkeypatch):
    monkeypatch.setattr(storage, "ZONES_DIR", tmp_path / "zones")
    db = FakeDB()
    folder = zones.zone_dir("eastern-kingdoms/elwynn-forest")
    storage.write_json(folder / "quests.json", {"quests": {"99128": {"id": 99128, "name": "Menace visqueuse",
                                                                     "status": "incomplete", "missing": ["giver"]}}})
    storage.write_json(folder / "npcs.json", {"npcs": {"197": {"id": 197, "voice": {"kind": "archetype",
                                                                                   "race": "Human", "sex": "male"},
                                                               "sex": {"value": "male", "source": "game_voice"}}}})
    catalog = json.loads(json.dumps(CATALOG))
    summary = importer.import_zone(db, catalog, "eastern-kingdoms/elwynn-forest", [40, 783])
    quests = storage.read_json(folder / "quests.json")
    npcs = storage.read_json(folder / "npcs.json")["npcs"]
    assert set(quests["quests"]) == {"40", "783", "99128"}  # the Wowhead-only quest stays
    assert quests["source"] == {"foreverdb": "db test"} and summary["quests"]["quests"] == 3
    assert set(npcs) == {"197", "240", "823"}  # givers and enders
    assert npcs["197"]["voice"]["kind"] == "archetype"  # the known game voice is kept
    assert npcs["197"]["sex"] == {"value": "male", "source": "game_voice"}  # and its sex (from the Wowhead NPC pages)
    assert npcs["823"]["display_id"] == 2072 and npcs["823"]["faction"] == "Stormwind"
    assert npcs["240"]["name"] == "Marshal Dughan" and npcs["240"]["voice"]["kind"] == "unknown"


def test_missing_database(tmp_path):
    with pytest.raises(importer.MissingDatabase, match="prepare_db"):
        importer.ForeverDB(tmp_path)


def test_base_oracle():
    from tools.base import oracle
    level = {"zones": 1, "quests": 2, "descriptions": 2, "completions": 1}
    assert oracle.ask(lambda: {"stamp": "s", "todo": [], "level": level}) == \
        {"done": True, "next": None, "todo": [], "level": level}
    assert oracle.ask(lambda: {"stamp": "s", "todo": ["a/b"], "level": level})["next"] == "all"
    assert oracle.ask(lambda: {"stamp": None, "todo": [], "level": level})["done"] is False  # not built yet


# --- sync (pipeline/foreverdb/sync.py) ----------------------------------------------------------

ELWYNN, UNCAT = "eastern-kingdoms/elwynn-forest", "uncategorized"
MINIMAL = {"status": "incomplete", "missing": ["description"]}


def _corpus(tmp_path, monkeypatch):
    """Quest 783 voiced in uncategorized (the beta's filing), 99 retired from the database, 98 captured in game,
    97 from Wowhead only."""
    monkeypatch.setattr(storage, "ZONES_DIR", tmp_path / "zones")
    monkeypatch.setattr(storage, "ZONES_FILE", tmp_path / "zones.json")  # the import saves the catalogue
    db = FakeDB()
    old = importer.quest_record(db, 783, -2, None)
    gone = {**importer.quest_record(db, 40, -2, None), "id": 99}
    folder = zones.zone_dir(UNCAT)
    storage.write_json(folder / "quests.json", {"quests": {"783": old, "99": gone,
                                                           "98": {"id": 98, "capture": {"text": "x"},
                                                                  "source": {"foreverdb": "db old"}, **MINIMAL},
                                                           "97": {"id": 97, "source": {"foreverdb": None},
                                                                  **MINIMAL}}})
    storage.write_json(folder / "npcs.json", {"npcs": {"823": {"id": 823, "voice": {"kind": "archetype"}}}})
    storage.write_json(folder / "scripts.json", {"schema": 2, "scripts": {"783": {"npc_id": 823}, "99": {}},
                                                 "complete": {"783": {"npc_id": 197}},
                                                 "failed": {"complete": {"783": {"error": "x"}}}})
    storage.write_json(folder / "audio.json", {"schema": 1, "audio": {"783": {"m": {"file": "a"}}},
                                               "complete": {"783": {"m": {"file": "b"}}}})
    storage.write_json(folder / "readings.json", {"schema": 1, "readings": {
        "783_detail": {"quest": 783, "tries": 2}, "99_detail": {"quest": 99, "tries": 1}},
        "history": [{"id": "783_detail", "quest": 783, "tries": 3}]})
    return db


def test_sync_moves_a_quest_with_everything_it_has(tmp_path, monkeypatch):
    from pipeline.foreverdb import sync
    db = _corpus(tmp_path, monkeypatch)
    p = sync.plan(db, {ELWYNN: [783], UNCAT: []})
    assert p.moved == [(783, UNCAT, ELWYNN)] and p.retired == [(99, UNCAT)] and p.new == []
    assert sorted(p.kept) == [(97, UNCAT, "other source"), (98, UNCAT, "capture")]  # never retired
    assert p.changed == [] and p.structural
    sync.apply(p, log=lambda *_: None)
    read = lambda key, name: storage.read_json(zones.zone_dir(key) / name)  # noqa: E731
    assert set(read(ELWYNN, "quests.json")["quests"]) == {"783"}
    assert set(read(UNCAT, "quests.json")["quests"]) == {"97", "98"}  # one place only
    assert read(ELWYNN, "npcs.json")["npcs"]["823"]["voice"]["kind"] == "archetype"  # the known voice follows
    assert read(ELWYNN, "scripts.json") == {"schema": 2, "scripts": {"783": {"npc_id": 823}},
                                            "complete": {"783": {"npc_id": 197}},
                                            "failed": {"complete": {"783": {"error": "x"}}}}
    assert read(ELWYNN, "audio.json")["complete"] == {"783": {"m": {"file": "b"}}}
    assert read(ELWYNN, "readings.json")["readings"] == {"783_detail": {"quest": 783, "tries": 2}}
    assert read(ELWYNN, "readings.json")["history"][0]["tries"] == 3  # the tries stay counted
    assert read(UNCAT, "audio.json")["audio"] == {} and read(UNCAT, "readings.json")["history"] == []
    archived = storage.read_json(sync.archive_file())["quests"]["99"]
    assert archived["category"] == UNCAT and archived["scripts.json"]["scripts"] == {"99": {}}
    assert archived["readings.json"]["readings"] == {"99_detail": {"quest": 99, "tries": 1}}
    assert sync.plan(db, {ELWYNN: [783]}).structural is False  # in step now


def test_sync_restores_a_quest_back_in_the_database(tmp_path, monkeypatch):
    from pipeline.foreverdb import sync
    db = _corpus(tmp_path, monkeypatch)
    sync.apply(sync.plan(db, {ELWYNN: [783]}), log=lambda *_: None)
    db.quests["99"] = {**db.quests["40"], "id": 99}
    p = sync.plan(db, {ELWYNN: [783, 99]})
    assert p.restored == [(99, ELWYNN)] and p.retired == []
    sync.apply(p, log=lambda *_: None)
    assert set(storage.read_json(zones.zone_dir(ELWYNN) / "quests.json")["quests"]) == {"99", "783"}
    assert storage.read_json(sync.archive_file())["quests"] == {}


def test_sync_lists_changed_texts_and_refuses_duplicates(tmp_path, monkeypatch):
    from pipeline.foreverdb import sync
    db = _corpus(tmp_path, monkeypatch)
    db.quests_fr["783"]["details"] = "Un texte réécrit pour la sortie."
    p = sync.plan(db, {UNCAT: [783]})
    assert p.moved == [] and p.changed == [(783, UNCAT, ["description"], True)]  # voiced: a human decides
    storage.write_json(zones.zone_dir(ELWYNN) / "quests.json", {"quests": {"783": {"id": 783}}})
    with pytest.raises(sync.DuplicateQuests, match="783"):
        sync.plan(db, {UNCAT: [783]})


def test_import_refuses_while_a_sync_is_pending(tmp_path, monkeypatch):
    from pipeline.zones import __main__ as cli
    db = _corpus(tmp_path, monkeypatch)
    catalog = json.loads(json.dumps(CATALOG))
    monkeypatch.setattr(cli, "_catalog", lambda: catalog)
    monkeypatch.setattr(importer, "cached_listings", lambda catalog: {ELWYNN: [783]})
    with pytest.raises(importer.SyncNeeded, match="moves 1 quest"):
        importer.import_zones(db=db, log=lambda *_: None)
    p = importer.sync_zones(db=db, log=lambda *_: None)
    assert p.moved == [(783, UNCAT, ELWYNN)]
    assert importer.import_zones(db=db, log=lambda *_: None)["quests"] >= 1  # in step: the import runs again


# --- releases (pipeline/foreverdb/release.py) ---------------------------------------------------

class Proc:
    def __init__(self, stdout, returncode=0):
        self.stdout, self.stderr, self.returncode = stdout, "", returncode


def fake_git(head, tags):
    def run(cmd, **_):
        if "ls-remote" in cmd:
            return Proc("".join(f"{sha}\trefs/tags/{t}\n" for t, sha in tags))
        return Proc(head + "\n")
    return run


CHANGELOG = json.dumps({"versions": [
    {"version": "0.1.6", "date": "2026-11-04", "website": ["a"], "dataNotes": ["Quests of the release."]},
    {"version": "0.1.5", "date": "2026-10-03", "dataNotes": ["Older note."]}]}).encode()


def test_release_tags_and_versions():
    from pipeline.foreverdb import release
    run = fake_git("x", [("v0.1.5", "aaa"), ("v0.1.10", "bbb"), ("v0.1.10^{}", "ccc"), ("nightly", "ddd")])
    tags = release.remote_tags(run)
    assert tags == {"v0.1.5": "aaa", "v0.1.10": "ccc"}  # an annotated tag's commit; not a release: left out
    assert release.latest(tags) == "v0.1.10"  # by version, not by text


def test_release_check(tmp_path, monkeypatch):
    from pipeline.foreverdb import release
    monkeypatch.setattr(release, "DB_DIR", tmp_path)
    assert release.check(fake_git("x", []))[0] == release.NEWER  # nothing built yet
    (tmp_path / ".git").mkdir()
    tags = [("v0.1.5", "a5"), ("v0.1.6", "a6")]
    get = lambda url: CHANGELOG  # noqa: E731
    assert release.check(fake_git("a6", tags), get)[0] == release.UP_TO_DATE
    code, lines = release.check(fake_git("a5", tags), get)
    assert code == release.NEWER and "    - Quests of the release." in lines
    assert "    - Older note." not in lines  # what we already have
    status = lambda s: lambda url: json.dumps({"status": s}).encode() if "compare" in url else CHANGELOG  # noqa
    assert release.check(fake_git("main1", tags), status("ahead"))[0] == release.UP_TO_DATE  # main, past v0.1.6
    assert release.check(fake_git("main1", tags), status("behind"))[0] == release.NEWER

    def offline(url):
        raise OSError("no network")
    assert release.check(fake_git("main1", tags), offline)[0] == release.UNKNOWN
