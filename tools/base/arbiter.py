"""Arbiter of the base pass: what the actor's exit codes mean. READ-ONLY for the loop.
The policy itself is shared: tools/loop/arbiter.py. The base pass makes no paid call and never touches
Wowhead: no usage limit, no block; any failure (a GitHub download, the build) is retried once, then stops."""

from tools.loop.arbiter import Rules

RULES = Rules()
