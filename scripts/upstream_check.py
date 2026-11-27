#!/usr/bin/env python3
"""Check every pinned upstream source in upstreams.json, read-only (#719).

  upstream_check.py validate [--manifest upstreams.json]
  upstream_check.py check [--manifest upstreams.json] [--json] [--output FILE]
  upstream_check.py sync --repo OWNER/NAME (--report FILE | --discover FILE) [--dry-run]
  upstream_check.py alert --repo OWNER/NAME --workflow NAME --run-url URL --results FILE|- [--sha SHA] [--bisect LINE]

A Skill Deck baseline asset: a repository copies it unchanged to `scripts/upstream_check.py`. The
manifest format, the statuses and the workflow that runs it are in bench-setup's
`references/upstream-check.md`. Python standard library and Git only.

`validate` exits 0 for a valid manifest and 1 with one line per error. `check` reports each source
as `moved`, `unchanged` or `unavailable`, and a source the manifest marks `retired` as `retired`
with its reason, reading nothing upstream (#1970); it exits 0, 1 when a source is unavailable, and 2 when the
manifest is invalid. Nothing here writes to the repository or to any upstream.

`sync` turns a report into issues through `gh`: one open issue per moved source, found by the marker
on its body's first line, created when missing, edited only when its text changed, and closed once
the source is unchanged, retired or gone. A created or edited issue carries `type: maintenance` and
`priority: P3` when the repository has them, and its body holds `## Specify` and `## Clarify`
(#807). It also gets a pre-plan size from its commit count, the `effort:` label and the body's
`Estimate before planning:` line, so a fastest-first backlog run can order it (#808). `--discover` reads Skill Deck's `discover.py --json` instead of a
`check` report. With `--runs-rule` (Skill Deck's `runs_rule.py`, the rule `cloud_ready.py` and
`publish.py issue` share) each created or edited issue also gets `runs: cloud` or `runs: mac` from its
body's verdict over the current checkout, when the repository has the label (#1659). It exits 1, after syncing, when a source is unavailable.

`alert` reads the workflow's `toJSON(needs)` and keeps one issue for the workflow itself (#1234),
found by `<!-- workflow-alert: NAME -->` on its first line: a job that failed or was cancelled
creates it, or edits it and comments the new run; every job a success closes it. Each comment opens
with `<!-- skd-workflow-alert -->`, so no reader takes it for a person's (#2133). The workflow's last
job runs it on a scheduled run, whatever the other jobs did, so a run cut at its timeout still
reaches the owner. `--bisect` is a red run's `ci_bisect:` line (Skill Deck's `scripts/ci_bisect.py`),
which the red-main issue quotes under Current behavior (#1715). `--failed` is a red run's failed
suites, one per line (Skill Deck's `failure_lines.py suites`), each named in that issue (#1710).

Exit: 0 every source checked, 1 an invalid manifest or an unavailable source, 2 a usage error.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlsplit

MANIFEST = "upstreams.json"
XS_COMMITS = 2  # upstream commits at most for an XS issue
S_COMMITS = 20  # upstream commits at most for an S issue
MESSAGE_SHA = 7  # characters of a commit shown in a message
GITHUB_PREFIX = "https://github.com/"
LABELS = ("type: maintenance", "priority: P3")
EFFORTS = ("XS", "S", "M", "L", "XL")
# The `runs:` label each verdict of Skill Deck's runs_rule.py gives; `handoff` and `unknown` give none (#1659).
RUNS = {"cloud": "runs: cloud", "mac": "runs: mac"}


def effort(result: dict) -> str:
    """The pre-plan size a fastest-first backlog run orders by (#808): reading and deciding a small
    move is quick, a long one is not. shortcut: commit count only; upgrade to the diff size if a
    one-commit rewrite turns out slow to review."""
    count = result["count"]
    return "XS" if count <= XS_COMMITS else "S" if count <= S_COMMITS else "M"
FIELDS = ("id", "repo", "ref", "commit", "upstreamPaths", "localPaths", "patches", "licence")
OPTIONAL_FIELDS = ("reviewed", "retired")
SHA_FIELDS = ("commit", "reviewed")
# Why a project no longer follows a source: one line, so it fits the report and the closing comment (#1970).
RETIRED = re.compile(r"\S[^\n]*")
FULL_SHA = re.compile(r"[0-9a-f]{40}")
SOURCE_ID = re.compile(r"[a-z0-9][a-z0-9.-]*")
# A glob is allowed only for tags, where it picks the highest version; a branch is one name.
REF = re.compile(r"refs/heads/[^*?\[\s]+|refs/tags/[^\s]+")
SPDX = re.compile(r"[A-Za-z0-9.+-]+(?:\s+(?:AND|OR|WITH)\s+[A-Za-z0-9.+-]+)*")
COMMIT_SAMPLE = 20
GIT_TIMEOUT = 600


class ManifestError(Exception):
    """The manifest cannot be read or breaks the schema; the message lists every problem."""


def _path_errors(where: str, value: object, *, allow_dot: bool) -> list[str]:
    if not isinstance(value, list) or not value:
        return [f"{where}: a non-empty list of relative paths"]
    errors = []
    for path in value:
        if not isinstance(path, str) or not path.strip():
            errors.append(f"{where}: every path is a non-empty string")
        elif path.startswith("/") or ".." in Path(path).parts:
            errors.append(f"{where}: {path!r} must be relative, without '..'")
        elif path == "." and not allow_dot:
            errors.append(f"{where}: '.' is allowed only for the upstream side")
    return errors


def validate_source(index: int, source: object) -> list[str]:
    if not isinstance(source, dict):
        return [f"sources[{index}]: an object"]
    where = f"sources[{index}]" + (f" ({source['id']})" if isinstance(source.get("id"), str) else "")
    errors = [f"{where}: missing {name}" for name in FIELDS if name not in source]
    errors += [
        f"{where}: unknown key {name!r}" for name in source if name not in FIELDS + OPTIONAL_FIELDS
    ]
    if "id" in source and not (isinstance(source["id"], str) and SOURCE_ID.fullmatch(source["id"])):
        errors.append(f"{where}: id must match {SOURCE_ID.pattern}")
    if "repo" in source:
        repo = source["repo"]
        parts = urlsplit(repo) if isinstance(repo, str) else None
        if parts is None or parts.scheme not in {"https", "file"} or not (parts.netloc or parts.path):
            errors.append(f"{where}: repo must be an https:// or file:// Git URL")
        elif "@" in parts.netloc:
            errors.append(f"{where}: repo must not carry a user or password")
    if "ref" in source and not (isinstance(source["ref"], str) and REF.fullmatch(source["ref"])):
        errors.append(f"{where}: ref must be refs/heads/<branch> or refs/tags/<tag or glob>")
    for name in SHA_FIELDS:
        if name in source and not (isinstance(source[name], str) and FULL_SHA.fullmatch(source[name])):
            errors.append(f"{where}: {name} must be a full 40-character lowercase commit SHA")
    if "upstreamPaths" in source:
        errors += _path_errors(f"{where}: upstreamPaths", source["upstreamPaths"], allow_dot=True)
    if "localPaths" in source:
        errors += _path_errors(f"{where}: localPaths", source["localPaths"], allow_dot=False)
    if "patches" in source and source["patches"] is not None:
        errors += _path_errors(f"{where}: patches", [source["patches"]], allow_dot=False)
    if "retired" in source and not (isinstance(source["retired"], str) and RETIRED.fullmatch(source["retired"])):
        errors.append(f"{where}: retired must be one line saying why the source is no longer followed")
    if "licence" in source and not (isinstance(source["licence"], str) and SPDX.fullmatch(source["licence"])):
        errors.append(f"{where}: licence must be an SPDX identifier or expression")
    return errors


def validate_manifest(data: object) -> list[str]:
    if not isinstance(data, dict) or set(data) != {"sources"}:
        return ["the manifest is an object with exactly one key, sources"]
    sources = data["sources"]
    if not isinstance(sources, list):
        return ["sources: a list"]
    errors = []
    for index, source in enumerate(sources):
        errors += validate_source(index, source)
    ids = [source.get("id") for source in sources if isinstance(source, dict)]
    errors += [f"id {name!r} appears more than once" for name in sorted({i for i in ids if ids.count(i) > 1})]
    return errors


def load_manifest(path: Path) -> list[dict]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise ManifestError(f"{path}: not found") from None
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ManifestError(f"{path}: {error}") from None
    errors = validate_manifest(data)
    if errors:
        raise ManifestError("\n".join(f"{path}: {error}" for error in errors))
    return data["sources"]


class Unavailable(Exception):
    """One source cannot be compared; the message says why."""


def _git(*args: str, cwd: Path | None = None) -> str:
    # Never prompt for credentials: a private or missing upstream is unavailable, not a hang.
    env = {**os.environ, "GIT_TERMINAL_PROMPT": "0"}
    try:
        result = subprocess.run(
            ["git", *args], cwd=cwd, env=env, capture_output=True, text=True, timeout=GIT_TIMEOUT
        )
    except subprocess.TimeoutExpired:
        raise Unavailable(f"git {_subcommand(args)} timed out after {GIT_TIMEOUT} s") from None
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines() if line.strip()]
        fatal = [line for line in lines if line.startswith(("fatal:", "error:"))]
        detail = (fatal or lines or [f"exit {result.returncode}"])[0]
        raise Unavailable(f"git {_subcommand(args)} failed: {detail}")
    return result.stdout


def _subcommand(args: tuple[str, ...]) -> str:
    index = 0
    while index < len(args) and args[index] == "-c":
        index += 2
    return args[index] if index < len(args) else "git"


# A version number followed by `-` and more: `v5.0.0-beta.1`, `v1.10.0-rc1` (#1270).
PRERELEASE = re.compile(r"\d-[0-9A-Za-z]")


def resolve_ref(repo: str, ref: str) -> tuple[str, str]:
    """The watched ref's full name and commit. A tag glob resolves to its highest release, a tag
    with no pre-release suffix (#1270), and to the highest pre-release only when no release
    matches; `-rc1`-style suffixes sort below their release (`versionsort.suffix=-`)."""
    glob = any(character in ref for character in "*?[")
    args = ["-c", "versionsort.suffix=-", "ls-remote"]
    args += ["--tags", "--sort=-v:refname"] if glob else []
    lines = [line.split("\t", 1) for line in _git(*args, repo, ref).splitlines() if "\t" in line]
    names: list[str] = []
    commits: dict[str, str] = {}
    for sha, name in lines:
        base = name.removesuffix("^{}")
        if base not in commits:
            names.append(base)
        # An annotated tag lists the tag object, then the commit it points to as `^{}`.
        if name.endswith("^{}") or base not in commits:
            commits[base] = sha
    if glob:
        names = [name for name in names if name.startswith("refs/tags/")]
        names = [name for name in names if not PRERELEASE.search(name)] or names
    else:
        names = [name for name in names if name == ref]
    if not names:
        raise Unavailable(f"{ref} not found upstream")
    return names[0], commits[names[0]]


def compare(source: dict, workspace: Path) -> dict:
    base_name = "reviewed" if source.get("reviewed") else "commit"
    base = source[base_name]
    result = {
        "id": source["id"],
        "repo": source["repo"],
        "ref": source["ref"],
        "commit": source["commit"],
        "reviewed": source.get("reviewed"),
        "base": base_name,
        "upstreamPaths": source["upstreamPaths"],
        "localPaths": source["localPaths"],
        "patches": source["patches"],
        "licence": source["licence"],
    }
    if source.get("retired"):
        result.update({"status": "retired", "reason": source["retired"]})
        return result
    try:
        head_ref, head = resolve_ref(source["repo"], source["ref"])
        result.update({"headRef": head_ref, "head": head})
        if head in {source["commit"], source.get("reviewed")}:
            result.update({"status": "unchanged", "count": 0, "commits": []})
            return result
        mirror = workspace / source["id"]
        _git("init", "-q", "--bare", str(mirror))
        # shortcut: a blobless fetch still downloads every tree of the watched history; switch to a
        # since-pin shallow fetch when one source's run nears the workflow's timeout.
        _git("fetch", "-q", "--no-tags", "--filter=blob:none", source["repo"], f"+{head_ref}:refs/upstream/head", cwd=mirror)
        for name in ("commit", "reviewed"):
            if source.get(name):
                try:
                    _git("merge-base", "--is-ancestor", source[name], head, cwd=mirror)
                except Unavailable:
                    raise Unavailable(f"{name} {source[name][:MESSAGE_SHA]} is not in the history of {head_ref}") from None
        paths = [] if source["upstreamPaths"] == ["."] else ["--", *source["upstreamPaths"]]
        count = int(_git("rev-list", "--count", f"{base}..{head}", *paths, cwd=mirror).strip())
        log = _git("log", f"--max-count={COMMIT_SAMPLE}", "--format=%H%x09%cs%x09%s", f"{base}..{head}", *paths, cwd=mirror)
        commits = [dict(zip(("sha", "date", "subject"), line.split("\t", 2))) for line in log.splitlines() if line.count("\t") >= 2]
        result.update({"status": "moved" if count else "unchanged", "count": count, "commits": commits})
    except Unavailable as error:
        result.update({"status": "unavailable", "reason": str(error)})
    return result


def check(sources: list[dict]) -> list[dict]:
    with tempfile.TemporaryDirectory(prefix="upstream-check.") as temporary:
        return [compare(source, Path(temporary)) for source in sources]


MARKER = "<!-- upstream-check: {} -->"
MARKER_LINE = re.compile(r"\A<!-- upstream-check: (\S+) -->")
WORKFLOW = "Upstream check"


def from_discover(data: dict) -> list[dict]:
    """Skill Deck's `discover.py --json` report as `check` results: the primary source is named by
    its skill, another by `<skill>/<repository name>`."""
    statuses = {"changed": "moved", "unchanged": "unchanged", "removed": "unchanged"}
    results: list[dict] = []
    for skill in data.get("results", []):
        name = skill["skill"]
        if not skill.get("sources"):
            results.append({"id": name, "status": "unavailable", "reason": skill.get("reason", skill["status"])})
            continue
        for source in skill["sources"]:
            repository = source["repository"].rstrip("/").removesuffix(".git")
            identity = name if source.get("primary") else f"{name}/{repository.rsplit('/', 1)[-1]}"
            if any(result["id"] == identity for result in results):
                identity = f"{identity}:{source.get('path') or '.'}"
            paths = [path for path in (source.get("path"), *source.get("additionalPaths", [])) if path]
            result = {
                "id": identity,
                "status": statuses.get(source["status"], "unavailable"),
                "repo": source["repository"],
                "ref": source.get("headRef"),
                "headRef": source.get("headRef"),
                "head": source.get("headRevision"),
                "commit": source["pinnedRevision"],
                "reviewed": None,
                "base": "commit",
                "upstreamPaths": paths or ["."],
                "localPaths": [f"skills/{name}"],
                "skill": name,
            }
            if result["status"] == "unavailable":
                result["reason"] = source.get("reason", source["status"])
            commits = source.get("commits") or {}
            result["count"] = commits.get("count", 0)
            result["commits"] = [
                {"sha": entry["revision"], "date": entry["date"], "subject": entry["subject"]}
                for entry in commits.get("entries", [])
            ]
            results.append(result)
    return results


def issue_title(result: dict) -> str:
    count = result["count"]
    noun = "commit" if count == 1 else "commits"
    return f"Upstream {result['id']} changed: {count} {noun} since {result[result['base']][:MESSAGE_SHA]}"


def _safe(text: str) -> str:
    """A subject inside a text fence: no backtick to close the fence, no control character."""
    return "".join(character if character.isprintable() else " " for character in text.replace("`", "'"))


def issue_body(result: dict) -> str:
    base = result[result["base"]]
    count = result["count"]
    noun = "commit" if count == 1 else "commits"
    code = lambda values: ", ".join(f"`{value}`" for value in values)  # noqa: E731
    lines = [
        MARKER.format(result["id"]),
        "## Specify",
        "",
        MOTIVATION,
        "",
        "As the owner, I want to know when an upstream I adapted moves, so that I adopt or reject the change on purpose.",
        "",
        "### What moved",
        "",
        f"The upstream of `{result['id']}` moved: {count} {noun} since `{base[:MESSAGE_SHA]}` "
        f"{'touches' if count == 1 else 'touch'} its upstream paths.",
        "",
        f"- Upstream: {result['repo']}",
        f"- Watched ref: `{result['ref']}`"
        + (f", now `{result['headRef']}`" if result["headRef"] != result["ref"] else "")
        + f" at `{result['head'][:MESSAGE_SHA]}`",
        f"- Pinned commit: `{result['commit']}`",
    ]
    if result.get("reviewed"):
        lines.append(f"- Reviewed commit: `{result['reviewed']}`")
    lines += [f"- Upstream paths: {code(result['upstreamPaths'])}", f"- Local paths: {code(result['localPaths'])}"]
    if "licence" in result:
        lines.append(f"- Local patches: {code([result['patches']]) if result['patches'] else 'none'}")
        lines.append(f"- Licence: `{result['licence']}`")
    repository = result["repo"].rstrip("/").removesuffix(".git")
    if repository.startswith(GITHUB_PREFIX):
        lines.append(f"- Compare: {repository}/compare/{base}...{result['head']}")
    lines += ["", "Newest commits on the upstream paths:", "", "```text"]
    lines += [f"{commit['sha'][:MESSAGE_SHA]} {commit['date']} {_safe(commit['subject'])}" for commit in result["commits"]]
    if count > len(result["commits"]):
        lines.append(f"... and {count - len(result['commits'])} more")
    lines += ["```", "", "## Clarify", "", "The choice is the owner's, per source: adopt or reject.", "",
              f"Estimate before planning: {effort(result)}", ""]
    if "skill" in result:
        lines.append(
            f"To decide, run `python3 skills/bench-skills-upstream/scripts/discover.py {result['skill']}` and follow "
            "`bench-skills-upstream`. Its `record` command moves the pin for an adoption or a review, and the next "
            f"`{WORKFLOW}` run closes this issue."
        )
    else:
        lines.append(
            "To adopt, port the change and set `commit` in `upstreams.json` to the upstream commit the copy now "
            f"matches. To reject, set `reviewed` to `{result['head']}`. The next `{WORKFLOW}` run closes this "
            "issue either way."
        )
    lines += ["", f"The `{WORKFLOW}` workflow opened this issue. It only reads the upstream and changes no code."]
    return "\n".join(lines) + "\n"


def _where(result: dict) -> str:
    return f" on `{result['headRef']}` at `{result['head'][:MESSAGE_SHA]}`" if result.get("head") else ""


def _normal(text: str | None) -> str:
    return (text or "").replace("\r\n", "\n").strip()


def plan_issues(results: list[dict], open_issues: list[dict]) -> list[dict]:
    """The dedup rule: the marker names the source, the lowest open issue number owns it, a moved
    source edits that issue only when its text changed, and an unchanged or gone source closes it."""
    owners: dict[str, dict] = {}
    for issue in sorted(open_issues, key=lambda issue: issue["number"]):
        match = MARKER_LINE.match(_normal(issue.get("body")))
        if match:
            owners.setdefault(match.group(1), issue)
    actions: list[dict] = []
    for result in results:
        # Popped for every reported source, so an unavailable one keeps its issue open and untouched.
        issue = owners.pop(result["id"], None)
        if result["status"] == "moved":
            title, body = issue_title(result), issue_body(result)
            if issue is None:
                actions.append({"action": "create", "id": result["id"], "title": title, "body": body})
            elif issue["title"] != title or _normal(issue.get("body")) != _normal(body):
                actions.append({"action": "edit", "id": result["id"], "number": issue["number"], "title": title, "body": body})
        elif result["status"] == "unchanged" and issue is not None:
            covered = "the recorded review covers it" if result["base"] == "reviewed" else "the pin covers it"
            actions.append({
                "action": "close",
                "id": result["id"],
                "number": issue["number"],
                "reason": "not planned" if result["base"] == "reviewed" else "completed",
                "comment": f"`{result['id']}` has no unreported upstream commit{_where(result)}: {covered}. "
                f"Closed by the `{WORKFLOW}` workflow.",
            })
        elif result["status"] == "retired" and issue is not None:
            actions.append({
                "action": "close",
                "id": result["id"],
                "number": issue["number"],
                "reason": "not planned",
                "comment": f"`{result['id']}` is retired: {result['reason']}. Closed by the `{WORKFLOW}` workflow.",
            })
    for identity, issue in owners.items():
        actions.append({
            "action": "close",
            "id": identity,
            "number": issue["number"],
            "reason": "not planned",
            "comment": f"`{identity}` is no longer a tracked upstream source. Closed by the `{WORKFLOW}` workflow.",
        })
    return actions


ALERT_MARKER = "<!-- workflow-alert: {} -->"
ALERT_LINE = re.compile(r"\A<!-- workflow-alert: (.+?) -->")
# Each alert comment's first line: the workflow posts with the owner's token, so without a script marker
# Workbench's backlog read its comment as a person's to answer (`next_move.py`, #2133).
COMMENT_MARK = "<!-- skd-workflow-alert -->\n"
ALERT_LABELS = ("type: maintenance", "priority: P2")
MAIN_LABELS = ("type: bug", "priority: P1")  # a red main is a defect, and backlog.py orders it first (#1431)
SHORT_SHA = 12  # the commit as an issue title names it
ON_MAIN = "{} on {}"  # the marker's name for a run on a landing branch, `main` or `staging` (`--sha`, #1431, #1883)
MOTIVATION = "### Motivation"


def alert_text(marker: str, want: str, current: str, results: dict, expected: str, clarify: str, origin: str) -> str:
    """An alert issue in the capture shape: its marker, why, the run and its jobs, and how to resolve it."""
    jobs = [f"- `{_safe(name)}`: {_safe(str(job.get('result')))}" for name, job in sorted(results.items())]
    return "\n".join([
        ALERT_MARKER.format(marker), "## Specify", "", MOTIVATION, "", want, "",
        "### Current behavior", "", current, "", *jobs, "",
        "### Expected outcome", "", f"- {expected}", "",
        "## Clarify", "", clarify, "", "Estimate before planning: S", "", origin,
    ]) + "\n"


def alert_body(workflow: str, results: dict, run_url: str) -> str:
    """The failed run's issue: which jobs did not succeed, the run, and how to resolve it."""
    return alert_text(
        workflow,
        f"As the owner, I want to know when the scheduled `{workflow}` run fails or is cut, so that its report never stops in silence.",
        f"The last scheduled run did not finish green: {run_url}", results,
        "The next scheduled run finishes green, and this issue closes on its own.",
        "Read the failed job's log first: a cancelled job reached its timeout, and the step's last lines name the slow source.",
        f"The scheduled `{workflow}` run opened this issue and keeps it current.")


def main_body(workflow: str, sha: str, results: dict, run_url: str, bisect: str = "", failed: list[str] | None = None,
              branch: str = "main") -> str:
    """A red run on the default branch: its marker, which backlog.py orders first, and the commit (#1431).
    `bisect` is the run's `ci_bisect:` line, which names the commit that turned it red (#1715); `failed`
    the suites that failed, each named (#1710)."""
    found = f"\n\nThe bisect over the failing suites read: `{_safe(bisect)}`." if bisect.strip() else ""
    suites = [suite.strip() for suite in failed or [] if suite.strip()]
    if suites:
        found += "\n\nFailed suites: " + ", ".join(f"`{_safe(suite)}`" for suite in suites) + "."
    return alert_text(
        ON_MAIN.format(workflow, branch),
        f"As the owner, I want `{workflow}` on {branch} green, so that every session installs and builds on a validated commit.",
        f"`{workflow}` ended red on {branch} at `{_safe(sha)}`: {run_url}{found}", results,
        f"A new commit on {branch} makes the run green, and this issue closes on its own.",
        f"Read the failed step's log first, then fix it with a new commit on {branch}, never a rewrite of history.",
        f"A workflow run after `{workflow}` opened this issue and keeps it current.")


RED_ON_MAIN = {"failure", "timed_out", "startup_failure"}  # a run's conclusions that leave main unvalidated (#1440)


def plan_alert(workflow: str, results: dict, run_url: str, open_issues: list[dict], sha: str = "",
               bisect: str = "", failed: list[str] | None = None, branch: str = "main") -> dict | None:
    """One issue per workflow: the lowest open number with its marker owns it. A failed or cancelled
    job creates it or edits it; every job a success closes it; skipped jobs count for neither.
    With `sha`, a run on the default branch (#1431): a failure, a time-out or a startup failure alerts
    (#1440), never a cancelled run, which a newer one replaced, and the issue is named for the commit."""
    name = ON_MAIN.format(workflow, branch) if sha else workflow
    owner = next((issue for issue in sorted(open_issues, key=lambda issue: issue["number"])
                  if (match := ALERT_LINE.match(_normal(issue.get("body")))) and match.group(1) == name), None)
    outcomes = {str(job.get("result")) for job in results.values()}
    if sha:
        if outcomes & RED_ON_MAIN:
            title, body = f"{workflow} red on {branch} at {sha[:SHORT_SHA]}", main_body(workflow, sha, results, run_url, bisect, failed, branch)
            if owner is None:
                return {"action": "create", "title": title, "body": body, "labels": MAIN_LABELS}
            return {"action": "edit", "number": owner["number"], "title": title, "body": body, "labels": MAIN_LABELS,
                    "comment": COMMENT_MARK + f"`{workflow}` is still red on {branch}, now at `{_safe(sha)}`: {run_url}"}
        if owner is not None and outcomes and outcomes <= {"success", "skipped"} and "success" in outcomes:
            return {"action": "close", "number": owner["number"],
                    "comment": COMMENT_MARK + f"`{workflow}` is green on {branch} at `{_safe(sha)}`: {run_url}. Closed by the workflow."}
        return None
    if outcomes & (RED_ON_MAIN | {"cancelled"}):  # a scheduled run's time-out alerts too (#1442)
        title = f"{workflow} failed on its scheduled run"
        body = alert_body(workflow, results, run_url)
        if owner is None:
            return {"action": "create", "title": title, "body": body}
        return {"action": "edit", "number": owner["number"], "title": title, "body": body,
                "comment": COMMENT_MARK + f"The scheduled run failed again: {run_url}"}
    if owner is not None and outcomes and outcomes <= {"success", "skipped"} and "success" in outcomes:
        return {"action": "close", "number": owner["number"],
                "comment": COMMENT_MARK + f"The scheduled `{workflow}` run finished green: {run_url}. Closed by the workflow."}
    return None


def alert(workflow: str, results: dict, run_url: str, repo: str, sha: str = "", bisect: str = "",
          failed: list[str] | None = None, branch: str = "main") -> int:
    listed = json.loads(_gh("issue", "list", "--repo", repo, "--state", "open", "--limit", "1000", "--json", "number,title,body"))
    action = plan_alert(workflow, results, run_url, listed, sha, bisect, failed, branch)
    if action is None:
        print(f"no alert issue to open, update or close for {workflow}")
        return 0
    print(f"{action['action']} {'#' + str(action['number']) if 'number' in action else 'a new issue'} for {workflow}")
    if action["action"] == "close":
        _gh("issue", "close", str(action["number"]), "--repo", repo, "--reason", "completed", "--comment", action["comment"])
        return 0
    existing = {entry["name"] for entry in json.loads(_gh("label", "list", "--repo", repo, "--limit", "1000", "--json", "name"))}
    labels = [label for label in action.get("labels", ALERT_LABELS) if label in existing] + ["effort: S"] * ("effort: S" in existing)
    if action["action"] == "create":
        flags = [part for label in labels for part in ("--label", label)]
        _gh("issue", "create", "--repo", repo, "--title", action["title"], "--body-file", "-", *flags, stdin=action["body"])
    else:
        flags = [part for label in labels for part in ("--add-label", label)]
        _gh("issue", "edit", str(action["number"]), "--repo", repo, "--title", action["title"], "--body-file", "-", *flags, stdin=action["body"])
        _gh("issue", "comment", str(action["number"]), "--repo", repo, "--body-file", "-", stdin=action["comment"])
    return 0


def _gh(*args: str, stdin: str | None = None) -> str:
    # No inherited stdin: a gh call without a body must never wait on the terminal.
    result = subprocess.run(["gh", *args], input=stdin or "", capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"gh {' '.join(args[:2])} failed: {result.stderr.strip()}")
    return result.stdout


def load_verdict(path: Path, root: Path):
    """body -> verdict, from Skill Deck's `runs_rule.py` at `path` over the checkout `root` (#1659). Only a
    checkout that holds the rule passes it, so this asset stays self-contained in every other repository."""
    sys.path.insert(0, str(path.resolve().parent))
    import importlib.util
    spec = importlib.util.spec_from_file_location("runs_rule", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    checker = module.Checker(root)
    return lambda body: checker.body_verdict(body, set())


def sync(results: list[dict], repo: str, dry_run: bool, verdict=None) -> int:
    listed = json.loads(_gh("issue", "list", "--repo", repo, "--state", "open", "--limit", "1000", "--json", "number,title,body,labels"))
    actions = plan_issues(results, listed)
    held = {issue["number"]: {label["name"] for label in issue.get("labels", [])} for issue in listed}
    sizes = {result["id"]: f"effort: {effort(result)}" for result in results if result.get("status") == "moved"}
    for result in results:
        print(describe(result))
    labels: list[str] = []
    existing: set[str] = set()
    if not dry_run and any(action["action"] in ("create", "edit") for action in actions):
        listed_labels = json.loads(_gh("label", "list", "--repo", repo, "--limit", "1000", "--json", "name"))
        existing = {entry["name"] for entry in listed_labels}
        labels = [label for label in LABELS if label in existing]
    for action in actions:
        target = f"#{action['number']}" if "number" in action else "a new issue"
        print(f"{'would ' if dry_run else ''}{action['action']} {target} for {action['id']}")
        if dry_run:
            continue
        runs = RUNS.get(verdict(action["body"])) if verdict and action["action"] != "close" else None
        runs = [runs] if runs in existing else []
        if action["action"] == "create":
            wanted = labels + [sizes[action["id"]]] * (sizes[action["id"]] in existing) + runs
            flags = [part for label in wanted for part in ("--label", label)]
            _gh("issue", "create", "--repo", repo, "--title", action["title"], "--body-file", "-", *flags, stdin=action["body"])
        elif action["action"] == "edit":
            size = sizes[action["id"]]
            wanted = labels + [size] * (size in existing) + runs
            # One effort: a moved count replaces the old size instead of adding a second (#808); one runs: (#1659).
            stale = sorted(name for name in held.get(action["number"], ())
                           if (name.startswith("effort: ") and name != size) or (runs and name in RUNS.values() and name not in runs))
            flags = [part for label in wanted for part in ("--add-label", label)]
            flags += [part for label in stale for part in ("--remove-label", label)]
            _gh("issue", "edit", str(action["number"]), "--repo", repo, "--title", action["title"], "--body-file", "-", *flags, stdin=action["body"])
        else:
            _gh("issue", "close", str(action["number"]), "--repo", repo, "--reason", action["reason"], "--comment", action["comment"])
    if not actions:
        print("no issue to open, update or close")
    return 1 if any(result["status"] == "unavailable" for result in results) else 0


def describe(result: dict) -> str:
    if result["status"] == "unavailable":
        return f"unavailable  {result['id']}: {result['reason']}"
    if result["status"] == "retired":
        return f"retired      {result['id']}: skipped, {result['reason']}"
    since = f"since {result[result['base']][:MESSAGE_SHA]}"
    if result["status"] == "moved":
        return f"moved        {result['id']}: {result['count']} commits {since}{_where(result)}".replace("`", "")
    return f"unchanged    {result['id']}: no commit {since} touches its upstream paths{_where(result)}".replace("`", "")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("validate", "check"):
        command = commands.add_parser(name)
        command.add_argument("--manifest", type=Path, default=Path(MANIFEST))
    check_parser = commands.choices["check"]
    check_parser.add_argument("--json", action="store_true", help="print the report as JSON")
    check_parser.add_argument("--output", type=Path, help="also write the JSON report to this file")
    sync_parser = commands.add_parser("sync")
    sync_parser.add_argument("--repo", required=True, help="OWNER/NAME of the repository that gets the issues")
    source = sync_parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--report", type=Path, help="a report written by check --output")
    source.add_argument("--discover", type=Path, help="Skill Deck's discover.py --json report")
    sync_parser.add_argument("--dry-run", action="store_true", help="print the issue changes and make none")
    sync_parser.add_argument("--runs-rule", type=Path, help="Skill Deck's runs_rule.py: label each issue runs: cloud or mac (#1659)")
    alert_parser = commands.add_parser("alert")
    alert_parser.add_argument("--repo", required=True, help="OWNER/NAME of the repository that gets the issue")
    alert_parser.add_argument("--workflow", required=True, help="the workflow's name")
    alert_parser.add_argument("--run-url", required=True, help="the run's URL, for the issue")
    alert_parser.add_argument("--results", required=True, help="the workflow's toJSON(needs), a file or - for stdin")
    alert_parser.add_argument("--sha", default="", help="a run on the default branch at this commit: only a failure alerts (#1431)")
    alert_parser.add_argument("--branch", default="main", help="the landing branch the run was on, main or staging (#1883)")
    alert_parser.add_argument("--bisect", default="", help="the run's `ci_bisect:` line, written into the red-main issue (#1715)")
    alert_parser.add_argument("--failed", default="", help="the red run's failed suites, one per line, named in the red-main issue (#1710)")
    args = parser.parse_args(argv)

    if args.command == "alert":
        try:
            text = sys.stdin.read() if args.results == "-" else Path(args.results).read_text(encoding="utf-8")
            results = json.loads(text)
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            print(f"cannot read the job results: {error}", file=sys.stderr)
            return 2
        if not isinstance(results, dict) or not all(isinstance(job, dict) for job in results.values()):
            print("cannot read the job results: expected toJSON(needs), an object of jobs", file=sys.stderr)
            return 2
        return alert(args.workflow, results, args.run_url, args.repo, args.sha, args.bisect, args.failed.splitlines(), args.branch)

    if args.command == "sync":
        try:
            data = json.loads((args.report or args.discover).read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            print(f"cannot read the report: {error}", file=sys.stderr)
            return 2
        results = from_discover(data) if args.discover else data["sources"]
        try:
            verdict = load_verdict(args.runs_rule, Path.cwd()) if args.runs_rule else None
        except Exception as error:  # noqa: BLE001  any failure of the optional rule leaves the issues unlabelled, never unsynced
            print(f"runs: label skipped, the rule could not load: {error}", file=sys.stderr)
            verdict = None
        return sync(results, args.repo, args.dry_run, verdict)

    try:
        sources = load_manifest(args.manifest)
    except ManifestError as error:
        print(error, file=sys.stderr)
        return 1 if args.command == "validate" else 2
    if args.command == "validate":
        print(f"{args.manifest}: {len(sources)} sources valid")
        return 0

    results = check(sources)
    report = json.dumps({"sources": results}, indent=2) + "\n"
    if args.output:
        args.output.write_text(report, encoding="utf-8")
    print(report if args.json else "\n".join(describe(result) for result in results), end="" if args.json else "\n")
    return 1 if any(result["status"] == "unavailable" for result in results) else 0


if __name__ == "__main__":
    sys.exit(main())
