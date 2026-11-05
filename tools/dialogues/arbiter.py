"""Arbiter of the dialogues loop: what the actor's exit codes mean. READ-ONLY for the loop.
The policy itself is shared: tools/loop/arbiter.py."""

from tools.loop.arbiter import Rules

RULES = Rules(
    halt={
        77: "the voice environment is missing: tools/voices/setup.sh, then rerun the dialogues loop",
    },
)
