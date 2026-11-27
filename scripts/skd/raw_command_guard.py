#!/usr/bin/env python3
"""Refuse a raw command that a Skill Deck script owns, before it runs (#506).

    raw_command_guard.py check        hook mode: the client's PreToolUse JSON on stdin
    raw_command_guard.py scan COMMAND  the same verdict for one command string

The map is `raw-commands.tsv` in the CLI folder, `scripts/bench/` (#1230). `check` also refuses a GitHub MCP write (#1211): a
`tool_name` `mcp__<server>__<tool>` whose server name holds `github` (any case) and whose tool
`github-write-tools.tsv` there lists, such as `create_pull_request` or
`add_issue_comment`. It names the script that scans and reads back, exits 2, and has no bypass: the
script, or git for a file, does the same write. Every other MCP tool, reads included, passes. `check` reads Claude Code's
payload (`tool_name` "Bash", `tool_input.command`), splits the command into simple commands at `&&`, `||`, `;`, `|`,
`&`, newlines, `$(...)` and `sh -c` (also `-lc` or `-e -c`), skips `do`, `then`, `if`, `while`, `{`
and the other words that open a loop or conditional body, `env`-style wrappers and `xargs` with its
options, and compares each with the map (#666). It also reads the programs a command runs (#658):
`python -c` code, a here-document fed to a shell or Python, and a script file outside this skills
folder run by a shell or Python, unless it is committed and unchanged in the repository the command
runs in (#1168); a file Git tracks under this checkout's `scripts/` folder is Skill
Deck's own too (#848). A linked worktree of the same repository counts as this one (#717): its `.git` file must name an admin folder that points back at it, and
that folder's common directory must be this checkout's. In Python code that starts a process, a
string literal that is or begins with `gh` is judged with the literals after it. A `gh api` write to an issue or its
comments (a method other than GET, or a field) is refused with the script that owns the step. On a match it writes the
owning script and its usage line to stderr and exits 2, the status Claude Code documents as a
block. Anything else passes, an unreadable payload or another tool
included: the guard keeps agents on the scripts, it is not a security boundary.

A `gh` help request (`-h` or `--help` before any `--`, and not the value of the option before it)
only prints help, so it passes.

One rule needs no map row: a recursive `grep` (`-r`, `-R`, `--recursive`, `-d recurse`) typed by the
agent is refused and `rg` named instead, because it reads ignored build folders such as SwiftPM's
`.build` and takes minutes where `rg` takes under a second (#686). Only the typed command is judged,
never a script file or program it runs, so a project script that uses `grep -r` still runs. One
whose paths are all regular files reads nothing more than a plain `grep`, so it passes (#773); a
typed `cd` before it moves the folder those paths resolve from (#816).

A second rule needs no row either: a typed `git commit --no-verify` (or `-n`, or a prefix of
`--no-verify` git accepts, such as `--no-verif`), `git push --no-verify` or
`git -c core.hooksPath=...` skips the pre-commit secret scan and the commit-msg rules, so it is
refused (#685, #773). So is a typed write of that key, which lasts for every later commit: `git
config [--global] core.hooksPath X`, `--unset` or `--add` it, `git --config-env=core.hooksPath=VAR`,
and `GIT_CONFIG_KEY_<n>=core.hooksPath` or `GIT_CONFIG_PARAMETERS` naming it; a read such as `git
config --get core.hooksPath` passes (#1283).

A third: a typed `git push` that rewrites the remote branch (`-f`, `--force`, `--force-with-lease`,
a `+` refspec, `--mirror`, a mirror remote, #815) is refused with a pointer to the one force push allowed (#507, #773). gh's inherited
`-R`/`--repo` is dropped before a `gh` command meets the map, wherever it stands (#773).

A fourth: a typed `gh pr merge` is refused, because only the owner's ask, `bench-cleanup`'s
per-item yes or a level-high `bench-backlog` lane after a passing review may merge (the merge rule
in `issue-closure.md`); the command cannot show which, so the bypass reason names it (#773). In a
Claude Code cloud session one merge passes with no bypass: `gh pr merge <N> --merge` of a Dependabot
pull request `unattended.py` would merge there, read from GitHub first (owner D146 B, #953).

A fifth: a typed command that finds processes by name, `pkill` with a pattern or `-f`, `killall`, or
`pgrep -f` (also in a cluster such as `-lf`, or `--full`), is refused with the captured PID named
instead, since a name can match another lane's process or the agent's own shell (#747, #1344).
`pgrep -x NAME`, `pgrep -P PID`, `pkill -P PID` and `kill PID` pass.

A sixth: a Bash command run in the background (Claude Code's `run_in_background`) whose whole body
only waits, as `waiters.py` in bench-backlog defines it (a loop on local state, or a lone `sleep`),
is refused, a lone `sleep` only over 60 seconds: the harness wakes the agent when its own command
ends (#876, #1344). A loop that polls an outside system (`gh`, `curl`) is a bounded wait and passes.

A seventh: a typed shell form Claude Code's own parser cannot read, which makes it ask for a
confirmation that bypass mode does not skip, so an unattended run waits on it (#1405): a zsh
parameter flag or word split (`${(f)...}`, `${=x}`, `$=x`), a `$(...)`, `${...}` or backtick
inside `${...}`, a backtick substitution, `eval`, and `rm` with a variable or a glob. Single-quoted
text and a here-document with a quoted delimiter are data and pass; an unquoted here-document's
body expands, so it is read. The refusal names the plain form: a pipe to `xargs`, one `x=$(cmd)`
on its own, a file the Write tool wrote, a literal path.

A command prefixed with `SKD_ALLOW_RAW="<reason>"` passes after the owner approved it; the guard
appends the time, directory, reason and command to `.scratch/raw-command-bypass.log` in the
Skill Deck checkout this script belongs to, never under `HOME` (#704), which `bench doctor` reports
until each entry becomes an issue that extends the script. A bypass of a rule no script will ever
own (a merge, a force push, a hook skip) adds the rule's name as a fifth field, so `bench doctor`
keeps it as a record and does not ask for an issue (#773).

The scripts' own `gh` calls run as their subprocesses, not as agent tool calls, so no hook sees
them; running a script (`python3 close_issue.py ...`) is not a raw command and passes.
"""

from __future__ import annotations

import fnmatch
import glob
import json
import os
import re
import shlex
import signal
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
# The CLI folder holds the helpers and data this reads: one up from scripts/bench/hooks/ (#1230), or this
# file's own folder in the flat copy another repository commits (`settings_hooks.py vendor`, #1287).
LIB = HERE.parent if HERE.name == "hooks" else HERE
sys.path[:0] = [str(HERE), str(LIB)]  # hooks/ first: LIB holds the forwarders of its modules
sys.dont_write_bytecode = True  # a hook leaves no __pycache__ in the tree it runs from
from hook_output import error as hook_error, refuse, unreadable  # one form for every hook (#1679)
try:  # a hook never fails on its state folder: a copy of this script alone keeps its own (#1214)
    from state_home import scratch
except ImportError:
    def scratch(root: Path) -> Path:
        return root / ".scratch"

MAP = LIB / "raw-commands.tsv"
GITHUB_TOOLS = LIB / "github-write-tools.tsv"
# `mcp__<server>__<tool>`: a tool name holds no `__`, so the server is everything before the last one.
MCP_TOOL = re.compile(r"mcp__(?P<server>.+)__(?P<tool>[A-Za-z0-9-]+(?:_[A-Za-z0-9-]+)*)")
SKILLS = LIB.parents[1] / "skills"
BYPASS = "SKD_ALLOW_RAW"
# Skill Deck's own state, so it lives in this checkout's scratch folder (#704).
LOG = scratch(SKILLS.parent) / "raw-command-bypass.log"
SEPARATORS = set(";&|()\n")
WRAPPERS = {"env", "command", "exec", "nohup", "time", "builtin", "sudo"}  # sudo since #1417
# Shell words that open a loop or conditional body: the command after them runs (#666).
KEYWORDS = {"do", "then", "else", "elif", "if", "while", "until", "!", "{", "}"}
# xargs options that take their value as the next word.
XARGS_VALUE = {"-n", "-I", "-i", "-L", "-l", "-P", "-d", "-E", "-e", "-s", "-a", "-J", "-R", "-S"}
SHELLS = {"sh", "bash", "zsh", "dash"}
PYTHON = re.compile(r"^python(\d+(\.\d+)?)?$")
LAUNCH = re.compile(r"\b(subprocess|os\.system|os\.popen|os\.exec\w*|os\.spawn\w*|pty\.spawn|Popen)\b")
LITERAL = re.compile(r"""(["'])((?:\\.|(?!\1).)*)\1""")
# `gh api` options whose value is the next word, so it is not taken for the endpoint.
API_VALUE = {"-X", "--method", "-f", "--raw-field", "-F", "--field", "-H", "--header", "--input", "-q", "--jq",
             "-t", "--template", "--cache", "-p", "--preview", "--hostname"}
API_FIELDS = {"-f", "--raw-field", "-F", "--field", "--input"}
API_ISSUE = re.compile(r"^/?repos/[^/]+/[^/]+/issues(?P<rest>/[^/]+|/[^/]+/comments|/comments/[^/]+)?/?$")
# Pull request and relation endpoints a script owns (#1211): the map row each write is refused with.
# A number is any one path segment, so `<parent>` or `$n` in a skill's example counts as one.
API_PULL = re.compile(r"^/?repos/[^/]+/[^/]+/pulls(?P<rest>/[^/]+(/comments(/[^/]+/replies)?|/reviews|/merge)?|/comments/[^/]+/replies)?/?$")
API_RELATION = re.compile(r"^/?repos/[^/]+/[^/]+/issues/[^/]+/(sub_issues?(/priority)?|dependencies/blocked_by(/[^/]+)?)/?$")
# Repository, release and gist endpoints that carry text a script owns (#1289).
API_REPO = re.compile(r"^/?repos/[^/]+/[^/]+/?$")
API_RELEASE = re.compile(r"^/?repos/[^/]+/[^/]+/releases(?P<rest>/[^/]+)?/?$")
API_GIST = re.compile(r"^/?gists(?P<rest>/[^/]+)?/?$")
# An Actions write (a dispatch, rerun, cancel or delete): the App token a Mac session exports reads
# Actions only, so it answers HTTP 403; gh_rest.py runs it on the owner's login (#1980).
API_ACTIONS = re.compile(r"^/?repos/[^/]+/[^/]+/actions/(workflows|runs|caches|jobs)(/|$)")
SCRIPT_LIMIT = 1_000_000
GIT_SECONDS = 5  # a local `git` read the guard waits for before it gives up
# A here-string (`<<< word`) opens no here-document, so its `<<` never counts (#1410).
HEREDOC = re.compile(r"(?<!<)<<(?!<)-?\s*(['\"]?|\\)([A-Za-z_][A-Za-z0-9_]*)(?(1)['\"]?)")
HELP = {"-h", "--help"}
GREP = {"grep", "egrep", "fgrep"}
# Typed commands that move the shell to another folder, followed for the paths after them (#816).
FOLDER_CHANGES = {"cd", "pushd", "popd"}
# grep's short options that take a value: in a cluster, the rest of the word (or the next word) is it.
GREP_VALUE = set("efmABCdD")
GREP_RECURSIVE = {"--recursive", "--dereference-recursive", "--directories=recurse"}
# grep's long options that take a value: without `=`, the next word is it (#843), as `ggrep --help` lists them.
# shortcut: an abbreviated one (`--exclude-d build`) is read as taking none; match prefixes if a bypass shows one.
GREP_LONG_VALUE = {
    "--after-context", "--before-context", "--binary-files", "--context", "--devices", "--directories",
    "--exclude", "--exclude-dir", "--exclude-from", "--file", "--group-separator", "--include",
    "--label", "--max-count", "--regexp",
}
SEARCH = {
    "script": None,
    "usage": "rg PATTERN [PATH] (follows .gitignore); rg -u PATTERN to include ignored files; "
             "git grep PATTERN for tracked files",
}
# git's global options whose value is the next word, before the subcommand (#685).
GIT_VALUE = {"-c", "-C", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env"}
# `git config` options that write or remove a key, and those that only read (#1283).
CONFIG_WRITES = {"--unset", "--unset-all", "--add", "--replace-all"}
CONFIG_READS = {"--get", "--get-all", "--get-regexp", "--get-urlmatch", "-l", "--list"}
# `git commit` short options whose value is the rest of the word or the next word.
COMMIT_VALUE = set("mFCctS")
HOOKS = {
    "script": None,
    "usage": "commit and push with the hooks; fix what a hook refuses, never skip it",
}
FORCE = {
    "script": None,
    "usage": "push without --force; the one force push allowed purges sensitive data from history, "
             "on the owner's approval of that exact push (bench-github-publishing, section 2, #507)",
}
MERGE = {
    "script": None,
    "usage": "merge only as the merge rule allows: the owner's ask, bench-cleanup's per-item yes, or a "
             "level-high bench-backlog lane after a passing bench-issue-review "
             "(bench-github-publishing, references/issue-closure.md, #476, #712)",
}
PROCESS = {
    "script": None,
    "usage": 'the PID captured when the task started: `kill -0 "$pid"` to check it, `wait "$pid"` to wait '
             'for it, `kill "$pid"` to stop it; `pgrep -x NAME` to check that a program runs (#747)',
}
WAITER = {
    "script": None,
    "usage": "run the work itself in the background, or nothing: the harness wakes you when your own "
             "background command ends (#876)",
}
# Shell forms Claude Code's own parser cannot read, so it asks for a confirmation that bypass mode
# does not skip, and an unattended run waits on it for hours (#1405): each with its plain form.
PROMPT_FORMS = {
    "zsh flag": {
        "script": None,
        "what": "a zsh parameter flag or word split",
        "usage": "a pipe, `cmd | xargs CMD`, or a list in a file (the Write tool, or `cmd > list.txt`) "
                 "read with `xargs CMD < list.txt`",
    },
    "nested": {
        "script": None,
        "what": "a command or expansion inside `${...}`",
        "usage": "one simple step per value: `x=$(cmd)` on its own, then `\"$x\"`; or a pipe to "
                 "`xargs CMD`",
    },
    "eval": {
        "script": None,
        "what": "`eval`",
        "usage": "run the command as written; build its arguments with a pipe to `xargs CMD` or a file",
    },
    "backtick": {
        "script": None,
        "what": "a backtick command substitution",
        "usage": "`$(cmd)` for a command's output; text that shows backticks (a commit or issue body) in "
                 "single quotes, a quoted here-document (`<<'EOF'`) or a file the Write tool wrote",
    },
    "rm": {
        "script": None,
        "what": "`rm` with a variable or a glob",
        "usage": "`trash PATH` or `rm` with each path written out in full, a `mktemp -d` folder by the "
                 "literal path it printed, a list as `cmd | xargs trash`",
    },
}
# The characters after `${` or `$` that start a zsh flag or word split: `${(f)x}`, `${=x}`, `$=x` (#1405).
ZSH_FLAG = set("(=~^")
# `$=x`, `$~x`, `$^x`: the same split or flag on a bare name.
ZSH_SPLIT = re.compile(r"\$[=~^][A-Za-z_][A-Za-z0-9_]*")
SLEEP_FLOOR = 60  # seconds a lone background `sleep` may last (#1344)
# Shell words before a command that set a variable, as `SKD_ALLOW_RAW="..." sleep 600`.
ASSIGNMENT = re.compile(r"""([A-Za-z_][A-Za-z0-9_]*)=("[^"]*"|'[^']*'|\S*)\s+""")
WAITERS = SKILLS / "bench-backlog" / "scripts"
# pgrep and pkill short options whose value is the rest of the word or the next word (BSD and procps).
PGREP_VALUE = set("dFGgPtUusc")
# Their long options (procps) whose value is the next word unless written with `=`.
PGREP_LONG_VALUE = {"--delimiter", "--pidfile", "--group", "--pgroup", "--parent", "--terminal", "--euid", "--uid",
                    "--session", "--signal", "--ns", "--nslist", "--env", "--runstates", "--cgroup"}
# pkill's `-SIGNAL` words (`-STOP`, `-SIGTSTP`): one token, since a name ending in a value letter (`-STOP`, `P`)
# must not swallow the next word (#1344).
SIGNAL_WORDS = {name for sig in signal.Signals if sig.name.startswith("SIG")
                for name in (sig.name, sig.name[3:])}
# Rules no script will ever own: their bypass is the owner's approval, kept as a record (#773).
OWNER_RULES = {id(HOOKS): "hook skip", id(FORCE): "force push", id(MERGE): "merge",
               id(PROCESS): "process by name", id(WAITER): "background waiter",
               **{id(row): "prompting shell form" for row in PROMPT_FORMS.values()}}
GLOB = re.compile(r"[*?\[]")


def load_map(path: Path = MAP) -> list[dict]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        command, flags, script, usage = line.split("\t")
        rows.append({
            "words": command.split(),
            "flags": [] if flags == "-" else flags.split(","),
            "script": script,
            "usage": usage,
        })
    return rows


def load_github_tools(path: Path = GITHUB_TOOLS) -> dict[str, dict]:
    """The GitHub MCP write tools, each with its owning script and usage line (#1211)."""
    tools = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        tool, script, usage = line.split("\t")
        tools[tool] = {"tool": tool, "script": None if script == "-" else script, "usage": usage}
    return tools


def github_write(tool_name: str, tools: dict[str, dict]) -> dict | None:
    """The row of a GitHub MCP write tool, else None: `mcp__<server>__<tool>` on a server whose
    name holds `github`, with a listed tool (#1211)."""
    found = MCP_TOOL.fullmatch(tool_name)
    if not found or "github" not in found["server"].lower():
        return None
    return tools.get(found["tool"])


def script_path(relative: str) -> str:
    """Where the owning script is: in this checkout, or for a copy of the guard in another repository,
    which has no skills folder, in a Workbench checkout (#1287)."""
    if SKILLS.is_dir():
        return str(SKILLS / relative)
    return f"skills/{relative} in a martonpaulo/workbench checkout (this repository carries a copy of the guard)"


def mcp_refusal(tool_name: str, row: dict) -> str:
    lines = [f"Refused: `{tool_name}` writes to GitHub without the sensitive-data scan and the read-back (#1211)."]
    if row["script"]:
        lines.append(f"  script: {script_path(row['script'])}")
    lines += [
        f"  usage:  {row['usage']}",
        "Run that instead, in the shell; an MCP write has no bypass. If the script cannot do this step,",
        "ask the owner, and report it in martonpaulo/workbench (bench-github-publishing, section 15).",
    ]
    return "\n".join(lines) + "\n"


def tokens(text: str) -> list[str]:
    """Shell words, with each run of separator characters as its own token."""
    lexer = shlex.shlex(text, posix=True, punctuation_chars=";&|()\n")
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    lexer.commenters = ""
    return list(lexer)


def without_heredoc_bodies(text: str) -> str:
    """Drop here-document bodies: they are data on stdin, never commands."""
    kept, ending = [], []
    for line in text.split("\n"):
        if ending:
            if line.strip() == ending[0]:
                ending.pop(0)
            continue
        kept.append(line)
        ending = [found.group(2) for found in HEREDOC.finditer(line)]
    return "\n".join(kept)


def simple_commands(text: str, depth: int = 0) -> list[list[str]]:
    """Split a command line into its simple commands, each a list of words."""
    text = without_heredoc_bodies(text)
    try:
        words = tokens(text)
    except ValueError:
        # An unbalanced quote, as in a heredoc body: judge each line on its own.
        words = []
        for line in text.splitlines():
            try:
                words += tokens(line) + ["\n"]
            except ValueError:
                words += line.split() + ["\n"]
    found: list[list[str]] = []
    current: list[str] = []
    for word in words:
        if word and set(word) <= SEPARATORS:
            if current:
                found.append(current)
            current = []
            continue
        if word.startswith("$") and word.rstrip("$") == "":
            continue  # the `$` of `$(`
        current.append(word.lstrip("`").rstrip("`") if "`" in word else word)
    if current:
        found.append(current)
    if depth < 3:
        nested = []
        for words in found:
            inline = shell_inline(strip_prefix(words)[1])
            if inline is not None:
                nested += simple_commands(inline, depth + 1)
        found += nested
    return [words for words in found if words]


def shell_inline(words: list[str]) -> str | None:
    """The command string of `bash -c '...'`, also `-lc`, `-ec` or `-l -c` (#666)."""
    if not words or Path(words[0]).name not in SHELLS:
        return None
    for index, word in enumerate(words[1:], 1):
        if not word.startswith("-") or word.startswith("--"):
            return None
        if "c" in word[1:]:
            return words[index + 1] if index + 1 < len(words) else None
    return None


def heredoc_blocks(text: str) -> list[tuple[str, str]]:
    """Each here-document as (the line that opens it, its body)."""
    blocks, ending, opener, body = [], [], "", []
    for line in text.split("\n"):
        if ending:
            if line.strip() == ending[0]:
                ending.pop(0)
                blocks.append((opener, "\n".join(body)))
                body = []
            else:
                body.append(line)
            continue
        ending = [found.group(2) for found in HEREDOC.finditer(line)]
        opener = line
    return blocks


def operands(words: list[str]) -> list[str]:
    """The words after the program that are neither options nor redirections."""
    found, skip = [], False
    for word in words[1:]:
        if skip:
            skip = False
            continue
        if word in {"<", "<<", "<<-", "<<<", ">", ">>"}:
            skip = True
            continue
        if word.startswith(("-", "<", ">")) and word != "-":
            continue
        found.append(word)
    return found


def interpreter(words: list[str]) -> str | None:
    """`shell` or `python` when the command runs code it reads from stdin or a script file."""
    if not words:
        return None
    name = Path(words[0]).name
    if name in SHELLS:
        return "shell"
    if PYTHON.match(name):
        return "python"
    return None


def code_commands(code: str) -> list[list[str]]:
    """The `gh` calls written as string literals in program code (#658).

    `subprocess.run(["gh", "issue", "comment", n])` and `os.system("gh issue comment 3")` both put
    the words in literals. Only code that starts a process is read, and only a literal that is `gh`
    itself or begins with the word `gh`, so a script that edits text about these commands passes.
    The words after it are the rest of that literal and the literals that follow, split at whitespace.
    """
    if not LAUNCH.search(code):
        return []
    literals = [found.group(2) for found in LITERAL.finditer(code)]
    found = []
    for index, literal in enumerate(literals):
        first = literal.split(None, 1)
        if first and Path(first[0]).name == "gh":
            found.append([word for text in literals[index:] for word in text.split()])
    return found


def common_dir(root: Path) -> Path | None:
    """The Git common directory of the checkout at `root`, the main one or a linked worktree (#717).
    A `.git` file counts only when its admin folder points back at it, as `git worktree` registers
    it, so a copied or hand-written `.git` file is not taken for one of this repository's worktrees."""
    dot_git = root / ".git"
    if dot_git.is_dir():
        return dot_git.resolve()
    if not dot_git.is_file():
        return None
    text = dot_git.read_text(encoding="utf-8", errors="replace").strip()
    if not text.startswith("gitdir:"):
        return None
    admin = (root / text[len("gitdir:"):].strip()).resolve()
    back, common = admin / "gitdir", admin / "commondir"
    if not back.is_file() or not common.is_file():
        return None
    registered = admin / back.read_text(encoding="utf-8", errors="replace").strip()
    if registered.resolve() != dot_git.resolve():
        return None
    return (admin / common.read_text(encoding="utf-8", errors="replace").strip()).resolve()


def tracked(root: Path, resolved: Path) -> bool:
    """Whether the file is committed and unchanged in the checkout at `root` (#852): in `HEAD`, with
    no staged or unstaged change, so a new script passes only once it is committed."""
    relative = str(resolved.relative_to(root))
    try:
        listed = subprocess.run(["git", "ls-tree", "--name-only", "HEAD", "--", relative],
                                cwd=root, capture_output=True, text=True, timeout=GIT_SECONDS)
        if listed.returncode != 0 or not listed.stdout.strip():
            return False
        return subprocess.run(["git", "diff", "--quiet", "HEAD", "--", relative],
                              cwd=root, capture_output=True, timeout=GIT_SECONDS).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def own_script(resolved: Path) -> bool:
    """Under the skills folder, or a committed, unchanged file under the scripts folder (#848, #852), of this
    checkout or of a linked worktree of the same repository (#717)."""
    if resolved.is_relative_to(SKILLS):
        return True
    root = next((parent for parent in resolved.parents if (parent / ".git").exists()), None)
    if root is None:
        return False
    if root != SKILLS.parent:
        home = common_dir(SKILLS.parent)
        if home is None or common_dir(root) != home:
            return False
    if resolved.is_relative_to(root / "skills"):
        return True
    return resolved.is_relative_to(root / "scripts") and tracked(root, resolved)


def project_script(resolved: Path, cwd: str) -> bool:
    """A committed, unchanged file of the repository the command runs in (#1168): a project's own
    script calls `gh` on purpose, and an agent's typed `gh` command is still judged on its own."""
    root = next((parent for parent in resolved.parents if (parent / ".git").exists()), None)
    if root is None:
        return False
    here = Path(cwd).expanduser().resolve()
    return (here == root or here.is_relative_to(root)) and tracked(root, resolved)


def script_text(path: str, cwd: str) -> str | None:
    """A script file's text, except a script its repository owns, which calls `gh` on purpose."""
    file = Path(cwd, path).expanduser()
    try:
        resolved = file.resolve()
        if own_script(resolved) or project_script(resolved, cwd) or not resolved.is_file() or resolved.stat().st_size > SCRIPT_LIMIT:
            return None
        return resolved.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None


def written_programs(command: str, cwd: str) -> list[list[str]]:
    """The `gh` calls inside programs the command runs: `python -c`, a here-document fed to a shell
    or Python, and a script file outside Skill Deck run by a shell or Python (#658)."""
    found: list[list[str]] = []
    for words in simple_commands(command):
        rest = strip_prefix(words)[1]
        kind = interpreter(rest)
        if kind == "python" and "-c" in rest[1:-1]:
            found += code_commands(rest[rest.index("-c") + 1])
            continue
        targets = operands(rest)
        if kind and targets and targets[0] != "-" and shell_inline(rest) is None:
            text = script_text(targets[0], cwd)
            if text is not None:
                found += simple_commands(text) if kind == "shell" else code_commands(text)
    for opener, body in heredoc_blocks(command):
        for words in simple_commands(opener):
            rest = strip_prefix(words)[1]
            kind = interpreter(rest)
            targets = operands(rest)
            if kind and (not targets or targets[0] == "-") and shell_inline(rest) is None:
                found += simple_commands(body) if kind == "shell" else code_commands(body)
    return found


def strip_prefix(words: list[str]) -> tuple[dict, list[str]]:
    """Leading `NAME=value` assignments and wrapper words, then the command itself."""
    assignments = {}
    index = 0
    while index < len(words):
        word = words[index]
        name, equals, value = word.partition("=")
        if equals and name.isidentifier():
            assignments[name] = value
        elif word in WRAPPERS or word in KEYWORDS:
            pass
        elif Path(word).name == "xargs":
            index += 1
            while index < len(words) and words[index].startswith("-"):
                index += 2 if words[index] in XARGS_VALUE else 1
            continue
        else:
            break
        index += 1
    return assignments, words[index:]


def asks_for_help(words: list[str]) -> bool:
    """Whether gh prints help instead of running: a help flag before `--`, not an option's value.

    `gh issue comment 12 --help` only prints help; in `--body --help` the flag is the body, and
    after `--` it is a positional argument, so both still run the command.
    """
    for index, word in enumerate(words):
        if word == "--":
            return False
        if word in HELP:
            before = words[index - 1] if index else ""
            return not (before.startswith("-") and "=" not in before)
    return False


def without_repo(words: list[str]) -> list[str]:
    """The words without gh's inherited `-R`/`--repo` and its value, which gh takes before, between
    or after the command's words, so `gh issue -R o/r comment 3` is `gh issue comment 3` (#773)."""
    kept, index = [], 0
    while index < len(words):
        word = words[index]
        if word == "--":
            return kept + words[index:]
        if word in {"-R", "--repo"}:
            index += 2
            continue
        if word.startswith("--repo=") or (word.startswith("-R") and not word.startswith("--")):
            index += 1
            continue
        kept.append(word)
        index += 1
    return kept


def match(words: list[str], rows: list[dict]) -> dict | None:
    if not words or Path(words[0]).name != "gh":
        return None
    rest = without_repo(words[1:])
    if asks_for_help(rest):
        return None
    if rest[:1] == ["api"]:
        return api_write(rest[1:], rows)
    for row in rows:
        size = len(row["words"])
        if rest[:size] != row["words"]:
            continue
        if row["flags"] and not any(
            fnmatch.fnmatchcase(word, glob) for word in rest[size:] for glob in row["flags"]
        ):
            continue
        return row
    return None


def moved(folder: str | None, words: list[str]) -> str | None:
    """The folder after a typed `cd`, `pushd` or `popd` (#816); None when it cannot be told.

    shortcut: a `cd` inside a subshell is followed as if it were not, and a nested `bash -c` body
    is judged from the last folder; track the shell's structure if that hides a real search.
    """
    targets = [word for word in words[1:] if word not in {"-P", "-L", "-e", "-@", "--"}]
    if folder is None or words[0] == "popd" or len(targets) != 1 or targets[0] == "-":
        return None
    return str(Path(folder, Path(targets[0]).expanduser()))


def recursive_grep(words: list[str], cwd: str | None = ".") -> bool:
    """Whether the command is a recursive `grep`, which reads every ignored folder (#686).

    One that names only existing regular files reads nothing more than a plain `grep`, so it is not
    counted (#773); no path, a directory, a link to one, a missing path or a folder the guard could
    not follow after a `cd` (None) keeps it counted (#816).
    """
    if not words or Path(words[0]).name not in GREP:
        return False
    recursive, pattern_given, found = False, False, []
    index = 1
    while index < len(words):
        word = words[index]
        if word == "--":
            found += words[index + 1:]
            break
        if not word.startswith("-") or word == "-":
            found.append(word)  # an operand: GNU grep still reads options after it
            index += 1
            continue
        if word.startswith("--"):
            option = word.partition("=")[0]
            if word in GREP_RECURSIVE or (word == "--directories" and words[index + 1:index + 2] == ["recurse"]):
                recursive = True
            if option in {"--regexp", "--file"}:
                pattern_given = True
            index += 2 if word in GREP_LONG_VALUE else 1
            continue
        for position, letter in enumerate(word[1:], 1):
            if letter in "rR":
                recursive = True
            if letter in GREP_VALUE:
                value = word[position + 1:]
                if not value:
                    index += 1
                    value = words[index] if index < len(words) else ""
                if letter == "d" and value == "recurse":
                    recursive = True
                if letter in "ef":
                    pattern_given = True
                break
        index += 1
    if not recursive:
        return False
    paths = found if pattern_given else found[1:]
    return cwd is None or not paths or not all(plain_file(path, cwd) for path in paths)


def plain_file(path: str, cwd: str) -> bool:
    """Whether `path` is an existing regular file, a link to a directory not included.

    The guard sees a glob such as `tests/*.sh` before the shell expands it, so a glob counts when it
    matches at least one path and every match is a regular file (#773).
    """
    try:
        if GLOB.search(path):
            matches = glob.glob(str(Path(cwd, path).expanduser()), recursive=True)
            return bool(matches) and all(Path(match).is_file() for match in matches)
        return Path(cwd, path).expanduser().is_file()
    except OSError:
        return False


def git_command(words: list[str]) -> tuple[str, list[str], bool]:
    """A `git` command's subcommand, the words after it, and whether a `-c core.hooksPath=` before
    it skips the hooks; ("", [], False) for any other program."""
    if not words or Path(words[0]).name != "git":
        return "", [], False
    index, hooks_path = 1, False
    while index < len(words) and words[index].startswith("-"):
        word = words[index]
        option, equals, value = word.partition("=")
        if option in GIT_VALUE and not equals:
            index += 1
            value = words[index] if index < len(words) else ""
        elif word.startswith("-c") and len(word) > 2:
            option, value = "-c", word[2:]
        if option in {"-c", "--config-env"} and value.partition("=")[0].lower() == "core.hookspath":
            hooks_path = True
        index += 1
    if index >= len(words):
        return "", [], hooks_path
    return words[index], words[index + 1:], hooks_path


def is_long_prefix(word: str, option: str, shortest: str) -> bool:
    """Whether `word` (before any `=`) is `option` or a prefix of it at least `shortest` long, as
    git's option parser accepts an unambiguous abbreviation."""
    name = word.partition("=")[0]
    return name.startswith(shortest) and option.startswith(name)


def force_push(words: list[str], cwd: str = ".") -> bool:
    """Whether a `git push` rewrites the remote branch (#773): `-f` (also in a short cluster),
    `--force`, `--force-with-lease` or a prefix of it from `--force-`, `--mirror` or a prefix of it,
    or a refspec that starts with `+`; with no refspec typed, a mirror remote or a `+` push refspec
    in its config, typed with `-c` or stored (#815). A push with `--delete` or `-d` removes a branch
    instead and is not counted."""
    command, rest, _ = git_command(words)
    if command != "push":
        return False
    forced, deleting, operands, index = False, False, [], 0
    while index < len(rest):
        word = rest[index]
        if word == "--":
            operands += rest[index + 1:]
            break
        if word.startswith("--"):
            name = word.partition("=")[0]
            if (name == "--force" or is_long_prefix(word, "--force-with-lease", "--force-")
                    or is_long_prefix(word, "--mirror", "--m")):
                forced = True
            elif name == "--delete":
                deleting = True
            elif name in {"--repo", "--receive-pack", "--exec", "--push-option"} and "=" not in word:
                index += 1
        elif word.startswith("-") and word != "-":
            for position, letter in enumerate(word[1:], 1):
                if letter == "f":
                    forced = True
                elif letter == "d":
                    deleting = True
                elif letter == "o":
                    if position == len(word) - 1:
                        index += 1  # the push option is the next word
                    break
        else:
            operands.append(word)
        index += 1
    forced = forced or any(refspec.startswith("+") for refspec in operands[1:])
    if not forced and not deleting and len(operands) <= 1:
        forced = mirror_config(words[1:len(words) - len(rest) - 1], operands[:1], cwd)
    return forced and not deleting


def mirror_config(options: list[str], remote: list[str], cwd: str) -> bool:
    """Whether the remote a push without a refspec uses is a mirror or has a `+` push refspec (#815).

    git reads it with the typed command's own global options, so `-c remote.origin.mirror=true`,
    `-C app` and a stored mirror remote all count. shortcut: with no remote named any remote counts,
    since git picks the default through several settings; resolve it when that refuses a real push.
    """
    name = re.escape(remote[0]) if remote else "[^.]+"
    try:
        found = subprocess.run(
            ["git", *options, "config", "--get-regexp", rf"^remote\.{name}\.(mirror|push)$"],
            cwd=cwd if os.path.isdir(cwd) else "/", capture_output=True, text=True, timeout=GIT_SECONDS,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    mirrors: dict[str, bool] = {}  # the last value wins, as `-c` overrides a stored one
    for line in found.stdout.splitlines():
        key, _, value = line.partition(" ")
        value = value.strip()
        if key.endswith(".mirror"):
            mirrors[key] = value.lower() in {"", "true", "yes", "on", "1"}
        elif value.startswith("+"):
            return True
    return any(mirrors.values())


def sets_hooks_path(command: str, rest: list[str]) -> bool:
    """Whether `git config` writes `core.hooksPath` (#1283): set, unset, add or replace it, in any
    scope. A read (`--get`, `--list`, `get`, or the key with no value) passes."""
    if command != "config":
        return False
    keys = [index for index, word in enumerate(rest) if word.lower() == "core.hookspath"]
    if not keys:
        return False
    options = {word.partition("=")[0] for word in rest if word.startswith("-")}
    verbs = [word for word in rest if not word.startswith("-")]
    if options & CONFIG_WRITES or (verbs and verbs[0] in {"set", "unset"}):
        return True
    if options & CONFIG_READS or (verbs and verbs[0] in {"get", "list"}):
        return False
    after = rest[keys[0] + 1:]
    return any(not word.startswith("-") for word in after)  # `git config core.hooksPath VALUE`


def hooks_env(assignments: dict, rest: list[str]) -> bool:
    """Whether a typed command sets `core.hooksPath` through Git's environment (#1283):
    `GIT_CONFIG_KEY_<n>=core.hooksPath` or `GIT_CONFIG_PARAMETERS` naming it, before a command or
    after `export`, `declare` or `typeset`."""
    pairs = dict(assignments)
    if rest and rest[0] in {"export", "declare", "typeset", "local", "readonly"}:
        pairs.update(word.partition("=")[::2] for word in rest[1:] if "=" in word)
    return any(
        (re.fullmatch(r"GIT_CONFIG_KEY_\d+", name) and value.strip().lower() == "core.hookspath")
        or (name == "GIT_CONFIG_PARAMETERS" and "core.hookspath" in value.lower())
        for name, value in pairs.items()
    )


def skips_hooks(words: list[str]) -> bool:
    """Whether a `git` command skips the commit and push hooks (#685).

    `git commit --no-verify` or `-n` (also inside a short cluster such as `-nm`), `git push
    --no-verify`, a `core.hooksPath` set on the command line with `-c` or `--config-env` for any
    subcommand, and a `git config` that writes it (#1283).
    """
    command, rest, hooks_path = git_command(words)
    if hooks_path or sets_hooks_path(command, rest):
        return True
    if command not in {"commit", "push"}:
        return False
    position = 0
    while position < len(rest):
        word = rest[position]
        if word == "--":
            return False
        if is_long_prefix(word, "--no-verify", "--no-v"):
            return True  # git takes any unambiguous prefix of a long option (#773)
        if command == "commit" and word.startswith("-") and not word.startswith("--"):
            for offset, letter in enumerate(word[1:], 1):
                if letter == "n":
                    return True
                if letter in COMMIT_VALUE:
                    if offset == len(word) - 1 and letter != "S":
                        position += 1  # the value is the next word
                    break
        position += 1
    return False


def merges(words: list[str]) -> bool:
    """Whether a typed command merges a pull request: `gh pr merge`, also with gh's inherited
    `-R`/`--repo` anywhere, and not a help request (#773).

    A `gh api` write on `pulls/N/merge` is refused the same way, through `api_write` (#1211).
    """
    if not words or Path(words[0]).name != "gh":
        return False
    rest = without_repo(words[1:])
    return rest[:2] == ["pr", "merge"] and not asks_for_help(rest)


# `gh pr merge` options that take the next word as their value.
MERGE_VALUE = {"-b", "--body", "-F", "--body-file", "-t", "--subject", "--match-head-commit", "-A", "--author-email"}
PULL_URL = re.compile(r"^https://github\.com/([^/]+/[^/]+)/pull/(\d+)/?$")


def merge_target(words: list[str]) -> tuple[str | None, str | None, set[str]]:
    """The `-R`/`--repo` value, the pull request (number or URL) and the flags of a `gh pr merge`."""
    repo, target, flags, index = None, None, set(), 1
    while index < len(words):
        word = words[index]
        if word in {"-R", "--repo"} and index + 1 < len(words):
            repo, index = words[index + 1], index + 2
            continue
        if word.startswith("--repo="):
            repo = word.split("=", 1)[1]
        elif word.startswith("-R") and not word.startswith("--") and len(word) > 2:
            repo = word[2:]
        elif word in MERGE_VALUE:
            index += 1
        elif word.startswith("-"):
            flags.add(word.split("=", 1)[0])
        elif word not in {"pr", "merge"} and target is None:
            target = word
        index += 1
    return repo, target, flags


def cloud_dependabot_merge(words: list[str], folder: str | None) -> bool:
    """Whether a typed `gh pr merge` is one a cloud session may run: owner decision D146 B (#953).

    Only in a Claude Code cloud session, only by a merge commit (`--merge`, the recorded method) and
    never `--admin` or `--auto`, and only for a pull request `bench-cleanup`'s `unattended.py`
    would merge there: opened by Dependabot, every check run of its head green, only manifests and
    lockfiles changed, a major bump included. Every GitHub read that fails refuses (fail closed)."""
    conventions = SKILLS / "bench-github-publishing" / "scripts"
    sys.path[:0] = [str(conventions), str(SKILLS / "bench-cleanup" / "scripts")]
    try:
        import session_env  # noqa: PLC0415  the one reader of the session's environment (#1223)
    except ImportError:
        return False
    if not session_env.is_cloud():
        return False
    repo, target, flags = merge_target(words)
    if "--merge" not in flags or flags & {"--admin", "--auto", "--squash", "--rebase", "-s", "-r", "-d", "--delete-branch"}:
        return False
    found = PULL_URL.match(target or "")
    if found:
        repo, target = found.group(1), found.group(2)
    if not (target or "").isdigit():
        return False
    try:
        import gh_rest  # noqa: PLC0415  only a cloud merge reads GitHub
        import github_port  # noqa: PLC0415
        import unattended  # noqa: PLC0415  the one Dependabot merge rule (#1099, #953)
        repo = repo or github_port.origin_repo(folder or os.getcwd())
        rest = gh_rest.Rest(gh_rest.default_runner, cache=False)
        pull = rest.call("GET", f"repos/{repo}/pulls/{target}")
        if (pull.get("user") or {}).get("login") != unattended.BOT or pull.get("state") != "open":
            return False
        return unattended.pull_verdict(rest, repo, pull, major=True) == ""
    except Exception:  # noqa: BLE001  a hook never lets a failed read pass a merge
        return False


def process_options(words: list[str]) -> tuple[bool, list[str]]:
    """Whether a `pgrep` or `pkill` matches the full command line (`-f` in any cluster, `--full`),
    and its operands, the patterns (#1344). pkill's `-SIGNAL` word is one token that takes no next word."""
    full, found, index = False, [], 1
    while index < len(words):
        word = words[index]
        if word == "--":
            found += words[index + 1:]
            break
        if word.startswith("--"):
            name, equals, _ = word.partition("=")
            full = full or name == "--full"
            index += 2 if name in PGREP_LONG_VALUE and not equals else 1
            continue
        if word.startswith("-") and word != "-":
            if Path(words[0]).name == "pkill" and word[1:] in SIGNAL_WORDS:
                index += 1
                continue
            for position, letter in enumerate(word[1:], 1):
                if letter == "f":
                    full = True
                if letter in PGREP_VALUE:
                    if position == len(word) - 1:
                        index += 1  # the value is the next word
                    break
            index += 1
            continue
        found.append(word)
        index += 1
    return full, found


def by_name(words: list[str]) -> bool:
    """Whether a typed command finds processes by name (#747, #1344): `pgrep -f`, `pkill` with a
    pattern or `-f`, or `killall` with anything but `-l`. A selection by PID (`-P PID`) passes."""
    if not words:
        return False
    name = Path(words[0]).name
    if name == "killall":
        return words[1:] != ["-l"]
    if name not in {"pgrep", "pkill"}:
        return False
    full, patterns = process_options(words)
    return full or (name == "pkill" and bool(patterns))


def background_waiter(command: str) -> tuple[str, str] | None:
    """(the command shown, the bypass reason) when a background command only waits (#1344), else
    None. `waiters.py` is bench-backlog's definition, shared with `lane_watch.py`; when it cannot
    be loaded, nothing is refused, since the hook never fails on its own files."""
    try:
        sys.path.insert(0, str(WAITERS))
        import waiters
    except ImportError:
        return None
    finally:
        if sys.path and sys.path[0] == str(WAITERS):
            sys.path.pop(0)
    body, reason = command.strip(), ""
    while True:
        found = ASSIGNMENT.match(body)
        if not found:
            break
        if found[1] == BYPASS:
            reason = found[2].strip("\"'").strip()
        body = body[found.end():].lstrip()
    if not waiters.is_waiter(body):
        return None
    seconds = waiters.sleep_seconds(body)
    if seconds is not None and seconds <= SLEEP_FLOOR:
        return None
    return " ".join(body.split()), reason


def text_endpoint(endpoint: str, method: str | None, fields: set[str]) -> list[str] | None:
    """The map words for a repository description, release or gist write (#1289), else None."""
    if API_REPO.match(endpoint):
        # shortcut: a JSON `--input` body passes, as bench-setup's settings PATCH sends one; the
        # guard cannot read a heredoc's keys, so a description sent that way is not caught (#1289).
        return ["repo", "edit"] if "description" in fields else None
    release = API_RELEASE.match(endpoint)
    if release and method != "DELETE" and (release["rest"] is None or fields & {"body", "name", "--input"}):
        return ["release", "create"] if release["rest"] is None else ["release", "edit"]
    gist = API_GIST.match(endpoint)
    if gist and method != "DELETE":
        return ["gist", "create"] if gist["rest"] is None else ["gist", "edit"]
    return None


def api_write(words: list[str], rows: list[dict]) -> dict | None:
    """The map row that owns a `gh api` write to an issue, its comments or relations, or a pull
    request, its review comments, reviews or merge (#658, #1211), a repository description, a
    release or a gist (#1289), an Actions workflow, run, job or cache (#1980), else None.

    A write is `--method`/`-X` other than GET, or any field or `--input` without an explicit GET.
    Other endpoints, labels and repository settings included, pass; a pull request PATCH with no
    `body`, `title` or `--input` (a state or base change) passes too.
    """
    endpoint, method, fields, index = None, None, set(), 0
    while index < len(words):
        word = words[index]
        option, equals, value = word.partition("=")
        if option in API_VALUE:
            if not equals:
                index += 1
                value = words[index] if index < len(words) else ""
            if option in {"-X", "--method"}:
                method = value.upper()
            elif option == "--input":
                fields.add("--input")
            elif option in API_FIELDS:
                fields.add(value.partition("=")[0])
        elif word.startswith("-X") and len(word) > 2:
            method = word[2:].upper()
        elif not word.startswith("-") and endpoint is None:
            endpoint = word
        index += 1
    if method == "GET" or (method is None and not fields):
        return None
    endpoint = (endpoint or "").partition("?")[0]
    wanted = text_endpoint(endpoint, method, fields)
    if wanted:
        return next((row for row in rows if row["words"] == wanted), None)
    if API_ACTIONS.match(endpoint):
        return next((row for row in rows if row["words"] == ["workflow", "run"]), None)
    if API_RELATION.match(endpoint):
        return next((row for row in rows if row["words"] == ["issue", "edit"] and "--add-sub-issue*" in row["flags"]), None)
    pull = API_PULL.match(endpoint)
    if pull:
        tail = pull["rest"] or ""
        if tail.endswith("/merge"):
            return MERGE
        if tail.endswith("/reviews"):
            wanted = ["pr", "review"]
        elif "/comments" in tail:
            wanted = ["pr", "reply"]
        elif tail == "":
            wanted = ["pr", "create"]
        elif fields & {"body", "title", "--input"}:
            wanted = ["pr", "edit"]
        else:
            return None
        return next((row for row in rows if row["words"] == wanted), None)
    found = API_ISSUE.match(endpoint)
    if not found:
        return None
    tail = found["rest"] or ""
    if tail == "":
        wanted = ["issue", "create"]
    elif tail.endswith("/comments") or "/comments/" in tail:
        wanted = ["issue", "comment"]
    elif "state" in fields:
        wanted = ["issue", "close"]
    elif fields & {"body", "title", "--input"}:
        wanted = ["issue", "edit"]
    else:
        return None
    return next((row for row in rows if row["words"] == wanted), None)


def brace_form(text: str, start: int) -> tuple[str | None, int]:
    """The prompting form of the `${...}` opening at `start`, else None, and where it closes (#1405):
    a zsh flag (`${(f)x}`, `${=x}`), or a `$(`, `${` or backtick inside it."""
    form = "zsh flag" if text[start + 2:][:1] in ZSH_FLAG else None
    depth, index = 1, start + 2
    while index < len(text) and depth:
        char = text[index]
        if char == "\\":
            index += 2
            continue
        if form is None and (char == "`" or (char == "$" and text[index + 1:index + 2] in {"(", "{"})):
            form = "nested"
        depth += {"{": 1, "}": -1}.get(char, 0)
        index += 1
    return form, index


def expansion_forms(text: str, body: bool = False) -> list[tuple[str, str]]:
    """(form, the text shown) for each prompting expansion outside single quotes (#1405).

    `body` reads a here-document body, where quotes are plain characters and every expansion runs.
    A `#` that starts a word comments out the rest of the line.
    """
    found, index, quote = [], 0, ""
    while index < len(text):
        char = text[index]
        if char == "\\":
            index += 2
            continue
        if not body and char == "'" and not quote:
            # In `$'...'` (ANSI-C quoting) a backslash escapes the next character, `\'` included (#1419).
            end, ansi = index + 1, text[index - 1:index] == "$"
            while end < len(text) and text[end] != "'":
                end += 2 if ansi and text[end] == "\\" else 1
            index = end + 1
            continue
        if not body and char == '"':
            quote = "" if quote else '"'
        elif not body and char == "#" and not quote and (index == 0 or text[index - 1] in " \t\n;&|("):
            end = text.find("\n", index)
            index = len(text) if end < 0 else end
            continue
        elif char == "`":
            end = text.find("`", index + 1)
            found.append(("backtick", text[index:end + 1 if end >= 0 else len(text)]))
            index = len(text) if end < 0 else end + 1
            continue
        elif char == "$" and text[index + 1:index + 2] == "{":
            form, end = brace_form(text, index)
            if form:
                found.append((form, text[index:end]))
        elif char == "$" and ZSH_SPLIT.match(text, index):
            found.append(("zsh flag", ZSH_SPLIT.match(text, index).group()))
        index += 1
    return found


LEADING_BYPASS = re.compile(r"""\s*(?:[A-Za-z_]\w*=(?:"[^"]*"|'[^']*'|\S*)\s+)*?%s=("[^"]*"|'[^']*'|\S*)""" % BYPASS)


def segments(text: str) -> list[str]:
    """The top-level simple commands of `text`, split at `;`, `&`, `|` and newlines outside quotes,
    backticks and `$(...)` or `${...}`, so a form is judged with the command that holds it (#1415)."""
    found, start, index, quote, depth = [], 0, 0, "", 0
    while index < len(text):
        char = text[index]
        if char == "\\" and quote != "'":
            index += 2
            continue
        if quote:
            quote = "" if char == quote else quote
        elif char in "'\"`":
            quote = char
        elif char == "$" and text[index + 1:index + 2] in {"(", "{"}:
            depth += 1
            index += 2
            continue
        elif depth and char in ")}":
            depth -= 1
        elif not depth and char in ";&|\n":
            found.append(text[start:index])
            start = index + 1
        index += 1
    return [part for part in found + [text[start:]] if part.strip()]


def segment_bypass(segment: str) -> str:
    """The `SKD_ALLOW_RAW` reason among the segment's own leading assignments, else ""."""
    found = LEADING_BYPASS.match(segment)
    return found.group(1).strip("\"'").strip() if found else ""


def prompt_forms(command: str, typed: list[list[str]]) -> list[tuple[str, str, str]]:
    """(form, the text shown, the bypass reason or "") for each shell form Claude Code's parser asks
    about (#1405): zsh flags and word splits, a command or expansion inside `${...}`, backticks,
    `eval`, and `rm` with a variable or a glob. Here-documents with a quoted delimiter are data and
    are skipped; an unquoted one's body expands, so it is read too. A reason counts only on the
    simple command that holds the form (#1415); a body's forms need it on every command."""
    kept, bodies, ending = [], [], []
    for line in command.split("\n"):
        if ending:
            if line.strip() == ending[0][1]:
                ending.pop(0)
            elif not ending[0][0]:
                bodies.append(line)
            continue
        kept.append(line)
        ending = [(found.group(1), found.group(2)) for found in HEREDOC.finditer(line)]
    parts = segments("\n".join(kept))
    reasons = [segment_bypass(part) for part in parts]
    found = [(form, shown, reason) for part, reason in zip(parts, reasons) for form, shown in expansion_forms(part)]
    everywhere = reasons[0] if reasons and all(reasons) else ""
    found += [(form, shown, everywhere) for form, shown in expansion_forms("\n".join(bodies), body=True)]
    for words in typed:
        assignments, rest = strip_prefix(words)
        reason = assignments.get(BYPASS, "").strip()
        if rest and rest[0] == "eval":
            found.append(("eval", " ".join(rest), reason))
        elif rest and Path(rest[0]).name == "rm" and any("$" in word or GLOB.search(word) for word in rest[1:]):
            found.append(("rm", " ".join(rest), reason))
    return found


def verdict(command: str, rows: list[dict], cwd: str | None = None,
            background: bool = False) -> tuple[list[tuple[str, dict]], list[tuple[str, str, str]]]:
    """The refused simple commands with their rows, and the bypassed ones with their reasons and,
    for a rule no script owns, the rule's name. `background` is a command run in the background,
    judged whole for a waiter (#1344)."""
    refused, bypassed = [], []
    waited = background_waiter(command) if background else None
    if waited and waited[1]:
        bypassed.append((waited[0], waited[1], OWNER_RULES[id(WAITER)]))
    elif waited:
        refused.append((waited[0], WAITER))
    typed = simple_commands(command)
    for form, shown, reason in prompt_forms(command, typed):
        if reason:
            bypassed.append((shown, reason, OWNER_RULES[id(PROMPT_FORMS[form])]))
        else:
            refused.append((shown, PROMPT_FORMS[form]))
    folder: str | None = cwd or os.getcwd()
    programs = written_programs(command, folder)
    for index, words in enumerate(typed + programs):
        assignments, rest = strip_prefix(words)
        if index < len(typed) and rest and rest[0] in FOLDER_CHANGES:
            folder = moved(folder, rest)
            continue
        row = match(rest, rows)
        if row is None and index < len(typed) and recursive_grep(rest, folder):
            row = SEARCH  # only the typed command: a script's own `grep -r` still runs
        if row is None and index < len(typed) and (skips_hooks(rest) or hooks_env(assignments, rest)):
            row = HOOKS
        if row is None and index < len(typed) and force_push(rest, folder or cwd or os.getcwd()):
            row = FORCE
        if row is None and index < len(typed) and merges(rest) \
                and not cloud_dependabot_merge(rest, folder or cwd):
            row = MERGE
        if row is None and index < len(typed) and by_name(rest):
            row = PROCESS
        if row is None:
            continue
        shown = " ".join(shlex.quote(word) for word in rest)
        reason = assignments.get(BYPASS, "").strip()
        if reason:
            bypassed.append((shown, reason, OWNER_RULES.get(id(row), "")))
        else:
            refused.append((shown, row))
    return refused, bypassed


def log_bypasses(bypassed: list[tuple[str, str, str]], cwd: str) -> None:
    path = LOG
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as handle:
            for shown, reason, rule in bypassed:
                fields = [stamp, cwd, reason, shown] + ([rule] if rule else [])
                handle.write("\t".join(" ".join(field.split()) for field in fields) + "\n")
    except OSError as error:
        hook_error(__file__, f"could not log the bypass in {path}: {error}\n")


def refusal(refused: list[tuple[str, dict]]) -> str:
    lines = []
    for shown, row in refused:
        if row is HOOKS:
            lines += [
                f"Refused: `{shown}` skips the pre-commit and commit-msg hooks, the secret scan and the"
                " commit-message rules included (#685).",
                f"  instead: {row['usage']}",
            ]
            continue
        if row is FORCE:
            lines += [
                f"Refused: `{shown}` rewrites the remote branch's history (#773).",
                f"  instead: {row['usage']}",
            ]
            continue
        if row is MERGE:
            lines += [
                f"Refused: `{shown}` merges a pull request, which only the merge rule's cases allow (#773).",
                f"  instead: {row['usage']}",
            ]
            continue
        if row is PROCESS:
            lines += [
                f"Refused: `{shown}` finds processes by name, which can match another lane's process or"
                " your own shell (#747, #1344).",
                f"  instead: {row['usage']}",
            ]
            continue
        if row is WAITER:
            lines += [
                f"Refused: `{shown}` runs in the background only to wait, which holds a task slot and the"
                " run's end open (#876, #1344).",
                f"  instead: {row['usage']}",
            ]
            continue
        if any(row is form for form in PROMPT_FORMS.values()):
            lines += [
                f"Refused: `{shown}` is {row['what']}, which Claude Code's parser cannot read: it asks for a"
                " confirmation even in bypass mode, and an unattended run waits on it (#1405).",
                f"  instead: {row['usage']}",
            ]
            continue
        if row is SEARCH:
            lines += [
                f"Refused: `{shown}` searches recursively and reads ignored build folders"
                " (`.build`, `node_modules`, `.scratch`), which takes minutes.",
                f"  instead: {row['usage']}",
            ]
            continue
        lines += [
            f"Refused: `{shown}` is a step a Skill Deck script owns; run the script instead.",
            f"  script: {script_path(row['script'])}",
            f"  usage:  {row['usage']}",
        ]
    if all(row is PROCESS or row is WAITER or OWNER_RULES.get(id(row)) == "prompting shell form"
           for _, row in refused):
        return "\n".join(lines + [
            "If only this form can do it, ask the owner; on a yes, rerun that exact command as",
            f'`{BYPASS}="<reason>" <command>`, the reason naming who approved it.',
        ]) + "\n"
    if all(id(row) in OWNER_RULES for _, row in refused):
        return "\n".join(lines + [
            "Only the owner may approve this, or for a merge the merge rule's level-high exception; then rerun",
            f'that exact command as `{BYPASS}="<reason>" <command>`, the reason naming who approved it.',
        ]) + "\n"
    if all(row is SEARCH for _, row in refused):
        return "\n".join(lines + [
            "Search with `rg` instead. If only `grep -r` can do it, ask the owner; on a yes, rerun it as",
            f'`{BYPASS}="<reason>" <command>`.',
        ]) + "\n"
    lines += [
        "If the script cannot do this step, ask the owner. On a yes, rerun only that command as",
        f'`{BYPASS}="<reason>" <command>`; the bypass is logged for an issue that extends the script.',
        "If the script itself fails or refuses a legitimate case, report it in martonpaulo/workbench and",
        "ask: fix it there now, work around it, or both (bench-github-publishing, section 15).",
    ]
    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    action = argv[1] if len(argv) > 1 else ""
    try:
        rows = load_map()
    except (OSError, ValueError) as error:
        unreadable(__file__, MAP, error)
        return 0 if action == "check" else 1
    background = False
    if action == "scan" and len(argv) == 3:
        command, cwd = argv[2], os.getcwd()
    elif action == "check" and len(argv) == 2:
        try:
            payload = json.loads(sys.stdin.read() or "{}")
        except ValueError:
            return 0
        if not isinstance(payload, dict):
            return 0
        tool_name = payload.get("tool_name", "Bash")
        if isinstance(tool_name, str) and tool_name.startswith("mcp__"):
            try:
                row = github_write(tool_name, load_github_tools())
            except (OSError, ValueError) as error:
                unreadable(__file__, GITHUB_TOOLS, error)
                return 0
            if row is None:
                return 0
            return refuse(mcp_refusal(tool_name, row))
        if tool_name != "Bash":
            return 0
        tool_input = payload.get("tool_input")
        command = tool_input.get("command") if isinstance(tool_input, dict) else None
        if not isinstance(command, str):
            return 0
        cwd = str(payload.get("cwd") or os.getcwd())
        background = tool_input.get("run_in_background") is True
    else:
        sys.stderr.write("usage: raw_command_guard.py check | scan COMMAND\n")
        return 1
    refused, bypassed = verdict(command, rows, cwd, background)
    if refused:
        return refuse(refusal(refused))
    if bypassed:
        log_bypasses(bypassed, cwd)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
