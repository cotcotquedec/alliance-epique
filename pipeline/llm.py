"""Structured calls to Claude through Claude Code in headless mode (`claude -p`).

No Python dependency and no key in the repository:
- by default the call uses the Claude Code login of this machine;
- with `bare=True` (CLI flag `--bare`) Claude Code reads ANTHROPIC_API_KEY only, for instance
  `export ANTHROPIC_API_KEY=$(security find-generic-password -s anthropic-api-key -w)`.

Each call is isolated: no tools, no session saved, no settings or CLAUDE.md (it runs in an empty
temporary directory), our own system prompt, a pinned model, and a JSON schema that Claude Code
enforces on the answer (`structured_output`).
"""

from __future__ import annotations

import json
import re
import subprocess
import tempfile
from dataclasses import dataclass

CLAUDE_BIN = "claude"


class LLMError(RuntimeError):
    pass


class LLMLimit(LLMError):
    """The subscription or API usage limit is reached: every next call would fail the same way."""


# Wording of Claude Code's usage-limit messages (subscription or API); unverified list, kept broad.
LIMIT_PATTERN = re.compile(r"usage limit|limit reached|hit your (usage )?limit|rate.?limit|out of (extra )?usage|"
                           r"(session|weekly|5-hour) limit|credit balance is too low", re.IGNORECASE)


def _failure(message: str) -> LLMError:
    return (LLMLimit if LIMIT_PATTERN.search(message) else LLMError)(message)


@dataclass
class Answer:
    data: dict
    model: str
    cost_usd: float


def claude_json(system: str, prompt: str, schema: dict, model: str, effort: str = "medium",
                bare: bool = False, timeout: float = 600.0, run=subprocess.run) -> Answer:
    cmd = [CLAUDE_BIN, "-p", "--model", model, "--effort", effort, "--tools", "",
           "--no-session-persistence", "--setting-sources", "", "--system-prompt", system,
           "--output-format", "json", "--json-schema", json.dumps(schema, ensure_ascii=False)]
    if bare:
        cmd.append("--bare")
    with tempfile.TemporaryDirectory(prefix="fs-llm-") as cwd:
        proc = run(cmd, input=prompt, capture_output=True, text=True, timeout=timeout, cwd=cwd)
    if proc.returncode != 0:
        raise _failure(f"claude exited with {proc.returncode}: {(proc.stderr or proc.stdout)[-500:]}")
    try:
        out = json.loads(proc.stdout)
    except json.JSONDecodeError as err:
        raise LLMError(f"claude returned no JSON: {proc.stdout[-300:]}") from err
    if out.get("is_error") or out.get("subtype") != "success" or not isinstance(out.get("structured_output"), dict):
        raise _failure(f"claude failed: {out.get('subtype')} {str(out.get('result'))[-300:]}")
    # Claude Code may make small side calls with another model (seen: Haiku listed first): the model
    # that wrote the answer is the one with the most output tokens.
    usage = out.get("modelUsage") or {}
    used = max(usage, key=lambda m: (usage[m] or {}).get("outputTokens") or 0) if usage else model
    return Answer(out["structured_output"], used, float(out.get("total_cost_usd") or 0))
