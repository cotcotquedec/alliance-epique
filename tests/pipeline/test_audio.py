"""The game files' format (pipeline/voices/audio.py, 2026-11-16): mono, 24 kHz Vorbis, whatever the take's format."""

import shutil
import subprocess

import pytest

from pipeline.voices import audio

pytestmark = pytest.mark.skipif(not (shutil.which("ffmpeg") and shutil.which("oggenc")), reason="ffmpeg and oggenc")


def test_to_ogg_is_mono_24k(tmp_path):
    take = tmp_path / "take.wav"  # a stereo 44.1 kHz take, like an ElevenLabs one
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100",
                    "-ac", "2", "-t", "0.5", str(take)], check=True)
    ogg = tmp_path / "out" / "line.ogg"
    audio.to_ogg(take, ogg)
    probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_name,channels,sample_rate",
                            "-of", "csv=p=0", str(ogg)], capture_output=True, text=True, check=True).stdout.strip()
    assert probe == "vorbis,24000,1"
    assert not list(ogg.parent.glob("*.wav"))  # the intermediate file is removed
