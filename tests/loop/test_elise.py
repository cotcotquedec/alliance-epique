import json

import pytest

from pipeline import narrator
from tools.elise import act, frame, judge, oracle

TEXT = "Le parchemin est froid."
ZONE = "dungeons/blackrock-depths"


@pytest.fixture
def world(tmp_path, monkeypatch):
    for name, value in (("ROOT", tmp_path), ("ZONES", tmp_path / "data" / "zones"),
                        ("STATE", tmp_path / "data" / "elise" / "state.json"),
                        ("CANDIDATES", tmp_path / "elise" / "candidates"), ("REVIEW", tmp_path / "elise" / "review"),
                        ("GAME_AUDIO", tmp_path / "addon" / "ForeverSpeech" / "audio"),
                        ("MASTERS", tmp_path / "data" / "audio"), ("TRIES_LOG", tmp_path / "tries.jsonl")):
        monkeypatch.setattr(judge, name, value)
    voices = tmp_path / "voices.json"
    voices.write_text(json.dumps({"npcs": {"1000000": {"name": "Elise", "elevenlabs": {"voice_id": "V1"}}}}))
    monkeypatch.setattr(judge.voice_judge, "VOICES_FILE", voices)
    zone = tmp_path / "data" / "zones" / ZONE
    zone.mkdir(parents=True)
    scripts = {"scripts": {"4081": {"name": "Recherché", "npc_id": narrator.NARRATOR_ID, "text": TEXT},
                           "4082": {"name": "PNJ", "npc_id": 823, "text": "Bonjour."}}, "complete": {}}
    (zone / "scripts.json").write_text(json.dumps(scripts))
    from pipeline.voices import audio

    def fake_encode(src, dst, *_):
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(b"OGG")
    monkeypatch.setattr(audio, "to_ogg", fake_encode)
    monkeypatch.setattr(audio, "to_flac", fake_encode)
    monkeypatch.setattr(act, "decode", lambda mp3, wav: wav.write_bytes(b"RIFF") or 2.0)
    from pipeline import build_index
    monkeypatch.setattr(build_index, "main", lambda argv: None)
    return tmp_path


class Client:
    def __init__(self, credits=10000):
        self.credits, self.spoken = credits, []

    def subscription(self):
        return {"character_limit": self.credits, "character_count": 0, "next_character_count_reset_unix": 1793887604}

    def speak(self, voice_id, text, model_id, seed=None, settings=None, output_format=None):
        assert voice_id == "V1" and model_id == frame.TTS_MODEL
        self.spoken.append(text)
        return b"ID3"


def lines(world):
    return oracle.zone_lines(ZONE, "V1", judge._read(judge.STATE, {"lines": {}}), zones=world / "data" / "zones",
                             root=world)


def test_only_the_narrator_lines_and_the_take_goes_in_place_without_whisper(world):
    assert [u["id"] for u in lines(world)["todo"]] == ["4081_detail"]
    assert act.main([ZONE], client=Client()) == 0
    z = lines(world)
    assert z["ok"] == 1 and z["todo"] == []
    item = json.loads((world / "data" / "zones" / ZONE / "audio.json").read_text())["audio"]["4081"]
    assert item["npc"] == narrator.NARRATOR_ID and item["m"]["voice_id"] == "V1"
    assert item["m"]["engine"] == "elevenlabs" and item["m"]["text_hash"] == frame.text_hash(TEXT)
    assert item["m"]["validated"]["by"] == "human" and item["m"]["validated"]["rule"] == act.TRUSTED
    assert set(item["m"]["scores"]) == {"secs", "cps"}  # no Whisper score
    assert (world / "addon" / "ForeverSpeech" / "audio" / "1000000" / "4081_detail.ogg").is_file()
    state = json.loads(judge.STATE.read_text())["lines"]["4081_detail"]
    assert state["tries"] == 1 and state["status"] == "ok" and "best" not in state


def test_a_changed_text_or_voice_is_to_do_again(world):
    act.main([ZONE], client=Client())
    assert lines(world)["ok"] == 1
    assert oracle.zone_lines(ZONE, "V2", judge._read(judge.STATE, {}), zones=world / "data" / "zones",
                             root=world)["ok"] == 0
    scripts = world / "data" / "zones" / ZONE / "scripts.json"
    data = json.loads(scripts.read_text())
    data["scripts"]["4081"]["text"] = TEXT + " Il tremble."
    scripts.write_text(json.dumps(data))
    assert [u["id"] for u in lines(world)["todo"]] == ["4081_detail"]


def test_a_line_refused_before_is_read_again_and_kept(world):
    judge.STATE.parent.mkdir(parents=True)
    judge.STATE.write_text(json.dumps({"lines": {"4081_detail": {
        "zone": ZONE, "status": "not_found", "campaign_tries": judge.MAX_TRIES, "tries": 5, "seeds": [1],
        "best": {"seed": 1, "scores": {}, "take": "elise/review/4081_detail.wav"}}}}))
    from tools.elise import reopen
    reopen.main()
    assert act.main([ZONE], client=Client()) == 0
    state = json.loads(judge.STATE.read_text())["lines"]["4081_detail"]
    assert state["status"] == "ok" and "best" not in state and state["tries"] == 6


def test_credits_spent_stop_the_round_with_the_limit_code(world, capsys):
    client = Client(credits=30)
    assert act.main([ZONE], client=client) == act.EXIT_LIMIT
    assert client.spoken == [] and "credit limit reached|1793887604" in capsys.readouterr().out


def test_the_limit_code_waits_and_the_halt_code_stops():
    from tools.elise import arbiter
    assert 75 in arbiter.RULES.limit and 77 in arbiter.RULES.halt


INTROS = "eastern-kingdoms/@intros"
INTRO = "Sous les grands chênes, la lumière tombe en flaques dorées."


def test_a_zone_introduction_is_one_of_her_lines_in_the_intro_folder(world):
    from pipeline import zone_intros
    folder = world / "data" / "zones" / INTROS
    folder.mkdir(parents=True)
    (folder / "scripts.json").write_text(json.dumps({"zones": {"12": {
        "npc_id": narrator.NARRATOR_ID, "name": "Forêt d'Elwynn", "area": 12, "map": 1429, "text": INTRO}}}))
    assert zone_intros.keys(world / "data" / "zones") == [INTROS]
    todo = oracle.zone_lines(INTROS, "V1", {}, zones=world / "data" / "zones", root=world)["todo"]
    assert [(u["id"], u["kind"], u["quest"]) for u in todo] == [("12_zone", "zone", 12)]
    client = Client()
    assert act.main([INTROS], client=client) == 0
    assert client.spoken == [INTRO]
    item = json.loads((folder / "audio.json").read_text())["zone"]["12"]
    assert item["npc"] == narrator.NARRATOR_ID and item["m"]["text_hash"] == frame.text_hash(INTRO)
    assert item["m"]["file"].endswith("\\audio\\1000000\\12_zone.ogg")
    assert (world / "addon" / "ForeverSpeech" / "audio" / "1000000" / "12_zone.ogg").is_file()
    assert oracle.zone_lines(INTROS, "V1", judge._read(judge.STATE, {}), zones=world / "data" / "zones",
                             root=world)["ok"] == 1


def test_kind_keeps_only_her_zone_introductions_or_only_her_quest_lines(world, monkeypatch):
    folder = world / "data" / "zones" / INTROS
    folder.mkdir(parents=True)
    (folder / "scripts.json").write_text(json.dumps({"zones": {"12": {
        "npc_id": narrator.NARRATOR_ID, "name": "Forêt d'Elwynn", "area": 12, "map": 1429, "text": INTRO}}}))

    def todo(key):
        return [u["id"] for u in oracle.zone_lines(key, "V1", {}, zones=world / "data" / "zones", root=world)["todo"]]
    monkeypatch.setenv("FS_ELISE_KIND", "zone")
    assert todo(INTROS) == ["12_zone"] and todo(ZONE) == []
    monkeypatch.setenv("FS_ELISE_KIND", "quest")
    assert todo(INTROS) == [] and todo(ZONE) == ["4081_detail"]
    monkeypatch.delenv("FS_ELISE_KIND")
    assert todo(INTROS) == ["12_zone"] and todo(ZONE) == ["4081_detail"]


def test_kind_is_for_the_elise_pass_only(capsys):
    from tools.loop.__main__ import main
    with pytest.raises(SystemExit):
        main(["check", "readings", "--all", "--kind", "zone"])
    assert "--kind: the elise pass only" in capsys.readouterr().err


def test_her_level_up_lines_are_lines_of_hers(world, monkeypatch):
    from pipeline import level_lines
    folder = world / "data" / "zones" / level_lines.KEY
    folder.mkdir(parents=True)
    (folder / "scripts.json").write_text(json.dumps({"levels": {"12": {
        "npc_id": narrator.NARRATOR_ID, "name": "Niveau 12", "level": 12, "text": "Je m'appelle Elise."}}}))
    assert level_lines.keys(world / "data" / "zones") == [level_lines.KEY]
    monkeypatch.setenv("FS_ELISE_KIND", "level")
    todo = oracle.zone_lines(level_lines.KEY, "V1", {}, zones=world / "data" / "zones", root=world)["todo"]
    assert [(u["id"], u["kind"], u["quest"]) for u in todo] == [("12_level", "level", 12)]
    assert act.main([level_lines.KEY], client=Client()) == 0
    item = json.loads((folder / "audio.json").read_text())["level"]["12"]["m"]
    assert item["file"].endswith("\\audio\\1000000\\12_level.ogg")


def test_her_companion_lines_are_lines_of_hers(world, monkeypatch):
    from pipeline import build_index, companion_lines
    folder = world / "data" / "zones" / companion_lines.KEY
    folder.mkdir(parents=True)
    (folder / "scripts.json").write_text(json.dumps({"npc_id": narrator.NARRATOR_ID, "tiers": [
        {"key": "encounter", "name_m": "Rencontre", "name_f": "Rencontre", "from_seconds": 300},
        {"key": "good_friend", "name_m": "Bon ami", "name_f": "Bonne amie", "from_seconds": 36000}],
        "lines": {"good_friend-03": {"tier": "good_friend", "variant": 3, "text": "Une route partagée."},
                  "encounter-01": {"tier": "encounter", "variant": 1, "text": "Un visage nouveau."}}}))
    assert companion_lines.keys(world / "data" / "zones") == [companion_lines.KEY]
    monkeypatch.setenv("FS_ELISE_KIND", "companion")
    todo = oracle.zone_lines(companion_lines.KEY, "V1", {}, zones=world / "data" / "zones", root=world)["todo"]
    assert [(u["id"], u["kind"], u["quest"], u["name"]) for u in todo] == [
        ("101_companion", "companion", 101, "Rencontre 1"), ("203_companion", "companion", 203, "Bon ami 3")]
    monkeypatch.setenv("FS_ELISE_KIND", "level")
    assert oracle.zone_lines(companion_lines.KEY, "V1", {}, zones=world / "data" / "zones", root=world)["todo"] == []
    monkeypatch.setenv("FS_ELISE_KIND", "companion")
    assert act.main([companion_lines.KEY], client=Client()) == 0
    audio = json.loads((folder / "audio.json").read_text())["companion"]
    assert sorted(audio) == ["101", "203"]
    assert audio["203"]["m"]["file"].endswith("\\audio\\1000000\\203_companion.ogg")
    assert oracle.zone_lines(companion_lines.KEY, "V1", judge._read(judge.STATE, {}), zones=world / "data" / "zones",
                             root=world) == {"todo": [], "ok": 2, "not_found": 0, "no_voice": 0}
    loaded = build_index.load_companions(world / "data" / "zones")
    assert loaded["lines"][203]["intro"]["file"].endswith("203_companion.ogg")
    assert loaded["lines"][101]["intro"]["src"] == "elise"


def test_companion_kind_is_accepted(capsys):
    from tools.loop.__main__ import main
    with pytest.raises(SystemExit):
        main(["check", "readings", "--all", "--kind", "companion"])
    assert "--kind: the elise pass only" in capsys.readouterr().err
