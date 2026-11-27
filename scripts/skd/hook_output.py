#!/usr/bin/env python3
"""How every Workbench hook refuses a call and reports an error, in one form (#1679).

`refuse(reason)` writes the reason to stderr and returns 2: Claude Code blocks the tool call, the
prompt or the stop on exit 2 and hands stderr to the agent. `error(script, text)` writes one
`Error: <script>: <text>` line to stderr, where `<script>` is the hook's file name without `.py`.
Every hook `settings_hooks.py` registers imports it, those under `skills/` through the checkout's
`scripts/bench`; `tests/test_hook_output.py` checks each one.
"""

from __future__ import annotations

import sys
from pathlib import Path

BLOCK = 2  # the exit status Claude Code reads as a refusal


def name(script: str) -> str:
    """The prefix name of a hook: its file name without the folder or `.py`."""
    return Path(script).stem


def error(script: str, text: str) -> None:
    sys.stderr.write(f"Error: {name(script)}: {text.rstrip(chr(10))}\n")


def unreadable(script: str, path: object, reason: object) -> None:
    """The error line of a hook that cannot read one of its files."""
    error(script, f"{path} cannot be read: {reason}")


def refuse(reason: str) -> int:
    sys.stderr.write(reason if reason.endswith("\n") else reason + "\n")
    return BLOCK
