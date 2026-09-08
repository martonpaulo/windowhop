#!/usr/bin/env python3
"""A stand-in for `gh release` used by scripts/tests/publish-release-tests.sh.

It keeps the release state in FAKE_GH_STATE, appends one line per operation to
FAKE_GH_LOG, and fails the single operation named in FAKE_GH_FAIL. No network,
no token, no real release.
"""
import json
import os
import sys


def load():
    with open(os.environ["FAKE_GH_STATE"]) as handle:
        return json.load(handle)


def save(state):
    with open(os.environ["FAKE_GH_STATE"], "w") as handle:
        json.dump(state, handle)


def record(operation):
    with open(os.environ["FAKE_GH_LOG"], "a") as handle:
        handle.write(operation + "\n")
    if os.environ.get("FAKE_GH_FAIL") == operation:
        sys.stderr.write("simulated failure: %s\n" % operation)
        sys.exit(1)


def main(argv):
    if argv[:1] != ["release"]:
        sys.exit("fake gh only implements `gh release`")
    command, args = argv[1], argv[2:]
    state = load()

    if command == "view":
        if os.environ.get("FAKE_GH_FAIL") == "view:auth":
            record("view")
            sys.stderr.write("HTTP 401: Bad credentials\n")
            sys.exit(1)
        record("view")
        if not state["exists"]:
            sys.stderr.write("release not found\n")
            sys.exit(1)
        if "--json" in args and "isDraft" in args[args.index("--json") + 1]:
            print("true" if state["draft"] else "false")
        else:
            print(json.dumps({"assets": [{"name": name, "size": size}
                                         for name, size in state["assets"].items()]}))
        return

    if command == "create":
        record("create")
        state.update(exists=True, draft="--draft" in args, assets={})
        save(state)
        return

    if command == "upload":
        path = args[1]
        record("upload:" + os.path.basename(path))
        state["assets"][os.path.basename(path)] = os.path.getsize(path)
        save(state)
        return

    if command == "edit":
        record("edit:publish" if "--draft=false" in args else "edit")
        state["draft"] = False
        save(state)
        return

    sys.exit("fake gh does not implement `gh release %s`" % command)


main(sys.argv[1:])
