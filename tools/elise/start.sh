#!/usr/bin/env bash
# Start (or restart after a reboot) the Elise loop in a detached tmux session, with the dashboard beside it, then
# print how to attach. Safe to run again: a loop already running is left alone, only the attach info is printed.
#   tools/elise/start.sh [run.sh arguments]     (default: the scope of the last run, else --all)
#   tools/elise/start.sh --kill                 (stop the loop and close the session)
# Session: fs-elise. Window "elise": tools/elise/run.sh (left), tools/loop/dashboard.sh elise (right).
# Window "bench": the listening page (tools/voices/bench.py, http://127.0.0.1:8765), started if not already up.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
SESSION=fs-elise
LOOP_JSON=data/cache/loops/elise/progress/loop.json

command -v tmux >/dev/null || { echo "tmux missing: sudo apt install -y tmux" >&2; exit 1; }

loop_pids() { pgrep -f "tools[.]loop run elise" || true; }

start_bench() {  # in its own window of the session, unless a bench already listens
    pgrep -f "tools[.]voices[.]bench" >/dev/null && return
    tmux new-window -d -t "$SESSION" -n bench -c "$ROOT"
    tmux send-keys -t "$SESSION:bench" ".venv/bin/python -m tools.voices.bench" C-m
}

attach_info() {
    cat <<EOF

Attach:   tmux attach -t $SESSION
Detach:   Ctrl-b d   (the loop keeps running)
Panes:    Ctrl-b o (switch), Ctrl-b z (zoom one pane), Ctrl-b n (next window: bench)
Bench:    http://127.0.0.1:8765  (view "Refusées (tout le jeu)": listen, accept by ear)
Status:   tools/loop/status.sh elise ; tools/report.sh --all
Stop:     tools/elise/start.sh --kill   (or Ctrl-C in the left pane: nothing is lost, relaunching resumes)
EOF
}

if [[ "${1:-}" == "--kill" ]]; then
    pids=$(loop_pids)
    if [[ -n "$pids" ]]; then
        echo "stopping the Elise loop (pid $pids)"
        kill -INT $pids
        for _ in $(seq 30); do [[ -z "$(loop_pids)" ]] && break; sleep 1; done
    fi
    tmux kill-session -t "$SESSION" 2>/dev/null && echo "session $SESSION closed" || true
    exit 0
fi

# A loop already running: leave it alone.
pids=$(loop_pids)
if [[ -n "$pids" ]]; then
    echo "the Elise loop is already running (pid $pids)"
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        start_bench
        attach_info
    else
        echo "it runs outside the $SESSION tmux session: follow it with tools/loop/dashboard.sh elise" >&2
    fi
    exit 0
fi

# No arguments: reuse the scope of the last run (e.g. "--all --parallel 8").
if [[ $# -eq 0 ]]; then
    scope=""
    if [[ -f "$LOOP_JSON" ]]; then
        scope=$(.venv/bin/python -c 'import json,sys; print(json.load(open(sys.argv[1])).get("scope") or "")' \
            "$LOOP_JSON" 2>/dev/null || true)
    fi
    read -r -a args <<< "${scope:---all}"
    set -- "${args[@]}"
fi

# Wrong arguments: fail here, not inside a detached pane.
.venv/bin/python -m tools.loop check elise "$@"

# Never beside the readings loop (both write the audio.json files); Whisper judges on the GPU.
if pgrep -f "tools[.]loop run readings" >/dev/null; then
    echo "the readings loop is running: both write the audio.json files, wait for it to finish" >&2
    exit 1
fi
if command -v nvidia-smi >/dev/null && ! nvidia-smi -L >/dev/null 2>&1; then
    echo "warning: nvidia-smi does not see the GPU (see docs/machines.md, known failures)" >&2
fi

# A session left from a previous run (loop ended or crashed): replace it.
tmux kill-session -t "$SESSION" 2>/dev/null || true

cmd=$(printf '%q ' tools/elise/run.sh "$@")
tmux new-session -d -s "$SESSION" -n elise -c "$ROOT" -x 220 -y 50
tmux set-option -t "$SESSION" history-limit 50000 >/dev/null
tmux send-keys -t "$SESSION:elise.0" "$cmd; echo; echo \"Elise loop exited (\$?)\"" C-m
tmux split-window -h -t "$SESSION:elise" -c "$ROOT"
tmux send-keys -t "$SESSION:elise.1" "sleep 3; tools/loop/dashboard.sh elise" C-m
tmux select-pane -t "$SESSION:elise.0"
start_bench

sleep 3
if [[ -n "$(loop_pids)" ]]; then
    echo "Elise loop started: tools/elise/run.sh $*"
else
    echo "the loop did not start; its output:" >&2
    tmux capture-pane -p -t "$SESSION:elise.0" | grep -v '^$' | tail -20 >&2
    attach_info
    exit 1
fi
attach_info
