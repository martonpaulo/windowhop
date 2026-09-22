#!/usr/bin/env python3
"""A stand-in for `gh release`, used by tests/scripts/publish-release-tests.sh.

It keeps the release in FAKE_GH_STATE as {"exists", "draft", "assets": {name: {"size",
"digest"}}}, appends one line per operation to FAKE_GH_LOG, and injects the failures named
in FAKE_GH_FAIL (comma-separated). No network, no token, no real release.

  view:isDraft         every draft-state query fails, as a timeout or a 502 would
  view:isDraft#<n>     only the n-th draft-state query of the run fails
  view:isDraft=null    the draft-state query answers null, as for a missing field
  edit:noop            `edit --draft=false` is logged but the release stays a draft
  upload:<name>:corrupt  the stored asset keeps its size but gets another digest

An asset whose state has no "digest" is reported without one, as GitHub may.
"""
import hashlib
import json
import os
import sys


def load():
    with open(os.environ["FAKE_GH_STATE"], encoding="utf-8") as handle:
        return json.load(handle)


def save(state):
    with open(os.environ["FAKE_GH_STATE"], "w", encoding="utf-8") as handle:
        json.dump(state, handle)


def record(operation):
    with open(os.environ["FAKE_GH_LOG"], "a", encoding="utf-8") as handle:
        handle.write(operation + "\n")


def failures():
    return [item for item in os.environ.get("FAKE_GH_FAIL", "").split(",") if item]


def draft_query(state):
    """Answers `gh release view --json isDraft --jq .isDraft`, or fails as asked."""
    state["draftQueries"] = state.get("draftQueries", 0) + 1
    save(state)
    injected = failures()
    if "view:isDraft" in injected or "view:isDraft#%d" % state["draftQueries"] in injected:
        sys.stderr.write("Post \"https://api.github.com/graphql\": context deadline exceeded\n")
        sys.exit(1)
    print("null" if "view:isDraft=null" in injected else ("true" if state["draft"] else "false"))


def main(argv):
    if argv[:1] != ["release"]:
        sys.stderr.write("fake gh only implements `gh release`\n")
        sys.exit(2)
    command, args = argv[1], argv[2:]
    state = load()

    if command == "view":
        record("view")
        if not state["exists"]:
            sys.stderr.write("release not found\n")
            sys.exit(1)
        fields = args[args.index("--json") + 1] if "--json" in args else ""
        if fields == "isDraft":
            draft_query(state)
            return
        print(json.dumps({"assets": [
            dict({"name": name, "size": asset["size"]},
                 **({"digest": asset["digest"]} if asset.get("digest") else {}))
            for name, asset in state["assets"].items()]}))
        return

    if command == "create":
        record("create")
        state.update(exists=True, draft="--draft" in args, assets={})
        save(state)
        return

    if command == "upload":
        path = args[1]
        name = os.path.basename(path)
        record("upload:" + name)
        with open(path, "rb") as handle:
            data = handle.read()
        stored = data[:-1] + b"?" if "upload:%s:corrupt" % name in failures() else data
        state["assets"][name] = {"size": len(stored),
                                 "digest": "sha256:" + hashlib.sha256(stored).hexdigest()}
        save(state)
        return

    if command == "edit":
        record("edit:publish" if "--draft=false" in args else "edit")
        if "edit:noop" not in failures():
            state["draft"] = False
        save(state)
        return

    sys.stderr.write("fake gh does not implement `gh release %s`\n" % command)
    sys.exit(2)


main(sys.argv[1:])
