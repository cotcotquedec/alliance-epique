"""Audio encoding over ffmpeg and oggenc (system tools) for the quest readings (tools/readings/judge.py).

Quality rule (2026-10-05): keep a lossless FLAC master, and encode the game file once with the reference Vorbis
encoder (oggenc, Homebrew `vorbis-tools`), never with ffmpeg's experimental one.
"""

from __future__ import annotations

import subprocess
from pathlib import Path


def to_flac(src: Path, dst: Path) -> None:
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(src), "-c:a", "flac", str(dst)], check=True)


def to_ogg(src_wav: Path, dst: Path, quality: int = 6) -> None:
    """Ogg Vorbis for the game: stereo 44.1 kHz like the S1 test sounds, encoded once by oggenc."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    stereo = dst.with_suffix(".stereo.wav")
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(src_wav), "-ac", "2", "-ar", "44100", "-map_metadata",
                    "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", str(stereo)], check=True)
    try:
        subprocess.run(["oggenc", "--quiet", "-q", str(quality), "-o", str(dst), str(stereo)], check=True)
    finally:
        stereo.unlink(missing_ok=True)
