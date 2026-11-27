#!/usr/bin/env python3
"""Where a hook keeps Skill Deck's own state: the development checkout's `.scratch` (#704, #1214).

`bench sync` runs the hooks from a read-only installed worktree, `<install>/<sha>`, that the next
sync removes. State written there would fail or be lost, so a hook resolves its checkout through
the worktree's `.git` file (`gitdir: <checkout>/.git/worktrees/<name>`) and writes under that
checkout. A script run from the checkout itself, or from a copy with no `.git` file, keeps its own
folder.
"""

from __future__ import annotations

import os
from collections.abc import Mapping
from pathlib import Path

# Each per-user root's app name, one place each (#1670). They differ today, and the folders stay where
# they are; the #705 and #1636 renames change these two constants and nothing else.
CACHE_APP = "skd"
CONFIG_APP = "skill-deck"
# The XDG Base Directory variables and their defaults under HOME.
XDG = {"cache": ("XDG_CACHE_HOME", ".cache"), "state": ("XDG_STATE_HOME", ".local/state"),
       "config": ("XDG_CONFIG_HOME", ".config"), "data": ("XDG_DATA_HOME", ".local/share")}


def checkout(root: Path) -> Path:
    """The development checkout that owns ROOT, or ROOT itself."""
    marker = root / ".git"
    try:
        text = marker.read_text(encoding="utf-8") if marker.is_file() else ""
    except OSError:
        return root
    if not text.startswith("gitdir:"):
        return root
    gitdir = Path(text.split(":", 1)[1].strip())
    if not gitdir.is_absolute():
        gitdir = (root / gitdir).resolve()
    if gitdir.parent.name == "worktrees" and gitdir.parent.parent.name == ".git":
        return gitdir.parent.parent.parent
    return root


def scratch(root: Path) -> Path:
    """The `.scratch` folder a hook under ROOT writes its state in."""
    return checkout(root) / ".scratch"


def _root(kind: str, app: str, environ: Mapping[str, str] | None) -> Path:
    """`$XDG_<KIND>_HOME/<app>`, else `~/<default>/<app>`: an empty or relative value is ignored, as the
    XDG Base Directory spec says. Read at call time, so a test that patches the environment drives it."""
    env = os.environ if environ is None else environ
    name, default = XDG[kind]
    value = env.get(name, "")
    base = Path(value) if value and os.path.isabs(value) else Path(env.get("HOME") or Path.home()) / default
    return base / app


def cache(environ: Mapping[str, str] | None = None) -> Path:
    """Workbench's per-user cache: the GitHub read cache, the App token, the session presence files
    and the heavy lock, which heavy.sh, the presence hook text and the menu bar read by the same rule (#1670)."""
    return _root("cache", CACHE_APP, environ)


def state(environ: Mapping[str, str] | None = None) -> Path:
    """Workbench's per-user state: the catch-up, red-revert and runner-queue ledgers (#1670)."""
    return _root("state", CACHE_APP, environ)


def config(environ: Mapping[str, str] | None = None) -> Path:
    """The owner's Workbench settings: accounts.json; long-run.json joins with mac_prepare.py (#1670)."""
    return _root("config", CONFIG_APP, environ)


def long_run(environ: Mapping[str, str] | None = None) -> Path:
    """The owner's long-run settings, which `mac_prepare.py` and `run_level.py` both read (#1670)."""
    return config(environ) / "long-run.json"


def data(environ: Mapping[str, str] | None = None) -> Path:
    """Workbench's per-user data: the installed worktrees (#1670)."""
    return _root("data", CONFIG_APP, environ)
