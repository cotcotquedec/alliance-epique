#!/usr/bin/env bash
# Creates the voice environment .venv-voices (gitignored) for this machine (tools/qwen_voices/backend.py):
# - Mac with Apple Silicon: requirements-mlx.txt (Qwen3-TTS through MLX-Audio);
# - Linux with an NVIDIA GPU (WSL2 on Windows): requirements-cuda.txt (Qwen3-TTS through PyTorch, CUDA 12.6);
# - anything else: requirements-cuda.txt as well, the models then run on the CPU (slow).
# An environment left by another machine (a folder copied from the Mac) is replaced. Model weights download on
# first use (Hugging Face cache). Check afterwards: .venv-voices/bin/python -m tools.qwen_voices.doctor
#   tools/voices/setup.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]]; then
  REQ=tools/voices/requirements-mlx.txt
else
  REQ=tools/voices/requirements-cuda.txt
  command -v nvidia-smi >/dev/null && nvidia-smi -L || echo "no NVIDIA GPU seen: the models will run on the CPU"
fi
if [[ -e .venv-voices ]] && ! .venv-voices/bin/python -c "" 2>/dev/null; then
  echo "replacing .venv-voices (made on another machine)"
  rm -rf .venv-voices
fi
[[ -e .venv-voices ]] || python3.12 -m venv .venv-voices
.venv-voices/bin/pip install --upgrade pip
.venv-voices/bin/pip install -r "$REQ"
echo "voice environment ready ($REQ)"
