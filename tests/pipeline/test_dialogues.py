import json
import sqlite3

from pipeline import scripts, storage
from pipeline.foreverdb import dialogues


def gossip_db(path):
    con = sqlite3.connect(path)
    con.executescript("""
        CREATE TABLE creature_template (entry INT, gossip_menu_id INT, patch INT);
        CREATE TABLE gossip_menu (entry INT, text_id INT, condition_id INT);
        CREATE TABLE gossip_menu_option (menu_id INT, id INT, option_id INT, action_menu_id INT, condition_id INT);
        CREATE TABLE npc_text (ID INT, BroadcastTextID0 INT);
        CREATE TABLE locales_broadcast_text (entry INT, male_text_loc2 TEXT, female_text_loc2 TEXT);
        CREATE TABLE conditions (condition_entry INT, type INT, value1 INT, value2 INT, value3 INT, value4 INT);
        INSERT INTO creature_template VALUES (197, 10, 0), (300, 30, 0);
        INSERT INTO gossip_menu VALUES (10, 1, 0), (11, 2, 0), (12, 3, 5), (30, 9, 0);
        INSERT INTO gossip_menu_option VALUES (10, 0, 1, 11, 0), (10, 1, 3, 0, 0), (11, 0, 1, 12, 6);
        INSERT INTO npc_text VALUES (1, 101), (2, 102), (3, 103), (9, 109);
        INSERT INTO locales_broadcast_text VALUES
          (101, 'Hé ! Vous m''avez l''air d''être costaud.', NULL),
          (102, 'Le corps est froid, $N.', 'La dame est partie.'),
          (103, 'Vous retournez le corps.', NULL),
          (109, NULL, NULL);
        INSERT INTO conditions VALUES (5, 9, 4921, 0, 0, 0), (6, -1, 7, 0, 0, 0), (7, 8, 4920, 0, 0, 0);
    """)
    con.commit()
    con.close()


def test_pages_follow_the_chat_options_and_keep_the_quests(tmp_path):
    gossip_db(tmp_path / "db.sqlite")
    g = dialogues.Gossip(tmp_path / "db.sqlite")
    pages = g.pages(197)
    assert [p["id"] for p in pages] == ["101", "102", "103"]
    assert pages[0]["first"] and not pages[1]["first"]
    assert pages[1]["text"] == "Le corps est froid, <nom>." and pages[1]["text_female"] == "La dame est partie."
    assert pages[2]["quests"] == [4920, 4921]  # the option's condition (AND group) and the page's own
    assert g.pages(300) == []  # no French text
    assert g.pages(999) == []


def test_dialogue_scripts_need_a_persona_and_use_the_female_text(tmp_path):
    data = {"npcs": {"197": {"name": "McBride", "pages": [
        {"id": "101", "first": True, "quests": [], "text": "Bonjour <nom>, <un ami/une amie>."},
        {"id": "102", "first": False, "quests": [4921], "text": "Il est parti.", "text_female": "Elle est partie."}]}}}
    assert scripts.plan_dialogues(data, {}, {})[1]["no_persona"] == ["197_101", "197_102"]
    voices = {"197": {"name": "Maréchal McBride", "persona": {"sex": "female"}}}
    jobs, skipped = scripts.plan_dialogues(data, voices, {})
    scripts.generate_dialogues(tmp_path, jobs, log=lambda *_: None)
    section = storage.read_json(tmp_path / "scripts.json")["dialogues"]
    assert list(section) == ["197_101", "197_102"]
    assert section["197_101"]["text"] == "Bonjour, <un ami/une amie>." and section["197_101"]["gendered"] is True
    assert section["197_102"]["text"] == "Elle est partie." and section["197_102"]["quests"] == [4921]
    assert scripts.plan_dialogues(data, voices, section)[0] == []


def test_import_places_npcs_and_adds_the_dialogue_only_ones(tmp_path, monkeypatch):
    gossip_db(tmp_path / "db.sqlite")
    zones = tmp_path / "zones"
    (zones / "eastern-kingdoms" / "elwynn-forest").mkdir(parents=True)
    (zones / "eastern-kingdoms" / "elwynn-forest" / "quests.json").write_text(json.dumps(
        {"quests": {"1": {"side": "alliance"}}}))

    class DB:
        stamp = "test"
        npcs = {"197": {"react": "A", "zone": {"zone": 12}}, "300": {"react": "A", "zone": {"zone": 12}}}
        npcs_fr = {"197": {"name": "Maréchal McBride"}}

        def parents(self, zone_id):
            yield zone_id
    from pipeline.foreverdb import importer
    monkeypatch.setattr(importer, "npc_record", lambda db, nid, prev, name: {
        "id": nid, "name": name, "voice": {"kind": "unknown"}, "missing": ["voice"]})
    catalog = {"zones": {"eastern-kingdoms/elwynn-forest": {"id": 12}}}
    report = dialogues.import_dialogues(DB(), catalog, ["eastern-kingdoms/elwynn-forest"],
                                        dialogues.Gossip(tmp_path / "db.sqlite"), zones, log=lambda *_: None)
    assert report == {"categories": 1, "npcs": 1, "pages": 3, "new_npcs": 1}
    folder = zones / "eastern-kingdoms" / "elwynn-forest"
    assert list(storage.read_json(folder / "dialogues.json")["npcs"]) == ["197"]
    npc = storage.read_json(folder / "npcs.json")["npcs"]["197"]
    assert npc["dialogue_only"] is True and npc["name"] == "Maréchal McBride"
