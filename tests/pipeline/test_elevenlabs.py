import base64
import io
import json

import pytest

from pipeline import elevenlabs


class Response(io.BytesIO):
    def __init__(self, body: bytes, kind: str):
        super().__init__(body)
        self.headers = {"Content-Type": kind}

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False


def opener(answers):
    calls = []

    def open_(req, timeout):
        calls.append((req.get_method(), req.full_url, json.loads(req.data) if req.data else None,
                      req.headers.get("Xi-api-key")))
        body, kind = answers.pop(0)
        return Response(body, kind)
    return open_, calls


def test_api_key_from_the_secrets_file(tmp_path, monkeypatch):
    monkeypatch.delenv(elevenlabs.KEY, raising=False)
    path = tmp_path / "secrets.env"
    with pytest.raises(elevenlabs.ElevenLabsError):
        elevenlabs.api_key(path)
    path.write_text("# comment\nELEVENLABS_API_KEY='sk_abc'\n")
    assert elevenlabs.api_key(path) == "sk_abc"
    monkeypatch.setenv(elevenlabs.KEY, "sk_env")
    assert elevenlabs.api_key(path) == "sk_env"


def test_calls():
    audio = base64.b64encode(b"MP3").decode()
    open_, calls = opener([
        (json.dumps({"character_limit": 100, "character_count": 30}).encode(), "application/json"),
        (json.dumps({"previews": [{"generated_voice_id": "g1", "audio_base_64": audio}]}).encode(), "application/json"),
        (json.dumps({"voice_id": "v1"}).encode(), "application/json"),
        (b"MP3DATA", "audio/mpeg"),
        (b'{"detail": "x"}', "application/json"),
    ])
    el = elevenlabs.ElevenLabs("sk", opener=open_)
    assert el.credits_left() == 70
    previews = el.design("desc", "texte", "eleven_multilingual_ttv_v2", seed=3)
    assert elevenlabs.preview_audio(previews[0]) == b"MP3"
    assert el.create("Elise", "desc", "g1") == "v1"
    assert el.speak("v1", "Bonjour.", "eleven_v4", seed=5) == b"MP3DATA"
    with pytest.raises(elevenlabs.ElevenLabsError):
        el.speak("v1", "Bonjour.", "eleven_v4")
    assert calls[1][2] == {"voice_description": "desc", "text": "texte", "model_id": "eleven_multilingual_ttv_v2",
                           "seed": 3}
    method, url, body, key = calls[3]
    assert method == "POST" and url.endswith("/v1/text-to-speech/v1?output_format=mp3_44100_192")
    assert body == {"text": "Bonjour.", "model_id": "eleven_v4", "language_code": "fr", "seed": 5} and key == "sk"
