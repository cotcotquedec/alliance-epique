"""Audio encoding over ffmpeg and oggenc (system tools) for the quest readings (tools/readings/judge.py).

Quality rule (2026-10-05): keep a lossless FLAC master, and encode the game file once with the reference Vorbis
encoder (oggenc, Homebrew `vorbis-tools`), never with ffmpeg's experimental one.

Game files (2026-11-16): mono, 24 kHz, quality 1 (about 36 kbit/s), chosen by ear on 80 readings against the former
stereo 44.1 kHz q6: the voices pack drops from 3.4 GB to about 0.93 GB. Qwen speaks at 24 kHz, so nothing of its voices
is lost; Elise (ElevenLabs, 44.1 kHz) loses the top of her spectrum. tools/reencode_audio.ts re-encodes the game files
from their masters.
"""

from __future__ import annotations

import subprocess
from pathlib import Path


def to_flac(src: Path, dst: Path) -> None:
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(src), "-c:a", "flac", str(dst)], check=True)


CHANNELS, RATE, QUALITY = 1, 24000, 1  # the game files' format; tools/reencode_audio.ts uses the same


def to_ogg(src_wav: Path, dst: Path, quality: int = QUALITY) -> None:
    """Ogg Vorbis for the game: mono 24 kHz, encoded once by oggenc."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    wav = dst.with_suffix(".mono.wav")
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(src_wav), "-ac", str(CHANNELS), "-ar", str(RATE),
                    "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", str(wav)], check=True)
    try:
        subprocess.run(["oggenc", "--quiet", "-q", str(quality), "-o", str(dst), str(wav)], check=True)
    finally:
        wav.unlink(missing_ok=True)
