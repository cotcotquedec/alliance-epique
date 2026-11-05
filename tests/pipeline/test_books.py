"""Books read by Elise (D19): extraction from a tiny VMaNGOS fixture, Elise's scripts, the index v9 sections."""

import json
import sqlite3

import pytest

from pipeline import build_index, narrator
from pipeline.books import extract, scripts
from pipeline.match import fs_fp, fs_key, words


def vmangos(path):
    con = sqlite3.connect(path)
    con.executescript("""
        CREATE TABLE page_text (entry INT, text TEXT, next_page INT);
        CREATE TABLE locales_page_text (entry INT, Text_loc2 TEXT);
        CREATE TABLE gameobject_template (entry INT, patch INT, name TEXT, type INT, data0 INT, data7 INT);
        CREATE TABLE item_template (entry INT, patch INT, name TEXT, page_text INT, allowable_race INT, start_quest INT);
        CREATE TABLE locales_gameobject (entry INT, name_loc2 TEXT);
        CREATE TABLE locales_item (entry INT, name_loc2 TEXT);
        CREATE TABLE mail_loot_template (entry INT, item INT);
        CREATE TABLE gameobject (guid INT, id INT, map INT, position_x REAL, position_y REAL);
        CREATE TABLE creature (guid INT, id INT, map INT, position_x REAL, position_y REAL);
        CREATE TABLE game_event_creature (guid INT, event INT);
        CREATE TABLE map_template (entry INT, patch INT, map_name TEXT);
        CREATE TABLE quest_template (entry INT, patch INT, RequiredRaces INT, ZoneOrSort INT, SrcItemId INT,
          ReqItemId1 INT, ReqItemId2 INT, ReqItemId3 INT, ReqItemId4 INT, ReqSourceId1 INT, ReqSourceId2 INT,
          ReqSourceId3 INT, ReqSourceId4 INT, RewItemId1 INT, RewItemId2 INT, RewItemId3 INT, RewItemId4 INT,
          RewChoiceItemId1 INT, RewChoiceItemId2 INT, RewChoiceItemId3 INT, RewChoiceItemId4 INT,
          RewChoiceItemId5 INT, RewChoiceItemId6 INT);
        INSERT INTO page_text VALUES (1, 'Dear $N', 2), (2, 'page two', 3), (3, 'page three', 0),
          (10, 'Letter', 0), (50, 'Lectern text', 0), (20, 'Horde note', 0), (30, 'Mail', 0), (40, 'Old', 0);
        INSERT INTO locales_page_text VALUES
          (1, '<HTML><BODY><H1 align="center">Chronique</H1><BR/><P>Cher $N, vous serez $gravi:ravie;.$B$BAdieu.</P></BODY></HTML>'),
          (2, 'The second page is still in English, you know.'),
          (3, 'Cette preuve atteste que $N a tué la bête. <texte illisible>'),
          (10, 'Merci pour votre aide, $c. Le maire.'),
          (20, 'Pour la Horde !'),
          (30, 'Courrier du roi.'),
          (40, 'Vieux texte.');
        INSERT INTO gameobject_template VALUES (500, 0, 'Chronicle', 9, 1, 0), (500, 1, 'Chronicle', 9, 1, 0),
          (501, 0, 'A chest', 3, 1, 0), (502, 0, 'Lectern', 10, 0, 50);
        INSERT INTO item_template VALUES (600, 0, 'Horde Note', 20, 178, 0), (601, 0, 'Royal Mail', 30, -1, 0),
          (602, 0, 'Deprecated Old Book', 40, -1, 0), (603, 0, 'Letter', 10, -1, 0);
        INSERT INTO locales_gameobject VALUES (500, 'Chronique'), (502, 'Lutrin');
        INSERT INTO locales_item VALUES (600, 'Note de la Horde'), (601, 'Courrier royal'), (603, 'Lettre du maire');
        INSERT INTO mail_loot_template VALUES (1, 601);
        INSERT INTO gameobject VALUES (1, 500, 0, 100.0, 100.0), (2, 502, 0, 5000.0, 5000.0);
        INSERT INTO creature VALUES (1, 900, 0, 110.0, 100.0), (2, 901, 0, 120.0, 90.0), (3, 902, 0, 105.0, 99.0);
        INSERT INTO game_event_creature VALUES (3, 1);
        INSERT INTO map_template VALUES (0, 0, 'Eastern Kingdoms');
        INSERT INTO quest_template (entry, patch, RequiredRaces, ZoneOrSort, ReqItemId1) VALUES (7, 0, 0, 12, 603);
    """)
    con.commit()
    con.close()


def database(path):
    def shard(folder, data):
        (path / folder).mkdir(parents=True, exist_ok=True)
        (path / folder / "0.json").write_text(json.dumps(data))
    shard("quest", {"7": {"id": 7, "side": "A", "zone": {"zone": 12}}})
    shard("npc", {"900": {"spawns": {"12": [[1, 1]]}}, "901": {"spawns": {"12": [[2, 2]]}},
                  "902": {"spawns": {"493": [[1, 1]]}}})  # 902: an event spawn, left out
    shard("object", {})
    shard("item", {})
    for kind in ("object", "item"):
        shard(f"l10n/frFR/{kind}", {})
    (path / "zones.json").write_text(json.dumps({"zones": {"12": {"name": "Elwynn Forest"}}}))
    (path / "l10n" / "frFR" / "zones.json").write_text(json.dumps({"12": "Forêt d'Elwynn"}))


@pytest.fixture
def registry(tmp_path):
    vmangos(tmp_path / "db.sqlite")
    database(tmp_path / "forever")
    return extract.extract(extract.Database(tmp_path / "forever"), extract.Pages(tmp_path / "db.sqlite"),
                           log=lambda *_: None)


def test_extraction_follows_the_chains_in_french_only(registry):
    books = registry["books"]
    assert sorted(books) == ["item:600", "item:603", "object:500", "object:502"]
    chronicle = books["object:500"]
    assert chronicle["title"] == "Chronique" and chronicle["key"] == fs_key("Chronique")
    assert [(p["page"], p["n"]) for p in chronicle["pages"]] == [(1, 1), (3, 3)]  # page 2 is English
    assert chronicle["missing"] == [{"page": 2, "n": 2, "why": "english"}]
    assert chronicle["pages"][0]["fp"] == "htmlbodyh1aligncenterchroniqueh1brpchervousserez"  # 48 bytes of the key
    assert chronicle["where"]["zone"] == 12 and chronicle["where"]["zone_source"] == "nearest_npc"
    assert chronicle["side"] == "both"
    assert books["item:600"]["side"] == "horde" and books["item:600"]["side_source"] == "races"
    assert books["item:603"]["side"] == "alliance" and books["item:603"]["quests"] == {"objective_of": [7]}
    assert books["object:502"]["title"] == "Lutrin" and books["object:502"]["pages"] == []  # no French text
    assert {e["why"] for e in registry["excluded"]} == {"mail", "deprecated"}
    assert {"book": "object:502", "why": "no_french_page"} in registry["missing"]
    assert registry["summary"]["pages_french"] == 4


def test_scripts_read_the_book_as_written(registry):
    doc = scripts.build(registry)
    pages = doc["pages"]
    assert sorted(pages, key=int) == ["1", "3", "10"]  # the Horde note is out of the scope
    assert pages["1"]["text"] == "Chronique\n\nCher, vous serez <ravi/ravie>.\n\nAdieu."
    assert "<" not in pages["1"]["text"].replace("<ravi/ravie>", "") and pages["1"]["gendered"]
    assert pages["3"]["text"] == "Cette preuve atteste que <l'aventurier/l'aventurière> a tué la bête. texte illisible"
    assert pages["10"]["text"] == "Merci pour votre aide. Le maire." and not pages["10"]["gendered"]
    assert pages["1"]["npc_id"] == narrator.NARRATOR_ID and pages["1"]["books"] == ["object:500"]
    assert doc["cost"]["scope"]["lines"] == 5 and doc["cost"]["all"]["pages"] == 4  # two gendered pages
    assert doc["cost"]["scope"]["chars"] == sum(p["chars"] for p in pages.values())


def test_a_page_whose_text_did_not_change_keeps_its_record(registry):
    first = scripts.build(registry)
    again = scripts.build(registry, first)
    assert again["pages"]["1"]["generator"] == first["pages"]["1"]["generator"]


def test_strip_html_and_notes():
    assert scripts.strip_html("Plain <texte illisible>") == "Plain <texte illisible>"
    assert scripts.unwrap_notes("Vous <nom> et <ravi/ravie> <un sceau brisé>") == \
        "Vous <nom> et <ravi/ravie> un sceau brisé"


def test_index_v9_books_and_dialogues(tmp_path, registry):
    zones = tmp_path / "zones"
    folder = zones / "@books"
    folder.mkdir(parents=True)
    (folder / "books.json").write_text(json.dumps(registry))
    (folder / "scripts.json").write_text(json.dumps(scripts.build(registry)))
    entry = {"file": "Interface\\AddOns\\ForeverSpeech\\audio\\1000000\\book_1.ogg", "dur": 12.5,
             "voice_id": "G6INpmIspgFpsST79Psc", "stamp": {"voice": "G6INpmIspgFpsST79Psc"}}
    female = {**entry, "file": entry["file"].replace("book_1", "book_1_f")}
    (folder / "audio.json").write_text(json.dumps({"book": {"1": {"npc": 1000000, "m": entry, "f": female}}}))
    cat = zones / "eastern-kingdoms" / "elwynn-forest"
    cat.mkdir(parents=True)
    (cat / "dialogues.json").write_text(json.dumps({"npcs": {"197": {"pages": [
        {"id": "7590", "text": "Hé ! Vous, <nom>, avez l'air <costaud/costaude>."},
        {"id": "7591", "text": "Sans audio."}]}}}))
    voiced = {"file": "Interface\\AddOns\\ForeverSpeech\\audio\\197\\dialogue_7590.ogg", "dur": 3.0,
              "stamp": {"voice": "q12345678"}}
    (cat / "dialogue_audio.json").write_text(json.dumps({"dialogues": {"197_7590": {"npc": 197, "m": voiced}}}))
    books = build_index.load_books(zones)
    assert sorted(books) == ["chronique", "lettredumaire"]
    first = books["chronique"]["pages"][1][0]
    assert first["intro"]["fileF"].endswith("book_1_f.ogg") and first["intro"]["voice"] == "npc1000000@G6INpmIs"
    assert books["chronique"]["pages"][3] == [{"fp": registry["books"]["object:500"]["pages"][1]["fp"],
                                               "intro": None}]
    dialogues = build_index.load_dialogues(zones)
    assert dialogues == {197: [{"page": "7590", "words": words("Hé ! Vous, $N, avez l'air $gcostaud:costaude;."),
                                "intro": {"npc": 197, "voice": "npc197@q1234567", "file": voiced["file"],
                                          "fileF": None, "dur": 3.0, "src": "qwen"}}]}
    lua = build_index.render_index({}, books=books, dialogues=dialogues)
    assert "version = 9," in lua
    assert '["chronique"] = {\n      title = "Chronique",' in lua
    assert 'page = "7590", words = "hé vous avez l air"' in lua
    assert 'src = "qwen" }' in lua and "fileF" not in lua.split("dialogues = {")[1]
