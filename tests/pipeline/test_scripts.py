from pipeline import scripts, storage

QUESTS = {
    "6": {"id": 6, "name": "La prime", "description": "Soyez <prudent/prudente> <nom>. Garrick rôde.",
          "objectives": "Tuer Garrick.", "starters": [{"type": "npc", "id": 823}]},
    "45": {"id": 45, "name": "Rolf", "description": "Un corps.", "objectives": "x",
           "starters": [{"type": "object", "id": 55}]},
    "16": {"id": 16, "name": "Eau", "description": None, "objectives": None, "starters": [{"type": "npc", "id": 823}]},
}
VOICES = {"823": {"name": "Adjoint Willem", "persona": {"summary": "garde"}}}


def test_plan_and_generate(tmp_path):
    jobs, skipped = scripts.plan(QUESTS, VOICES, {})
    assert [j["quest"]["id"] for j in jobs] == [6]
    assert skipped["no_npc_giver"] == [45] and skipped["no_text"] == [16]
    assert scripts.plan(QUESTS, {}, {})[1]["no_persona"] == [6]
    report = scripts.generate(tmp_path, jobs, log=lambda *_: None)
    assert report["generated"] == 1
    data = storage.read_json(tmp_path / "scripts.json")
    s = data["scripts"]["6"]
    assert data["schema"] == scripts.SCHEMA
    assert s["gendered"] is True and s["npc_id"] == 823 and s["npc_name"] == "Adjoint Willem"
    assert s["text"].startswith("Soyez <prudent/prudente>.") and s["text"].endswith("Objectif : Tuer Garrick.")
    assert "segments" not in s and s["generator"]["version"] == scripts.VERSION
    # a rerun writes nothing; a changed text or persona does not rewrite an existing script
    existing = data["scripts"]
    assert scripts.plan(QUESTS, VOICES, existing)[0] == []
    assert len(scripts.plan(QUESTS, VOICES, existing, force=True)[0]) == 1
    changed = {**QUESTS, "6": {**QUESTS["6"], "objectives": "Tuer Garrick et ses complices."}}
    assert scripts.plan(changed, {"823": {**VOICES["823"], "persona": {"summary": "autre"}}}, existing)[0] == []


def test_completion_scripts_go_to_their_section(tmp_path):
    quests = {"783": {"id": 783, "name": "Menace intérieure", "description": "Va voir McBride.", "objectives": "x",
                      "completion": "Ah, parfait, un autre volontaire. Nous aurons à combattre, <nom>.",
                      "starters": [{"type": "npc", "id": 823}], "enders": [{"type": "npc", "id": 197}]},
              "9": {"id": 9, "description": "Rien.", "objectives": "x", "completion": None,
                    "starters": [{"type": "npc", "id": 823}], "enders": [{"type": "npc", "id": 197}]},
              "10": {"id": 10, "description": "Rien.", "objectives": "x", "completion": "Merci.",
                     "starters": [{"type": "npc", "id": 823}], "enders": [{"type": "object", "id": 5}]}}
    voices = {"823": VOICES["823"], "197": {"name": "Maréchal McBride", "persona": {"summary": "maréchal"}}}
    jobs, skipped = scripts.plan(quests, voices, {}, kind="complete")
    assert [(j["quest"]["id"], j["npc"]) for j in jobs] == [(783, 197)]
    assert skipped["no_text"] == [9] and skipped["no_npc_ender"] == [10]
    scripts.generate(tmp_path, jobs, log=lambda *_: None)
    data = storage.read_json(tmp_path / "scripts.json")
    assert data["complete"]["783"]["text"] == "Ah, parfait, un autre volontaire. Nous aurons à combattre."
    assert data["complete"]["783"]["kind"] == "complete" and data["complete"]["783"]["npc_id"] == 197
    assert data["scripts"] == {}  # the acceptance scripts are untouched
    assert scripts.plan(quests, voices, scripts.section(data, "complete"), kind="complete")[0] == []


def test_a_direction_failed_before_gets_its_script(tmp_path):
    storage.write_json(tmp_path / "scripts.json", {"schema": 1, "scripts": {"1": {"text": "old", "segments": []}},
                                                   "failed": {"detail": {"6": {"error": "x", "attempts": 3}}}})
    jobs, _ = scripts.plan(QUESTS, VOICES, {"1": {}})
    scripts.generate(tmp_path, jobs, log=lambda *_: None)
    data = storage.read_json(tmp_path / "scripts.json")
    assert "6" in data["scripts"] and "failed" not in data
    assert data["scripts"]["1"] == {"text": "old", "segments": []}  # an older script keeps its fields


def test_the_narrator_says_what_no_npc_says_once_she_has_her_record(tmp_path):
    from pipeline import narrator
    quests = {"45": {**QUESTS["45"], "enders": [{"type": "object", "id": 55}], "completion": "Le corps est froid."}}
    assert scripts.plan(quests, VOICES, {})[1]["no_npc_giver"] == [45]  # no narrator yet: skipped as before
    voices = {**VOICES, str(narrator.NARRATOR_ID): narrator.record()}
    for kind in scripts.KINDS:
        jobs, skipped = scripts.plan(quests, voices, {}, kind=kind)
        assert [(j["quest"]["id"], j["npc"]) for j in jobs] == [(45, narrator.NARRATOR_ID)]
        assert skipped[scripts.NO_SPEAKER[kind]] == []
        scripts.generate(tmp_path, jobs, log=lambda *_: None)
    data = storage.read_json(tmp_path / "scripts.json")
    for section in ("scripts", "complete"):
        s = data[section]["45"]
        assert s["npc_id"] == narrator.NARRATOR_ID and s["npc_name"] == "Elise" and s["narrator"] is True
    # an NPC giver always wins over the narrator
    assert scripts.plan(QUESTS, voices, {})[0][0]["npc"] == 823


def test_a_script_carries_the_origin_of_the_texts_it_reads(tmp_path):
    quest = {**QUESTS["6"], "completion": "Merci.", "enders": [{"type": "npc", "id": 823}],
             "source": {"texts": {"description": "wowhead", "objectives": "foreverdb", "completion": "foreverdb"},
                        "origins": {"description": "wowhead", "objectives": "foreverdb:questie"}}}
    assert scripts.text_origins(quest, "detail") == ("wowhead", {"description": "wowhead",
                                                                 "objectives": "foreverdb:questie"})
    # no origin yet: the channel of the text; no description: the objectives give the source
    assert scripts.text_origins(quest, "complete") == ("foreverdb", {"completion": "foreverdb"})
    assert scripts.text_origins({**quest, "description": None}, "detail")[0] == "foreverdb:questie"
    jobs, _ = scripts.plan({"6": quest}, VOICES, {})
    scripts.generate(tmp_path, jobs, log=lambda *_: None)
    s = storage.read_json(tmp_path / "scripts.json")["scripts"]["6"]
    assert s["source"] == "wowhead" and s["origins"]["objectives"] == "foreverdb:questie"


def test_origins_rewrites_the_source_of_existing_scripts_never_their_text(tmp_path):
    from pipeline.foreverdb import origins
    quest = {**QUESTS["6"], "source": {"origins": {"description": "foreverdb:vmangos", "objectives": "wowhead"}}}
    text = scripts.text_template(quest, "detail")["text"]
    storage.write_json(tmp_path / "scripts.json", {"scripts": {"6": {"text": text, "source": "wowhead_fr"},
                                                               "7": {"text": "Ancien texte.", "source": "wowhead_fr"}}})
    counts = origins.script_origins(tmp_path / "scripts.json", {"6": quest, "7": {**quest, "id": 7}})
    data = storage.read_json(tmp_path / "scripts.json")["scripts"]
    assert data["6"] == {"text": text, "source": "foreverdb:vmangos",
                         "origins": {"description": "foreverdb:vmangos", "objectives": "wowhead"}}
    assert data["7"] == {"text": "Ancien texte.", "source": "wowhead_fr"}  # its text is no longer the quest's
    assert counts["detail text changed or quest gone"] == 1
