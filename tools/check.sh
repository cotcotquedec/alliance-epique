#!/usr/bin/env bash
# Run every offline check: luacheck, busted, pytest.
set -euo pipefail
cd "$(dirname "$0")/.."
.luarocks/bin/luacheck .
.luarocks/bin/busted
.venv/bin/pytest -q
