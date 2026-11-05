#!/usr/bin/env bash
# The quest readings, then the NPC dialogues, one after the other in a detached tmux session (one GPU), then prints
# how to attach. Waits first for the voice and Elise loops (they would share the GPU or the audio.json files).
# Safe to run again: a chain already running is left alone.
#   tools/loop/next.sh [readings options...]     (default: --all --parallel 8; the dialogues get --all --parallel 8)
#   tools/loop/next.sh --kill                     (stop the loop in progress and close the session)
# Session fs-next: the chain on the left, the dashboard of the loop in progress on the right.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
SESSION=fs-next

command -v tmux >/dev/null || { echo "tmux missing: sudo apt install -y tmux" >&2; exit 1; }

attach_info() {
    cat <<EOF

Attach:   tmux attach -t $SESSION
Detach:   Ctrl-b d   (the chain keeps running)
Status:   tools/loop/status.sh readings ; tools/loop/status.sh dialogues
Stop:     tools/loop/next.sh --kill   (nothing is lost: relaunching resumes)
EOF
}

if [[ "${1:-}" == "--kill" ]]; then
    pids=$(pgrep -f "tools[.]loop run (readings|dialogues)" || true)
    [[ -n "$pids" ]] && kill -INT $pids
    tmux kill-session -t "$SESSION" 2>/dev/null && echo "session $SESSION closed" || true
    exit 0
fi

if tmux has-session -t "$SESSION" 2>/dev/null && pgrep -f "next-chain[.]sh|tools[.]loop run (readings|dialogues)" >/dev/null; then
    echo "the chain is already running"
    attach_info
    exit 0
fi

[[ $# -eq 0 ]] && set -- --all --parallel 8
.venv/bin/python -m tools.loop check readings "$@"
chain="data/cache/loops/next-chain.sh"
mkdir -p "$(dirname "$chain")"
cat > "$chain" <<EOF
#!/usr/bin/env bash
cd "$ROOT"
echo "== waiting for the voice and Elise loops"
while pgrep -f "tools[.]loop run (voices|elise)" >/dev/null; do sleep 30; done
echo "== 1/2 readings loop"
tmux respawn-pane -k -t $SESSION:next.1 "tools/loop/dashboard.sh readings" 2>/dev/null || true
tools/readings/run.sh $(printf '%q ' "$@")
echo "== readings loop exited (\$?)"
echo "== 2/2 dialogues loop"
tmux respawn-pane -k -t $SESSION:next.1 "tools/loop/dashboard.sh dialogues" 2>/dev/null || true
tools/dialogues/run.sh --all --parallel 8
echo "== dialogues loop exited (\$?)"
EOF
chmod +x "$chain"
tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" -n next -c "$ROOT" -x 220 -y 50
tmux set-option -t "$SESSION" history-limit 50000 >/dev/null
tmux send-keys -t "$SESSION:next.0" "$chain" C-m
tmux split-window -h -t "$SESSION:next" -c "$ROOT"
tmux send-keys -t "$SESSION:next.1" "sleep 5; tools/loop/dashboard.sh readings" C-m
tmux select-pane -t "$SESSION:next.0"
echo "chain started: readings ($*), then dialogues (--all --parallel 8)"
attach_info
