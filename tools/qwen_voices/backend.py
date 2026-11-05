"""Where the voice models run (2026-10-07): chosen from the machine, the same code on the Mac and on a GPU box.

- "mlx": Apple Silicon (macOS arm64), Qwen3-TTS through MLX-Audio, the weights of the frames
  (mlx-community/...-bf16); Whisper and ECAPA on the CPU, beside the GPU work.
- "cuda": an NVIDIA GPU (Linux, e.g. WSL2 on Windows), Qwen3-TTS through the official PyTorch package (qwen-tts)
  in bf16, Whisper (CTranslate2, float16) and ECAPA on the GPU too.
- "cpu": anything else, PyTorch on the CPU (slow; for a check, not for a campaign).

FS_TTS_BACKEND=mlx|cuda|cpu forces one. The frames name the model (tools/qwen_voices/frame.py,
tools/readings/frame.py: the MLX build of Qwen3-TTS 12Hz 1.7B); `repo` maps it to the official build of the same
model for PyTorch. Sampling is the same on both: the frame's temperature, top-k 50, top-p 1.0, repetition penalty
1.05 (MLX-Audio's defaults, and those of qwen-tts). A seed does not give the same take on two backends.

Environments: tools/voices/setup.sh installs requirements-mlx.txt or requirements-cuda.txt.
"""

from __future__ import annotations

import os
import platform
import sys

BACKENDS = ("mlx", "cuda", "cpu")
MAX_TOKENS = 4096  # codec tokens per VoiceDesign call (MLX-Audio's default; qwen-tts's is lower)
SAMPLES = 8  # samples per PyTorch call at most (paragraphs of readings, voice texts): qwen-tts decodes a call's codes
# all at once, and past about 10 samples that decoding spills past the GPU's memory: 13 paragraphs, 277 s to decode;
# 6, 0.6 s (2026-10-08, RTX 4090, WSL2). A larger batch is generated in several calls, one after the other.


def name() -> str:
    forced = os.environ.get("FS_TTS_BACKEND", "").strip().lower()
    if forced:
        if forced not in BACKENDS:
            raise SystemExit(f"FS_TTS_BACKEND={forced!r}: expected one of {', '.join(BACKENDS)}")
        return forced
    if sys.platform == "darwin" and platform.machine() == "arm64":
        return "mlx"
    try:
        import torch
    except ImportError:
        return "cpu"
    return "cuda" if torch.cuda.is_available() else "cpu"


def repo(frame_repo: str, backend: str | None = None) -> str:
    """The model to load: the frame's MLX build, or the official build of the same model for PyTorch
    ("mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16" -> "Qwen/Qwen3-TTS-12Hz-1.7B-Base")."""
    if (backend or name()) == "mlx":
        return frame_repo
    model = frame_repo.split("/", 1)[-1]
    return "Qwen/" + (model[:-len("-bf16")] if model.endswith("-bf16") else model)


def engine(frame_repo: str, backend: str | None = None) -> str:
    """What a take records as its engine: the model loaded, and the backend when it is not MLX."""
    backend = backend or name()
    return repo(frame_repo, backend) + ("" if backend == "mlx" else f" ({backend})")


def torch_device() -> str:
    """Device of the PyTorch models beside Qwen3 (ECAPA): the GPU on a CUDA box, else the CPU."""
    return "cuda" if name() == "cuda" else "cpu"


def whisper(model: str):
    """faster-whisper: float16 on the GPU of a CUDA box, int8 on the CPU elsewhere (the Mac's GPU is Qwen3's).
    CTranslate2 needs the CUDA 12 cuBLAS and cuDNN: importing torch (+cu126) loads them first. If the GPU fails,
    the CPU is used, said loudly."""
    from faster_whisper import WhisperModel
    if name() == "cuda":
        try:
            import torch  # noqa: F401  (loads libcublas.so.12 and libcudnn for CTranslate2)
            return WhisperModel(model, device="cuda", compute_type="float16")
        except Exception as err:  # noqa: BLE001 - any CUDA load error: the CPU still judges
            print(f"WARNING: Whisper on the GPU failed ({err}); judging on the CPU", flush=True)
    return WhisperModel(model, device="cpu", compute_type="int8")


class Qwen:
    """Qwen3-TTS (VoiceDesign or Base, from the frame's repo) on the backend of this machine.

    design(...) and clone(...) return (mono float32 audio, sample rate); voice(ref_wav, ref_text) prepares a model
    voice once for clone."""

    def __init__(self, frame_repo: str):
        import numpy as np
        self.np = np
        self.backend = name()
        self.repo = repo(frame_repo, self.backend)
        self.engine = engine(frame_repo, self.backend)
        print(f"loading {self.repo} on {self.backend} (downloaded on first use)...", flush=True)
        if self.backend == "mlx":
            import mlx.core as mx
            from mlx_audio.tts.utils import load_model
            from mlx_audio.utils import load_audio
            self.mx, self.load_audio = mx, load_audio
            self.model = load_model(self.repo)
            self.sample_rate = self.model.sample_rate
        else:
            import torch
            from qwen_tts import Qwen3TTSModel
            self.torch = torch
            cuda = self.backend == "cuda"
            self.model = Qwen3TTSModel.from_pretrained(self.repo, device_map="cuda:0" if cuda else "cpu",
                                                       dtype=torch.bfloat16 if cuda else torch.float32)
            self.sample_rate = None  # given by each generation

    def seed(self, seed: int) -> None:
        if self.backend == "mlx":
            self.mx.random.seed(seed)
        else:
            self.torch.manual_seed(seed)  # every device, the GPU included

    def _mono(self, chunks):
        return self.np.concatenate([self.np.asarray(c, dtype=self.np.float32).reshape(-1) for c in chunks])

    def design(self, text: str, instruct: str, language: str, temperature: float, seed: int):
        self.seed(seed)
        if self.backend == "mlx":
            results = self.model.generate_voice_design(text=text, instruct=instruct, language=language,
                                                       temperature=temperature, max_tokens=MAX_TOKENS)
            return self._mono(r.audio for r in results), self.sample_rate
        wavs, sr = self.model.generate_voice_design(text=text, instruct=instruct, language=language,
                                                    temperature=temperature, max_new_tokens=MAX_TOKENS)
        return self._mono(wavs), sr

    def voice(self, ref_wav: str, ref_text: str):
        """A model voice ready for cloning (decoded and encoded once)."""
        if self.backend == "mlx":
            return self.load_audio(ref_wav, sample_rate=self.sample_rate), ref_text
        return self.model.create_voice_clone_prompt(ref_audio=ref_wav, ref_text=ref_text)

    def clone(self, paragraphs: list[str], voice, language: str, seed: int, gap: float, max_tokens: int):
        """The paragraphs read one after the other in the model voice, joined by `gap` seconds of silence."""
        self.seed(seed)
        parts, sr = [], self.sample_rate
        for paragraph in paragraphs:
            if self.backend == "mlx":
                ref_audio, ref_text = voice
                audio = self._mono(r.audio for r in self.model.generate(
                    text=paragraph, ref_audio=ref_audio, ref_text=ref_text, lang_code=language,
                    max_tokens=max_tokens, split_pattern="\n"))
            else:
                wavs, sr = self.model.generate_voice_clone(text=paragraph, language=language,
                                                           voice_clone_prompt=voice, max_new_tokens=max_tokens)
                audio = self._mono(wavs)
            parts += [audio, self.np.zeros(int(gap * sr), dtype=self.np.float32)]
        return self.np.concatenate(parts[:-1]), sr

    def design_many(self, items: list[tuple[str, str]], language: str, temperature: float, seed: int):
        """design(...) of several (text, instruct) in one batch on PyTorch, at most SAMPLES per call (one after the
        other on MLX). The batch
        shares one random state, seeded with `seed`. Returns [(audio, sample rate)] in the order of `items`."""
        if self.backend == "mlx" or len(items) == 1:
            return [self.design(text, instruct, language, temperature, seed) for text, instruct in items]
        self.seed(seed)
        out = []
        for c in range(0, len(items), SAMPLES):
            chunk = items[c:c + SAMPLES]
            wavs, sr = self.model.generate_voice_design(text=[t for t, _ in chunk], instruct=[i for _, i in chunk],
                                                        language=[language] * len(chunk), temperature=temperature,
                                                        max_new_tokens=MAX_TOKENS)
            out += [(self._mono([w]), sr) for w in wavs]
        return out

    def clone_many(self, jobs: list[tuple[list[str], object]], language: str, seed: int, gap: float,
                   max_tokens: int):
        """clone(...) of several (paragraphs, voice) in one batch on PyTorch, every paragraph of every job one
        sample of the batch, at most SAMPLES per call (one after the other on MLX). The batch shares one random state, seeded with `seed`.
        Returns [(audio, sample rate)] in the order of `jobs`."""
        if self.backend == "mlx" or len(jobs) == 1:
            return [self.clone(paragraphs, voice, language, seed, gap, max_tokens) for paragraphs, voice in jobs]
        self.seed(seed)
        texts = [p for paragraphs, _ in jobs for p in paragraphs]
        prompts = [item for paragraphs, voice in jobs for _ in paragraphs for item in voice]
        wavs = []
        for c in range(0, len(texts), SAMPLES):
            got, sr = self.model.generate_voice_clone(text=texts[c:c + SAMPLES],
                                                      language=[language] * len(texts[c:c + SAMPLES]),
                                                      voice_clone_prompt=prompts[c:c + SAMPLES],
                                                      max_new_tokens=max_tokens)
            wavs += list(got)
        silence = self.np.zeros(int(gap * sr), dtype=self.np.float32)
        out, i = [], 0
        for paragraphs, _ in jobs:
            parts = []
            for w in wavs[i:i + len(paragraphs)]:
                parts += [self._mono([w]), silence]
            out.append((self.np.concatenate(parts[:-1]), sr))
            i += len(paragraphs)
        return out


def batch_size() -> int:
    """Takes generated together (FS_TTS_BATCH forces it): 8 on a CUDA GPU, which one take alone leaves mostly idle
    (2026-10-08, RTX 4090: 0.9x real time alone, 6.3x for 8 together), else 1."""
    forced = os.environ.get("FS_TTS_BATCH", "").strip()
    if forced:
        return max(1, int(forced))
    return 8 if name() == "cuda" else 1
