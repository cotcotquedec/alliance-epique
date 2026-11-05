"""Arbiter shared by the passes: after each attempt, commit, wait, roll back or stop. READ-ONLY for the loop.

Pure functions only. A pass (tools/text/arbiter.py, tools/audio/arbiter.py) gives its `Rules`: which exit
codes of its actor mean a usage limit, a block by a site, or a halt only a human can lift.

The level is a dict of counters given by the pass's oracle; the reference (`before`) is the ratchet,
the highest level ever reached. Policy:
- a counter below the ratchet: rollback (the attempt lost data), then stop;
- the oracle says the goal is reached: done;
- usage limit: wait until it lifts (reset time read from the output, else 30 min doubling up to 2 h),
  not counted as a failure;
- blocked (Wowhead 403/429): wait 60 min and try once more; two blocks in a row without progress stop;
- halt code: stop with the pass's message;
- any other code (0 included): progress -> next attempt after 1 min; no progress is a failure, a second
  one in a row stops with the end of the last output;
- at most `max_attempts` attempts.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field, replace
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

RETRY_WAIT = 60  # after an attempt that made progress
FAIL_WAIT = 5 * 60  # after a first failure without progress
BLOCK_WAIT = 60 * 60  # after a block by a site
LIMIT_WAIT = 30 * 60  # usage limit without a reset time: 30 min, then doubled...
LIMIT_WAIT_MAX = 2 * 60 * 60  # ...up to 2 h
LIMIT_MARGIN = 2 * 60  # after a parsed reset time, in case the clocks differ a little
LIMIT_HORIZON = timedelta(days=8)  # a reset time further than that is not believed (weekly limits are 7 days)

ACTIONS = ("done", "retry", "wait", "stop", "rollback")


@dataclass(frozen=True)
class Rules:
    limit: frozenset[int] = frozenset()  # usage limit: wait until it lifts
    blocked: frozenset[int] = frozenset()  # refused by a site: wait long, retry once
    halt: dict[int, str] = field(default_factory=dict)  # stop, with this message


@dataclass(frozen=True)
class State:
    attempt: int = 0  # attempts finished
    fails: int = 0  # consecutive failures without progress
    blocks: int = 0  # consecutive blocks, the last ones without progress
    limits: int = 0  # consecutive usage limits, for the backoff when no reset time is given
    max_attempts: int = 1000


def dropped(before: dict, after: dict) -> list[str]:
    """Counters of `before` that are lower (or missing) in `after`."""
    return [k for k, v in before.items() if after.get(k, -1) < v]


def progressed(before: dict, after: dict) -> bool:
    return not dropped(before, after) and any(after[k] > before.get(k, -1) for k in after)


# "Claude AI usage limit reached|1791300000" (epoch seconds), "resets 3pm", "resets 3:30pm (Europe/Paris)",
# "resets at 15:00". Unverified wordings, from the CLI's messages as seen so far.
EPOCH_PATTERN = re.compile(r"limit reached\|(\d{10})\b", re.IGNORECASE)
CLOCK_PATTERN = re.compile(r"resets?\s+(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?(?:\s*\(([A-Za-z_]+/[A-Za-z_/]+)\))?",
                           re.IGNORECASE)


def reset_time(text: str, now: datetime) -> datetime | None:
    """When the usage limit lifts, from the last mention in `text`; None if absent, past or implausible.
    A clock time without a time zone is read in the zone of `now` (aware), at its next occurrence."""
    found: list[tuple[int, datetime]] = []
    for m in EPOCH_PATTERN.finditer(text):
        found.append((m.start(), datetime.fromtimestamp(int(m.group(1)), now.tzinfo)))
    for m in CLOCK_PATTERN.finditer(text):
        hour, minute, half, zone = int(m.group(1)), int(m.group(2) or 0), (m.group(3) or "").lower(), m.group(4)
        if half:
            if not 1 <= hour <= 12:
                continue
            hour = hour % 12 + (12 if half == "pm" else 0)
        if hour > 23 or minute > 59 or (not half and m.group(2) is None):
            continue  # "resets 3" alone is not a time
        try:
            tz = ZoneInfo(zone) if zone else now.tzinfo
        except (ZoneInfoNotFoundError, ValueError):
            tz = now.tzinfo
        local = now.astimezone(tz)
        at = local.replace(hour=hour, minute=minute, second=0, microsecond=0)
        if at <= local:
            at += timedelta(days=1)
        found.append((m.start(), at))
    if not found:
        return None
    at = max(found, key=lambda f: f[0])[1]
    return at if now < at <= now + LIMIT_HORIZON else None


def _summary(output_tail: str, lines: int = 15) -> str:
    return "\n".join(output_tail.rstrip().splitlines()[-lines:])


def decide(exit_code: int, before: dict, after: dict, output_tail: str, state: State, now: datetime,
           rules: Rules) -> tuple[str, int, str]:
    """(action, seconds to wait, reason). `before` is the ratchet level, `after` the oracle's answer after the
    attempt ({"done", "next", "level"}), `state` the counters before the attempt."""
    level = after["level"]
    lost = dropped(before, level)
    if lost:
        return ("rollback", 0, f"DATA LOSS: {', '.join(f'{k} {before[k]} -> {level.get(k)}' for k in lost)}; "
                               "the attempt's files are in quarantine, the previous ones restored")
    if after["done"]:
        return ("done", 0, f"goal reached, level {level}")
    if exit_code in rules.halt:
        return ("stop", 0, rules.halt[exit_code])
    if state.attempt + 1 >= state.max_attempts:
        return ("stop", 0, f"maximum number of attempts reached ({state.max_attempts})")
    moved = progressed(before, level)
    if exit_code in rules.limit:
        at = reset_time(output_tail, now)
        if at is not None:
            wait = int((at - now).total_seconds()) + LIMIT_MARGIN
            return ("wait", wait, f"Claude usage limit, resets at {at.isoformat(timespec='minutes')}")
        wait = min(LIMIT_WAIT * 2 ** (0 if moved else state.limits), LIMIT_WAIT_MAX)
        return ("wait", wait, f"Claude usage limit, no reset time in the output: wait {wait // 60} min")
    if exit_code in rules.blocked:
        if not moved and state.blocks >= 1:
            return ("stop", 0, "refused by the site twice in a row without progress: investigate before "
                               "crawling again (see the attempt logs)")
        return ("wait", BLOCK_WAIT, "refused by the site (403/429): wait 60 min, then one more try")
    if moved:
        return ("retry", RETRY_WAIT, f"exit {exit_code}, progress to {level}")
    if state.fails >= 1:
        return ("stop", 0, f"exit {exit_code}, no progress twice in a row at {level}; "
                           f"end of the last attempt:\n{_summary(output_tail)}")
    return ("retry", FAIL_WAIT, f"exit {exit_code}, no progress at {level}: one more try")


def next_state(state: State, exit_code: int, before: dict, after: dict, rules: Rules) -> State:
    """The counters after an attempt: each counts consecutive attempts of its kind; progress resets them."""
    moved = progressed(before, after["level"])

    def keep(n: int) -> int:
        return 0 if moved else n

    attempt = state.attempt + 1
    if exit_code in rules.limit:
        return replace(state, attempt=attempt, fails=keep(state.fails), blocks=keep(state.blocks),
                       limits=keep(state.limits) + 1)
    if exit_code in rules.blocked:
        return replace(state, attempt=attempt, fails=keep(state.fails), blocks=keep(state.blocks) + 1, limits=0)
    return replace(state, attempt=attempt, fails=0 if moved else state.fails + 1, blocks=0, limits=0)
