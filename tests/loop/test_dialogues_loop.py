import json

import pytest

from tools.dialogues import frame, judge, oracle, reopen

ZONE = "eastern-kingdoms/elwynn-forest"
GOOD = {"en": 0.0001, "fr": 0.999, "wer": 0.0, "cps": 14.0, "secs": 3.0, "sim": 0.9}
OTHER = {**GOOD, "sim": 0.3}


@pytest.fixture
def world(tmp_path, monkeypatch):
    for name, value in (("ROOT", tmp_path), ("ZONES", tmp_path / "data" / "zones"),
                        ("CANDIDATES", tmp_path / "cand"), ("REVIEW", tmp_path / "review"),
                        ("GAME_AUDIO", tmp_path / "addon" / "ForeverSpeech" / "audio"),
                        ("MASTERS", tmp_path / "data" / "audio"), ("TRIES_LOG", tmp_path / "tries.jsonl")):
        monkeypatch.setattr(judge, name, value)
    monkeypatch.setattr(judge.voice_judge, "ROOT", tmp_path)  # the model voice's ref.wav lives here
    zone = tmp_path / "data" / "zones" / ZONE
    zone.mkdir(parents=True)
    (zone / "scripts.json").write_text(json.dumps({"dialogues": {
        "197_7590": {"npc_id": 197, "npc_name": "Maréchal McBride", "page": "7590", "first": True,
                     "text": "Hé, <un ami/une amie> !", "gendered": True},
        "300_9": {"npc_id": 300, "npc_name": "Muet", "page": "9", "text": "Bonjour."}}}))
    from pipeline.voices import audio

    def fake_encode(src, dst, *_):
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(b"OGG")
    monkeypatch.setattr(audio, "to_ogg", fake_encode)
    monkeypatch.setattr(audio, "to_flac", fake_encode)
    voices = {"197": {"qwen": {"status": "ok", "seed": 1, "ref": "ref.wav",
                               "scores": {"en": 0.0, "fr": 1.0, "wer": 0.0, "cps": 15.0, "secs": 5.0}}}}
    (tmp_path / "ref.wav").write_bytes(b"RIFF")
    return tmp_path, voices


def zone_state(world):
    root, voices = world
    return oracle.zone_dialogues(ZONE, voices, zones=root / "data" / "zones", root=root)


class Ears:
    def __init__(self, scores):
        self.queue = list(scores)

    def scores(self, take, text, model_voice):
        return self.queue.pop(0), text


def take(world, unit, seed):
    root, _ = world
    folder = root / "cand" / judge.flat(ZONE)
    folder.mkdir(parents=True, exist_ok=True)
    wav = folder / f"{unit['id']}_s{seed}.wav"
    wav.write_bytes(b"RIFF")
    wav.with_suffix(".json").write_text(json.dumps({**unit, "zone": ZONE, "seed": seed, "voice_seed": 1,
                                                    "voice_ref": "ref.wav", "engine": "test"}))
    return wav


def test_units_one_per_player_sex_and_waiting_for_the_voice(world):
    z = zone_state(world)
    assert [u["id"] for u in z["todo"]] == ["197_7590", "197_7590_f"]
    assert z["todo"][1]["text"] == "Hé, une amie !" and z["waiting_voice"] == 1


def test_a_good_take_goes_in_place_in_the_dialogue_files(world):
    unit = zone_state(world)["todo"][0]
    assert judge.judge_take(ZONE, take(world, unit, 5), Ears([GOOD]), say=lambda _: None) == "ok"
    root, _ = world
    item = json.loads((root / "data" / "zones" / ZONE / "dialogue_audio.json").read_text())["dialogues"]["197_7590"]
    assert item["npc"] == 197 and item["m"]["file"].endswith("\\197\\dialogue_7590.ogg")
    assert (root / "addon" / "ForeverSpeech" / "audio" / "197" / "dialogue_7590.ogg").is_file()
    assert not (root / "data" / "zones" / ZONE / "audio.json").exists()  # never the readings' file
    z = zone_state(world)
    assert z["ok"] == 1 and [u["id"] for u in z["todo"]] == ["197_7590_f"]


def test_not_found_after_five_failures_then_reopened(world, monkeypatch):
    unit = zone_state(world)["todo"][0]
    for seed in range(judge.MAX_TRIES):
        judge.judge_take(ZONE, take(world, unit, seed), Ears([OTHER]), say=lambda _: None)
    assert zone_state(world)["not_found"] == 1
    root, _ = world
    assert (root / "review" / judge.flat(ZONE) / "197_7590" / "best.wav").is_file()
    reopen.main()
    assert [u["id"] for u in zone_state(world)["todo"]][0] == "197_7590"


def test_file_names():
    assert judge.file_name("197_7590") == "dialogue_7590" and judge.file_name("197_7590_f") == "dialogue_7590_f"
    assert frame.unit_id("197_7590", "f") == "197_7590_f"
