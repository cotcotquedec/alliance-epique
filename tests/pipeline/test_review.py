import json

import pytest

from pipeline import review, storage

ZONE = "eastern-kingdoms/elwynn-forest"
BAD = {"en": 0.05, "fr": 0.9, "wer": 0.3, "cps": 14.0, "secs": 3.0, "sim": 0.5}


@pytest.fixture
def world(tmp_path, monkeypatch):
    from pipeline import build_index
    from pipeline.voices import audio
    from tools.dialogues import judge as dj
    from tools.elise import judge as ej
    from tools.readings import judge as rj
    zones = tmp_path / "data" / "zones"
    game = tmp_path / "addon" / "ForeverSpeech" / "audio"
    for mod in (rj, dj, ej):
        for name, value in (("ROOT", tmp_path), ("ZONES", zones), ("GAME_AUDIO", game),
                            ("MASTERS", tmp_path / "data" / "audio")):
            monkeypatch.setattr(mod, name, value)
    monkeypatch.setattr(ej, "STATE", tmp_path / "data" / "elise" / "state.json")
    monkeypatch.setattr(ej, "voice_id", lambda voices=None: "V1")
    monkeypatch.setattr(review, "ROOT", tmp_path)
    monkeypatch.setattr(review, "DECISIONS", tmp_path / "data" / "review" / "decisions.json")
    monkeypatch.setattr(review, "running", lambda loops, run=None: [])
    monkeypatch.setattr(build_index, "main", lambda argv: None)
    from tools.voices import judge as vj, redo
    monkeypatch.setattr(redo, "main", lambda argv: 0)  # never the real voices and readings
    monkeypatch.setattr(vj, "VOICES_FILE", tmp_path / "voices.json")
    monkeypatch.setattr(vj, "ROOT", tmp_path)

    def fake_encode(src, dst, *_):
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(b"OGG")
    monkeypatch.setattr(audio, "to_ogg", fake_encode)
    monkeypatch.setattr(audio, "to_flac", fake_encode)
    (zones / ZONE).mkdir(parents=True)
    best = tmp_path / "best.wav"
    best.write_bytes(b"RIFF")
    entry = {"npc": 197, "status": "not_found", "campaign_tries": 5, "tries": 5, "seeds": [1, 2],
             "best": {"seed": 2, "scores": BAD, "failed": ["en"], "take": "best.wav", "engine": "e", "text": "Salut.",
                      "voice_seed": 9}}
    storage.write_json(zones / ZONE / "readings.json", {"readings": {"18_detail": entry}})
    storage.write_json(zones / ZONE / "dialogue_readings.json",
                       {"readings": {"197_7590": {**entry, "key": "197_7590", "page": "7590", "sex": "m"}}})
    storage.write_json(ej.STATE, {"lines": {"4081_detail": {**entry, "zone": ZONE, "quest": 4081, "kind": "detail",
                                                            "sex": "m"}}})
    return tmp_path


def test_refused_audio_goes_in_game_marked_refused(world):
    for kind in ("reading", "dialogue", "elise"):
        assert review.publish_refused(kind, log=lambda *_: None) == 1
        assert review.publish_refused(kind, log=lambda *_: None) == 0  # the same take: once
    audio = json.loads((world / "data" / "zones" / ZONE / "audio.json").read_text())
    reading, line = audio["audio"]["18"]["m"], audio["audio"]["4081"]["m"]
    assert reading["refused"]["by"] == "judge" and reading["seed"] == 2
    assert line["engine"] == "elevenlabs" and line["voice_id"] == "V1" and audio["audio"]["4081"]["npc"] == 1000000
    page = json.loads((world / "data" / "zones" / ZONE / "dialogue_audio.json").read_text())["dialogues"]["197_7590"]
    assert page["m"]["refused"]["failed"] == ["en"] and page["page"] == "7590"
    assert (world / "addon" / "ForeverSpeech" / "audio" / "197" / "dialogue_7590.ogg").is_file()
    from tools.readings import oracle
    unit = {"id": "18_detail", "quest": 18, "kind": "detail", "sex": "m"}
    assert oracle.settled(unit, audio, {"readings": {}}, root=world) is None  # never counted as settled


def test_delete_removes_everything_and_the_reading_is_to_do_again(world):
    review.publish_refused("reading", log=lambda *_: None)
    decision = review.decide("reading", ZONE, "18_detail", "delete")
    assert decision["state"] == "applied"
    audio = json.loads((world / "data" / "zones" / ZONE / "audio.json").read_text())
    assert "18" not in audio["audio"]
    assert not (world / "addon" / "ForeverSpeech" / "audio" / "197" / "18_detail.ogg").exists()
    assert not (world / "best.wav").exists()
    entry = json.loads((world / "data" / "zones" / ZONE / "readings.json").read_text())["readings"]["18_detail"]
    assert "status" not in entry and entry["campaign_tries"] == 0 and entry["tries"] == 5 and "best" not in entry


def test_validate_then_refuse_by_hand_and_what_the_oracle_says(world):
    from tools.readings import oracle
    unit = {"id": "18_detail", "quest": 18, "kind": "detail", "sex": "m"}
    zone = world / "data" / "zones" / ZONE

    def settled():
        return oracle.settled(unit, json.loads((zone / "audio.json").read_text()),
                              json.loads((zone / "readings.json").read_text()), root=world)
    assert review.decide("reading", ZONE, "18_detail", "validate")["state"] == "applied"
    item = json.loads((zone / "audio.json").read_text())["audio"]["18"]["m"]
    assert item["validated"]["by"] == "human" and "refused" not in item and item["seed"] == 2
    assert settled() == "ok" and not (world / "best.wav").exists()
    assert review.decide("reading", ZONE, "18_detail", "refuse")["state"] == "applied"
    assert json.loads((zone / "audio.json").read_text())["audio"]["18"]["m"]["refused"]["by"] == "human"
    assert settled() == "not_found"  # refused: made again by the next run (reopen), still played meanwhile


def test_decisions_wait_for_the_writers_and_can_be_cancelled(world, monkeypatch):
    assert review.decide("voice", None, "197", "validate")["note"].startswith("waiting for the loops' update")
    monkeypatch.setattr(review, "running", lambda loops, run=None: ["readings"])
    review.decide("voice", None, "197", "delete")  # the latest decision on an asset replaces a queued one
    assert review.decide("reading", ZONE, "18_detail", "delete")["state"] == "queued"
    assert [x["action"] for x in review.pending()] == ["delete", "delete"]
    assert review.cancel("voice", None, "197") and len(review.pending()) == 1
    monkeypatch.setattr(review, "running", lambda loops, run=None: [])
    assert review.apply_pending(log=lambda *_: None) == 1 and review.pending() == []
    assert review.decide("voice", None, "197", "delete")["state"] == "applied"  # redo (stubbed here)


def test_statuses_in_english():
    assert [review.status(s) for s in ("ok", "pending", "not_found", None)] == \
        ["validated", "in_progress", "refused", "todo"]
