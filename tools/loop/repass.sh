#!/usr/bin/env bash
# Global repass (2026-10-12): every generation loop once more, one after the other, over the whole game, to raise the
# completion. Each loop reopens what it did not find in its last run (5 more takes for every voice, reading, dialogue
# page and line of Elise still refused) and makes what is new. Order: text (personas and scripts still missing,
# Claude), voices (model voices), readings (quest audio), dialogues (NPC dialogue pages), Elise (ElevenLabs; waits
# when the credits are spent). One GPU: never two loops at once; the review decisions of the control page are applied
# by each loop before it starts. The base (Forever Database) is not touched: a sync is a human decision.
# Then the addon's index is rebuilt and tools/report.sh --all is written to the log.
#   tools/loop/repass.sh                    (start in the tmux session fs-repass, the dashboard on the right)
#   tools/loop/repass.sh --from readings    (start at a loop: text, voices, readings, dialogues or elise)
#   tools/loop/repass.sh --reset-ratchet    (after a wanted drop, e.g. tools/voices/redo.py: each loop's ratchet starts
#                                            again from its level at launch; can follow --from <loop>)
#   tools/loop/repass.sh --kill             (stop the loop in progress and close the session)
# Safe to run again: a repass already running is left alone. Log: data/cache/loops/repass.log
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
SESSION=fs-repass
LOOPS=(text voices readings dialogues elise)
LOG=data/cache/loops/repass.log
PIDFILE=data/cache/loops/repass.pid  # the chain's process (matched by pid, never by name: a name matches any shell)

command -v tmux >/dev/null || { echo "tmux missing: sudo apt install -y tmux" >&2; exit 1; }

attach_info() {
    cat <<EOF

Attach:   tmux attach -t $SESSION
Panes:    Ctrl-b o (switch), Ctrl-b z (zoom one pane), Ctrl-b [ (scroll, q to quit)
Detach:   Ctrl-b d   (the repass keeps running)
Status:   grep '^==' $LOG ; tools/report.sh --all
Stop:     tools/loop/repass.sh --kill   (nothing is lost: --from <loop> resumes)
EOF
}

chain_pid() { [[ -f $PIDFILE ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null && cat "$PIDFILE" || true; }
running() { chain_pid; pgrep -f "tools[.]loop run (text|voices|readings|dialogues|elise)" || true; }

if [[ "${1:-}" == "--kill" ]]; then
    pid=$(chain_pid)
    [[ -n "$pid" ]] && kill "$pid"
    rm -f "$PIDFILE"
    pids=$(pgrep -f "tools[.]loop run (text|voices|readings|dialogues|elise)" || true)
    [[ -n "$pids" ]] && kill -INT $pids
    tmux kill-session -t "$SESSION" 2>/dev/null && echo "session $SESSION closed" || true
    exit 0
fi

from=text
reset=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --from) from=${2:-}; shift 2
            [[ " ${LOOPS[*]} " == *" $from "* ]] || { echo "--from: one of ${LOOPS[*]}" >&2; exit 2; } ;;
        --reset-ratchet) reset=" --reset-ratchet"; shift ;;
        *) echo "unknown option $1 (--from <loop>, --reset-ratchet, --kill)" >&2; exit 2 ;;
    esac
done

if [[ -n "$(running)" ]]; then
    echo "a loop or a repass is already running (pid $(running | tr '\n' ' ')): wait for it, or --kill" >&2
    tmux has-session -t "$SESSION" 2>/dev/null && attach_info
    exit 1
fi

chain="data/cache/loops/repass-chain.sh"
mkdir -p "$(dirname "$chain")"
{
    echo "#!/usr/bin/env bash"
    echo "cd \"$ROOT\""
    echo "echo \$\$ > $PIDFILE"
    echo "echo \"== repass started \$(date '+%F %T')\""
    started=0
    for loop in "${LOOPS[@]}"; do
        [[ $loop == "$from" ]] && started=1
        [[ $started -eq 1 ]] || continue
        case $loop in
            text) cmd="tools/text/run.sh --all" ;;
            voices) cmd="tools/voices/run.sh --all" ;;
            readings) cmd="tools/readings/run.sh --all --parallel 8" ;;
            dialogues) cmd="tools/dialogues/run.sh --all --parallel 8" ;;
            elise) cmd="tools/elise/run.sh --all" ;;
        esac
        echo "echo \"== $loop: $cmd (\$(date '+%T'))\""
        echo "tmux respawn-pane -k -t $SESSION:repass.1 \"tools/loop/dashboard.sh $loop\" 2>/dev/null || true"
        [[ $loop == text ]] || cmd+=$reset
        echo "$cmd; echo \"== $loop exited (\$?) \$(date '+%T')\""
    done
    echo ".venv/bin/python -m pipeline.build_index"
    echo "tools/report.sh --all | tail -3"
    echo "rm -f $PIDFILE"
    echo "echo \"== repass done \$(date '+%F %T')\""
} > "$chain"
chmod +x "$chain"

tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" -n repass -c "$ROOT" -x 220 -y 50
tmux set-option -t "$SESSION" history-limit 50000 >/dev/null
tmux send-keys -t "$SESSION:repass.0" "$chain 2>&1 | tee -a $LOG" C-m
tmux split-window -h -t "$SESSION:repass" -c "$ROOT"
tmux send-keys -t "$SESSION:repass.1" "sleep 5; tools/loop/dashboard.sh $from" C-m
tmux select-pane -t "$SESSION:repass.0"
echo "repass started from $from: ${LOOPS[*]}"
attach_info
