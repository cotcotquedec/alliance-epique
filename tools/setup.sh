#!/usr/bin/env bash
# Sets up the whole project on this machine: a Mac (Homebrew) or Linux / WSL2 on Windows (apt). Checks the system
# tools (and says how to install the missing ones), then makes the local environments, replacing those copied from
# another machine: .venv (pipeline, tests), .luarocks (luacheck, busted), .venv-voices (tools/voices/setup.sh).
# Idempotent. Then: tools/check.sh, and .venv-voices/bin/python -m tools.qwen_voices.doctor
#   tools/setup.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# A folder copied through an external disk (exFAT, NTFS) loses the executable bits, and a Mac writes "._<name>"
# metadata files on such a disk: a "._<take>.wav" would pass for a take in the loops. Both fixed here.
find tools -name '*.sh' -exec chmod +x {} +
junk=$(find . -name '._*' -type f -not -path './.venv*' | wc -l | tr -d ' ')
if [[ $junk -gt 0 ]]; then
  echo "removing $junk macOS metadata file(s) (._*)"
  find . -name '._*' -type f -not -path './.venv*' -delete
fi

if [[ "$(uname -s)" == Darwin ]]; then
  INSTALL="brew install python@3.12 luajit luarocks ffmpeg vorbis-tools"
else
  INSTALL="sudo apt install -y python3.12 python3.12-venv build-essential curl git ffmpeg vorbis-tools sox luajit luarocks liblua5.1-0-dev"
fi
missing=()
for tool in python3.12 ffmpeg oggenc luarocks make curl git; do
  command -v "$tool" >/dev/null || missing+=("$tool")
done
if ((${#missing[@]})); then
  echo "missing: ${missing[*]}"
  echo "install them with:"
  echo "  $INSTALL"
  exit 1
fi
command -v claude >/dev/null || echo "note: the claude command is missing (text loop): https://claude.com/claude-code"

# Python of the pipeline and the tests (no external dependency but pytest)
if [[ -e .venv ]] && ! .venv/bin/python -c "" 2>/dev/null; then
  echo "replacing .venv (made on another machine)"
  rm -rf .venv
fi
[[ -e .venv ]] || python3.12 -m venv .venv
.venv/bin/pip install --quiet 'pytest>=8'

# Lua tools of the addon (Lua 5.1, the game's)
if [[ -e .luarocks ]] && ! .luarocks/bin/busted --version >/dev/null 2>&1; then
  echo "replacing .luarocks (made on another machine)"
  rm -rf .luarocks
fi
if [[ ! -x .luarocks/bin/busted ]]; then
  luarocks --tree .luarocks --lua-version 5.1 install busted
  luarocks --tree .luarocks --lua-version 5.1 install luacheck
fi

tools/voices/setup.sh
echo "ready. Check: tools/check.sh, then .venv-voices/bin/python -m tools.qwen_voices.doctor"
