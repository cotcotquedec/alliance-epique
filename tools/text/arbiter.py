"""Arbiter of the text pass: what the actor's exit codes mean. READ-ONLY for the loop.
The policy itself is shared: tools/loop/arbiter.py."""

from tools.loop.arbiter import Rules

RULES = Rules(
    limit=frozenset({75}),  # Claude usage limit (pipeline.zones EXIT_LIMIT): wait until it lifts
    blocked=frozenset({69}),  # Wowhead refused us, 403/429 (EXIT_BLOCKED): wait 60 min, one more try
)
