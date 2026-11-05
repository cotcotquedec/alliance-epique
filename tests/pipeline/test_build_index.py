import pytest

import json

from pipeline.build_index import load_audio, load_registries, main, render_index


def test_empty_index():
    out = render_index({})
    assert out.startswith("-- GENERATED")
    assert "version = 9," in out
    assert "quests = {\n  }," in out
    assert "npcs = {\n  }," in out


def test_entry_fields_in_contract_order_and_nil_omitted():
    out = render_index({
        783: {"detail": {
            "src": "test", "dur": 23.456, "npc": 823, "voice": "npc823@v1",
            "file": "Interface\\AddOns\\ForeverSpeech\\audio\\823\\783_detail.ogg", "fileF": None,
        }}
    })
    block = out[out.index("[783]"):]
    assert block.index("npc = 823") < block.index("voice =") < block.index("file =") < block.index("dur =")
    assert 'file = "Interface\\\\AddOns\\\\ForeverSpeech\\\\audio\\\\823\\\\783_detail.ogg",' in out
    assert "fileF" not in out
    assert "dur = 23.46," in out


def test_quests_sorted():
    entry = {"detail": {"file": "a.ogg", "src": "test"}}
    out = render_index({90: entry, 7: entry})
    assert out.index("[7]") < out.index("[90]")


def test_string_escaping():
    out = render_index({1: {"detail": {"file": 'a"b\nc', "src": "test"}}})
    assert 'file = "a\\"b\\nc",' in out


@pytest.mark.parametrize("entry", [
    {"src": "test"},                           # no file
    {"file": "a.ogg", "src": "nope"},          # bad source
    {"file": "a.ogg", "src": "test", "x": 1},  # unknown field
])
def test_invalid_entries_rejected(entry):
    with pytest.raises(ValueError):
        render_index({1: {"detail": entry}})


def test_givers_and_npcs():
    out = render_index({783: {"detail": {"file": "a.ogg", "src": "test"}}},
                       givers={783: 823, 33: 196},
                       npcs={823: {"display": 2072, "name": "Adjoint Willem"}, 196: {"display": None, "name": "Eagan"}})
    assert out.index("[33]") < out.index("[783]")
    block = out[out.index("[783] = {"):]
    assert block.index("giver = 823,") < block.index("detail = {")
    npcs = out[out.index("  npcs = {"):]
    assert '[823] = {\n      display = 2072,\n      name = "Adjoint Willem",\n    },' in npcs
    assert "display" not in npcs[npcs.index("[196]"):npcs.index("[823]")]


def test_load_registries_keeps_npc_givers_and_enders_only(tmp_path):
    zone = tmp_path / "eastern-kingdoms" / "elwynn-forest"
    zone.mkdir(parents=True)
    (zone / "quests.json").write_text(json.dumps({"quests": {
        "783": {"starters": [{"type": "npc", "id": 823, "name": "Adjoint Willem"}],
                "enders": [{"type": "npc", "id": 197, "name": "Maréchal McBride"}]},
        "91736": {"starters": [{"type": "object", "id": 562131, "name": "Alambic"}]},
    }}), encoding="utf-8")
    (zone / "npcs.json").write_text(json.dumps({"npcs": {
        "823": {"display_id": 2072, "name": "Adjoint Willem"},
        "197": {"display_id": 1, "name": "Maréchal McBride"},
        "5": {"display_id": 9, "name": "Passant"},
    }}), encoding="utf-8")
    givers, npcs, enders = load_registries(tmp_path)
    assert givers == {783: 823} and enders == {783: 197}
    assert npcs == {823: {"display": 2072, "name": "Adjoint Willem"}, 197: {"display": 1, "name": "Maréchal McBride"}}


def test_completion_audio_and_ender_in_the_index(tmp_path):
    zone = tmp_path / "eastern-kingdoms" / "elwynn-forest"
    zone.mkdir(parents=True)
    take = lambda npc, kind: {"file": f"Interface\\AddOns\\ForeverSpeech\\audio\\{npc}\\783_{kind}.ogg",  # noqa: E731
                              "dur": 12.5, "stamp": {"voice": "abcdefghij"}}
    (zone / "audio.json").write_text(json.dumps({"audio": {"783": {"npc": 823, "m": take(823, "detail")}},
                                                 "complete": {"783": {"npc": 197, "m": take(197, "complete")}}}))
    entries = load_audio(tmp_path)
    assert entries[783]["detail"]["npc"] == 823 and entries[783]["complete"]["npc"] == 197
    assert entries[783]["complete"]["voice"] == "npc197@abcdefgh"
    out = render_index(entries, {783: 823}, {}, {783: 197})
    assert "giver = 823," in out and "ender = 197," in out
    assert out.index("complete = {") < out.index("detail = {")  # kinds sorted
    assert "783_complete.ogg" in out


def test_the_narrator_is_named_in_the_index_without_a_giver(tmp_path):
    zones = tmp_path / "zones"
    zone = zones / "dungeons" / "blackrock-depths"
    zone.mkdir(parents=True)
    (zone / "quests.json").write_text(json.dumps({"quests": {"4081": {
        "starters": [{"type": "object", "id": 164867}], "enders": [{"type": "object", "id": 164867}]}}}))
    (zone / "npcs.json").write_text(json.dumps({"npcs": {}}))
    take = {"file": "Interface\\AddOns\\ForeverSpeech\\audio\\1000000\\4081_detail.ogg", "dur": 9.0}
    (zone / "audio.json").write_text(json.dumps({"audio": {"4081": {"npc": 1000000, "m": take}}}))
    (tmp_path / "voices.json").write_text(json.dumps({"npcs": {"1000000": {"name": "Elise"}}}))
    out = tmp_path / "index.lua"
    main(["--zones", str(zones), "--out", str(out)])
    lua = out.read_text(encoding="utf-8")
    assert "version = 9," in lua
    assert "giver =" not in lua and "ender =" not in lua
    assert "npc = 1000000," in lua and '[1000000] = {\n      name = "Elise",' in lua and "display" not in lua


def test_zone_introductions_in_the_index_by_map_id(tmp_path):
    zones = tmp_path / "zones"
    intros = zones / "eastern-kingdoms" / "@intros"
    intros.mkdir(parents=True)
    (intros / "scripts.json").write_text(json.dumps({"zones": {
        "12": {"npc_id": 1000000, "name": "Forêt d'Elwynn", "name_en": "Elwynn Forest", "area": 12, "map": 1429,
               "text": "Sous les chênes.\n\nCe sont vos premiers pas."},
        "40": {"npc_id": 1000000, "name": "Marche de l'Ouest", "name_en": "Westfall", "area": 40, "map": 1436,
               "text": "Les blés ont séché."}}}))
    take = {"file": "Interface\\AddOns\\ForeverSpeech\\audio\\1000000\\12_zone.ogg", "dur": 31.2,
            "stamp": {"voice": "G6INpmIspgFpsST79Psc"}}
    (intros / "audio.json").write_text(json.dumps({"zone": {"12": {"npc": 1000000, "m": take}}}))
    out = tmp_path / "index.lua"
    main(["--zones", str(zones), "--out", str(out)])
    lua = out.read_text(encoding="utf-8")
    assert "  zones = {\n    [1429] = {\n      area = 12,\n      name = \"Forêt d'Elwynn\"," in lua
    assert 'text = "Sous les chênes.\\n\\nCe sont vos premiers pas.",' in lua
    assert 'intro = {\n        npc = 1000000,\n        voice = "npc1000000@G6INpmIs",' in lua
    assert 'src = "elise",' in lua and "dur = 31.2," in lua
    assert "[1436] = {" in lua and lua.count("intro = {") == 1  # Westfall: the text only, no audio yet
    assert '[1000000] = {\n      name = "Elise",' in lua


def test_level_lines_in_the_index_by_level(tmp_path):
    zones = tmp_path / "zones"
    levels = zones / "@elise" / "levels"
    levels.mkdir(parents=True)
    (levels / "scripts.json").write_text(json.dumps({"arc": "…", "levels": {
        "12": {"npc_id": 1000000, "level": 12, "text": "Je m'appelle Elise."},
        "13": {"npc_id": 1000000, "level": 13, "text": "Méfiez-vous."}}}))
    take = {"file": "Interface\\AddOns\\ForeverSpeech\\audio\\1000000\\12_level.ogg", "dur": 4.2,
            "stamp": {"voice": "G6INpmIspgFpsST79Psc"}}
    (levels / "audio.json").write_text(json.dumps({"level": {"12": {"npc": 1000000, "m": take}}}))
    out = tmp_path / "index.lua"
    main(["--zones", str(zones), "--out", str(out)])
    lua = out.read_text(encoding="utf-8")
    assert "  levels = {\n    [12] = {\n      text = \"Je m'appelle Elise.\",\n      intro = {" in lua
    assert "[13] = {\n      text = \"Méfiez-vous.\",\n    }," in lua
    assert '[1000000] = {\n      name = "Elise",' in lua


def test_quest_levels_in_the_index(tmp_path):
    zones = tmp_path / "zones"
    zone = zones / "eastern-kingdoms" / "elwynn-forest"
    zone.mkdir(parents=True)
    (zone / "quests.json").write_text(json.dumps({"quests": {
        "6": {"level": 5, "starters": [{"type": "npc", "id": 823}], "enders": []},
        "7": {"level": 0, "starters": [], "enders": []},
        "8": {"level": 12, "starters": [], "enders": []}}}))
    (zone / "npcs.json").write_text(json.dumps({"npcs": {}}))
    out = tmp_path / "index.lua"
    main(["--zones", str(zones), "--out", str(out)])
    lua = out.read_text(encoding="utf-8")
    assert "    [6] = {\n      level = 5,\n      giver = 823," in lua
    assert "    [8] = {\n      level = 12,\n    }," in lua
    assert "[7]" not in lua  # no level known and nothing else: not in the index


def test_companion_tiers_and_lines_in_the_index(tmp_path):
    zones = tmp_path / "zones"
    folder = zones / "@elise" / "companions"
    folder.mkdir(parents=True)
    (folder / "scripts.json").write_text(json.dumps({"npc_id": 1000000, "tiers": [
        {"key": "encounter", "name_m": "Rencontre", "name_f": "Rencontre", "from_seconds": 300},
        {"key": "best_friend", "name_m": "Meilleur ami", "name_f": "Meilleure amie", "from_seconds": 36000,
         "rank": 1}],
        "lines": {
            "encounter-01": {"tier": "encounter", "variant": 1, "text": "Un visage nouveau."},
            "best_friend-02": {"tier": "best_friend", "variant": 2, "text": "Une place, dans un cœur."}}}))
    take = {"file": "Interface\\AddOns\\ForeverSpeech\\audio\\1000000\\202_companion.ogg", "dur": 5.0,
            "stamp": {"voice": "G6INpmIspgFpsST79Psc"}}
    (folder / "audio.json").write_text(json.dumps({"companion": {"202": {"npc": 1000000, "m": take}}}))
    out = tmp_path / "index.lua"
    main(["--zones", str(zones), "--out", str(out)])
    lua = out.read_text(encoding="utf-8")
    assert '      { key = "encounter", name = "Rencontre", nameF = "Rencontre", from = 300 },' in lua
    assert '{ key = "best_friend", name = "Meilleur ami", nameF = "Meilleure amie", from = 36000, rank = 1 },' in lua
    assert '      [101] = {\n        tier = "encounter",\n        text = "Un visage nouveau.",\n      },' in lua
    assert '      [202] = {\n        tier = "best_friend",' in lua and 'src = "elise",' in lua
    assert '[1000000] = {\n      name = "Elise",' in lua
