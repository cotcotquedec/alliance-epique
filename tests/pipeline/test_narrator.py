import base64
import json

import pytest

from pipeline import narrator
from tools.elise import voice


def test_record_is_a_female_night_elf_described_by_the_voice_frame():
    from tools.qwen_voices.frame import describe
    record = narrator.record()
    assert record["name"] == "Elise" and record["narrator"] is True and record["persona"]["sex"] == "female"
    accents = json.loads((voice.ROOT / "data" / "accents.json").read_text(encoding="utf-8"))
    assert "Elise : une femme de race elfe de la nuit" in describe(record, accents)
    assert narrator.is_narrator(1000000) and narrator.is_narrator("1000000") and not narrator.is_narrator(None)


class Client:
    def __init__(self):
        self.created = []

    def design(self, description, text, model_id):
        assert model_id == voice.DESIGN_MODEL and text == narrator.PERSONA["sample_line"]
        return [{"generated_voice_id": f"g{i}", "audio_base_64": base64.b64encode(b"ID3").decode()} for i in (1, 2, 3)]

    def create(self, name, description, gid):
        self.created.append((name, gid))
        return "voice123"


@pytest.fixture
def paths(tmp_path, monkeypatch):
    for name, value in (("ROOT", tmp_path), ("VOICES_FILE", tmp_path / "voices.json"),
                        ("DESIGN", tmp_path / "elise" / "design"), ("VOICE", tmp_path / "elise" / "voice"),
                        ("PAGE", tmp_path / "pages" / "elise.html")):
        monkeypatch.setattr(voice, name, value)
    (tmp_path / "voices.json").write_text(json.dumps({"npcs": {"823": {"name": "Adjoint Willem"}}}))
    monkeypatch.setattr(voice.subprocess, "run", lambda cmd, **_: (voice.Path(cmd[-1]).write_bytes(b"fLaC")))
    return tmp_path


def test_design_then_keep_one_preview(paths, capsys):
    client = Client()
    assert voice.design(1, client) == 0
    assert sorted(p.name for p in (paths / "elise" / "design").glob("*.mp3")) == ["g1.mp3", "g2.mp3", "g3.mp3"]
    assert "keep g2" in (paths / "pages" / "elise.html").read_text()
    assert voice.keep("nope", client) == 1
    assert voice.keep("g2", client) == 0 and client.created == [("Elise", "g2")]
    voices = json.loads((paths / "voices.json").read_text())["npcs"]
    elise = voices["1000000"]
    assert elise["name"] == "Elise" and elise["elevenlabs"]["voice_id"] == "voice123"
    assert elise["elevenlabs"]["tts_model"] == voice.TTS_MODEL and "823" in voices
    assert (paths / elise["elevenlabs"]["ref"]).read_bytes() == b"fLaC"
    assert voice.keep("g3", client) == 1  # definitive


def test_use_an_existing_voice(paths):
    class Account(Client):
        def voice(self, voice_id):
            return {"voice_id": voice_id, "name": "FS base HumanFemaleOfficial", "description": "Adult woman"}

        def speak(self, voice_id, text, model_id):
            assert model_id == voice.TTS_MODEL
            return b"ID3"
    assert voice.use("G6IN", Account()) == 0
    elise = json.loads((paths / "voices.json").read_text())["npcs"]["1000000"]["elevenlabs"]
    assert elise["voice_id"] == "G6IN" and elise["account_name"] == "FS base HumanFemaleOfficial"
    assert (paths / "elise" / "voice" / "ref.mp3").read_bytes() == b"ID3"
    assert voice.use("other", Account()) == 1
