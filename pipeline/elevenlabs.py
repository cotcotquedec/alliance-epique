"""ElevenLabs over plain HTTP (urllib, no dependency), for Elise's voice and lines (2026-10-10). Restored in part from
pipeline/voices/engines.py, removed on 2026-10-07 (b34b0db): the NPCs stay on Qwen3-TTS (D11).

API (docs: elevenlabs.io/docs/api-reference; models listed on this account on 2026-10-10: eleven_v4 speaks French):
- GET  /v1/user/subscription: plan, characters used and limit, voice slots (free);
- POST /v1/text-to-voice/design: description + preview text -> 3 previews (generated_voice_id, base64 audio);
- POST /v1/text-to-voice: keep one preview as a voice (takes a voice slot);
- GET  /v1/voices/{voice_id}: a voice of the account;
- POST /v1/text-to-speech/{voice_id}: speech with that voice (costs the text's characters).

The API key comes from the environment or config/secrets.env (gitignored, never committed): ELEVENLABS_API_KEY.
"""

from __future__ import annotations

import base64
import json
import os
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SECRETS_FILE = ROOT / "config" / "secrets.env"
API = "https://api.elevenlabs.io"
KEY = "ELEVENLABS_API_KEY"


class ElevenLabsError(RuntimeError):
    pass


def api_key(path: Path = SECRETS_FILE) -> str:
    value = os.environ.get(KEY, "")
    if not value and path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith(KEY + "="):
                value = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not value:
        raise ElevenLabsError(f"{KEY} is not set: put it in config/secrets.env")
    return value


class ElevenLabs:
    def __init__(self, key: str | None = None, opener=urllib.request.urlopen):
        self.headers = {"xi-api-key": key or api_key()}
        self.opener = opener

    def _request(self, path: str, body: dict | None = None, timeout: float = 180.0) -> tuple[bytes, str]:
        data = json.dumps(body).encode("utf-8") if body is not None else None
        req = urllib.request.Request(API + path, data=data, method="POST" if data else "GET",
                                     headers={**self.headers, "Content-Type": "application/json"})
        try:
            with self.opener(req, timeout=timeout) as resp:
                return resp.read(), resp.headers.get("Content-Type", "")
        except urllib.error.HTTPError as err:
            detail = err.read().decode("utf-8", errors="replace")[:500] if err.fp else ""
            raise ElevenLabsError(f"{err.code} on {path}: {detail}") from err

    def subscription(self) -> dict:
        return json.loads(self._request("/v1/user/subscription")[0])

    def credits_left(self) -> int:
        sub = self.subscription()
        return int(sub.get("character_limit", 0)) - int(sub.get("character_count", 0))

    def voice(self, voice_id: str) -> dict:
        """A voice of the account: {voice_id, name, category, description, labels, ...}."""
        return json.loads(self._request(f"/v1/voices/{voice_id}")[0])

    def design(self, description: str, text: str, model_id: str, seed: int | None = None) -> list[dict]:
        """3 previews: [{generated_voice_id, audio_base_64, ...}]."""
        body = {"voice_description": description, "text": text, "model_id": model_id}
        if seed is not None:
            body["seed"] = seed
        return json.loads(self._request("/v1/text-to-voice/design", body)[0])["previews"]

    def create(self, name: str, description: str, generated_voice_id: str) -> str:
        body = {"voice_name": name, "voice_description": description, "generated_voice_id": generated_voice_id}
        return json.loads(self._request("/v1/text-to-voice", body)[0])["voice_id"]

    def speak(self, voice_id: str, text: str, model_id: str, seed: int | None = None,
              settings: dict | None = None, output_format: str = "mp3_44100_192") -> bytes:
        body = {"text": text, "model_id": model_id, "language_code": "fr"}
        if seed is not None:
            body["seed"] = seed
        if settings:
            body["voice_settings"] = settings
        raw, kind = self._request(f"/v1/text-to-speech/{voice_id}?output_format={output_format}", body)
        if "json" in kind:
            raise ElevenLabsError(f"text-to-speech returned JSON instead of audio: {raw[:300]!r}")
        return raw


def preview_audio(preview: dict) -> bytes:
    return base64.b64decode(preview["audio_base_64"])
