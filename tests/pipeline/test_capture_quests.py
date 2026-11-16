import json

from pipeline import capture_quests


def _cap(**over):
    cap = {"questID": 7, "title": "Une quête", "text": "Merci, Lira. Repos, guerrier.\n\nUn guerrier sans égal.",
           "objectives": "Tuer 5 loups.", "giverID": 42, "giverName": "Bob", "giverType": "Creature",
           "playerName": "Lira", "playerClass": "Guerrier", "playerRace": "Humain", "playerSex": 2,
           "lastSeen": 10, "client": "1.60.1.70862"}
    cap.update(over)
    return cap


def _record(**over):
    record = {"id": 7, "name": None, "description": None, "objectives": None, "completion": None, "starters": [],
              "enders": [], "capture": None, "source": {"texts": {}, "origins": {}}}
    record.update(over)
    return record


def test_impersonal_name_and_addressed_class_only():
    text = capture_quests.impersonal(_cap()["text"], _cap())
    assert text == "Merci, <nom>. Repos, <classe>.\n\nUn guerrier sans égal."


def test_impersonal_name_is_a_whole_word():
    assert capture_quests.impersonal("Merci, Lirabelle.", _cap()) == "Merci, Lirabelle."


def test_fills_missing_texts_and_speaker():
    record = _record()
    result = capture_quests.apply(record, "detail", _cap())
    assert sorted(result["filled"]) == ["description", "name", "objectives"]
    assert record["source"]["texts"]["description"] == "capture"
    assert record["source"]["origins"]["description"] == "capture"
    assert record["starters"] == [{"type": "npc", "id": 42, "name": "Bob"}]
    assert record["missing"] == [] and record["status"] == "complete"
    assert "Lira" not in json.dumps(record["capture"])


def test_never_replaces_an_existing_text_but_lists_it():
    record = _record(name="Une quête", description="Un tout autre texte, rien à voir.", objectives="Tuer 5 loups.",
                     starters=[{"type": "npc", "id": 1, "name": "Alice"}],
                     source={"texts": {"description": "foreverdb"}, "origins": {}})
    result = capture_quests.apply(record, "detail", _cap())
    assert result["filled"] == []
    assert [f for f, _ in result["differs"]] == ["description"]
    assert record["description"] == "Un tout autre texte, rien à voir."
    assert record["starters"][0]["id"] == 1


def test_player_giver_name_is_never_kept():
    record = _record()
    capture_quests.apply(record, "detail", _cap(giverType="Player", giverName="Lira", giverID=None))
    assert "Lira" not in json.dumps(record, ensure_ascii=False)
    assert record["starters"] == []


def test_object_giver_is_not_taken():
    record = _record()
    capture_quests.apply(record, "detail", _cap(giverType="GameObject"))
    assert record["starters"] == []


def test_latest_capture_wins(tmp_path):
    zone = tmp_path / "g" / "c"
    zone.mkdir(parents=True)
    (zone / "quests.json").write_text(json.dumps({"quests": {"7": _record()}}), encoding="utf-8")
    caps = {"quests": {"7": [_cap(text="Ancien texte.", lastSeen=1), _cap(text="Nouveau texte.", lastSeen=5)]},
            "completions": {"7": _cap(text="Fini !", enderID=43, enderName="Carl", enderType="Creature")}}
    report = capture_quests.import_captures(caps, tmp_path)
    saved = json.loads((zone / "quests.json").read_text(encoding="utf-8"))["quests"]["7"]
    assert saved["description"] == "Nouveau texte."
    assert saved["completion"] == "Fini !"
    assert saved["enders"][0]["id"] == 43
    assert len(report["filled"]) == 2 and report["unknown"] == []


def test_client_cache_fills_missing_texts_only(tmp_path):
    from pipeline import client_cache
    zone = tmp_path / "g" / "c"
    zone.mkdir(parents=True)
    kept = _record(id=8, description="Texte de la base.", source={"texts": {"description": "foreverdb"}, "origins": {}})
    (zone / "quests.json").write_text(json.dumps({"quests": {"7": _record(), "8": kept}}), encoding="utf-8")
    texts = {7: {"name": "Une quête", "description": "Bonjour $N.$B$BMerci.", "objectives": "Tuer 5 loups."},
             8: {"name": None, "description": "Un tout autre texte, sans rapport.", "objectives": None},
             9: {"name": "Ailleurs", "description": "x", "objectives": None}}
    report = client_cache.import_cache(texts, 70938, tmp_path)
    saved = json.loads((zone / "quests.json").read_text(encoding="utf-8"))["quests"]
    assert saved["7"]["description"] == "Bonjour $N.$B$BMerci."  # converted by read(), not here
    assert saved["7"]["source"]["origins"]["description"] == "client_cache"
    assert saved["7"]["source"]["client_cache"] == 70938
    assert saved["8"]["description"] == "Texte de la base."
    assert [r["field"] for r in report["differs"]] == ["description"]
    assert report["unknown"] == [9]


def test_client_cache_unconfirmed_needs_the_registry_title(tmp_path):
    from pipeline import client_cache
    zone = tmp_path / "g" / "c"
    zone.mkdir(parents=True)
    quests = {"7": _record(), "8": _record(id=8, name="Autre titre")}
    (zone / "quests.json").write_text(json.dumps({"quests": quests}), encoding="utf-8")
    texts = {7: {"name": "Une quête", "description": "Texte.", "objectives": None, "confirmed": False},
             8: {"name": "Pas le même", "description": "Texte.", "objectives": None, "confirmed": False}}
    report = client_cache.import_cache(texts, 1, tmp_path)
    assert [r["quest"] for r in report["filled"]] == [7]
    assert [r["quest"] for r in report["skipped"]] == [8]
