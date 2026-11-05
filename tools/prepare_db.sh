#!/usr/bin/env bash
# Builds the Forever Database, our main data source (github.com/Stein-N/WoW-Quest-Database, GPL-3.0), in
# .data/ (not versioned): clone, a local Lua 5.1 (QuestieDB's export needs one; LuaJIT hits a constant
# limit), QuestieDB Forever export, VMaNGOS SQLite snapshot and AzerothCore locales (GitHub downloads),
# then the merged JSON data. Idempotent: what is there is kept. We follow the repository's releases (tags), not its
# main branch (2026-10-08): a first clone takes the latest release; --update moves to a newer release, if any
# (tools/db_check.sh), then the registries follow with tools/zone.sh sync.
#   tools/prepare_db.sh [--update]
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=https://github.com/Stein-N/WoW-Quest-Database.git
DB=.data/forever-db
LUA_VERSION=5.1.5
LUA_SHA256=2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333
LUA=$PWD/.data/lua-$LUA_VERSION/src/lua
UPDATE=0
if [[ "${1:-}" == "--update" ]]; then UPDATE=1; fi
mkdir -p .data

if [[ ! -d $DB/.git ]]; then
  TAG=$(.venv/bin/python -m pipeline.foreverdb.release latest)
  git clone --depth 1 --branch "$TAG" --recurse-submodules --shallow-submodules "$REPO" "$DB"
elif [[ $UPDATE -eq 1 ]]; then
  set +e
  .venv/bin/python -m pipeline.foreverdb.release check
  STATUS=$?
  set -e
  if [[ $STATUS -eq 0 ]]; then
    echo "no newer release: nothing to update"
    exit 0
  elif [[ $STATUS -ne 10 ]]; then
    echo "cannot tell whether a newer release exists: nothing changed" >&2
    exit 1
  fi
  TAG=$(.venv/bin/python -m pipeline.foreverdb.release latest)
  git -C "$DB" fetch --depth 1 origin tag "$TAG"
  git -C "$DB" checkout -q --detach "$TAG"
  git -C "$DB" submodule update --init --depth 1
  rm -rf "$DB/vendor/vmangos" "$DB/vendor/azerothcore"  # fetched again below
fi

# A Lua built on another machine (the folder copied from the Mac to Linux) does not run: built again.
if ! "$LUA" -v >/dev/null 2>&1; then
  echo "building Lua $LUA_VERSION (lua.org) …"
  rm -rf ".data/lua-$LUA_VERSION"
  curl -sSfL -o ".data/lua-$LUA_VERSION.tar.gz" "https://www.lua.org/ftp/lua-$LUA_VERSION.tar.gz"
  echo "$LUA_SHA256  .data/lua-$LUA_VERSION.tar.gz" | sha256sum -c - 2>/dev/null \
    || echo "$LUA_SHA256  .data/lua-$LUA_VERSION.tar.gz" | shasum -a 256 -c -
  tar -xzf ".data/lua-$LUA_VERSION.tar.gz" -C .data
  # macosx on the Mac; posix elsewhere (no readline needed to run scripts)
  make -C ".data/lua-$LUA_VERSION" "$([[ "$(uname -s)" == Darwin ]] && echo macosx || echo posix)" >/dev/null
fi

make -C "$DB" questie LUA="$LUA"
make -C "$DB" vmangos azerothcore
make -C "$DB" site-data
echo "Forever Database ready: $(cat "$DB/web/static/data/meta.json" | head -c 200)"
echo "Next: tools/zone.sh sync --dry-run, then tools/zone.sh sync   (registries in step with it; no loop running)"
