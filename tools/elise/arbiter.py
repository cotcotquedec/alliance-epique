"""Arbiter of the Elise loop: what the actor's exit codes mean. READ-ONLY for the loop.
The policy itself is shared: tools/loop/arbiter.py."""

from tools.loop.arbiter import Rules

RULES = Rules(
    limit=frozenset({75}),  # ElevenLabs credits spent: wait for them to come back
    halt={
        77: "Elise has no voice, ElevenLabs refused the key, or the voice environment is missing: see the log",
    },
)
