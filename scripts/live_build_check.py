#!/usr/bin/env python3
"""Confirm the live site serves the build of the deployed commit (#753).

    live_build_check.py URL SHA [--timeout SECONDS] [--interval SECONDS]

The build writes the commit into the published output (a `<meta name="build" content="<sha>">` or
a `build.txt`), and the deploy job's last step runs this against the live URL. It fetches the URL
with a cache-busting query, passes when the body contains SHA, and retries until the deadline,
because a publication is not instant.
Exit 0 when the site serves SHA, 1 when the deadline passes with another build, 2 on a usage error
or a value that is not a commit SHA. Copy it unchanged into a project, as the bench-setup skill's
references/ci-pipelines.md says. Standard library only.
"""

from __future__ import annotations

import argparse
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

FETCH_TIMEOUT = 30  # seconds for one request
DEFAULT_TIMEOUT = 600.0  # seconds to keep trying
DEFAULT_INTERVAL = 15.0  # seconds between attempts
SHA = re.compile(r"[0-9a-f]{7,40}")


def busted(url: str, sha: str, attempt: int) -> str:
    """The URL with a query a cache has never seen, so a CDN cannot answer with the old build."""
    parts = urllib.parse.urlsplit(url)
    query = urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
    query.append(("live-build-check", f"{sha}-{attempt}"))
    return urllib.parse.urlunsplit(parts._replace(query=urllib.parse.urlencode(query)))


def fetch(url: str) -> tuple[str, str]:
    """(status, body); an HTTP or network failure is a status, not a crash."""
    request = urllib.request.Request(url, headers={"Cache-Control": "no-cache", "User-Agent": "live-build-check/1"})
    try:
        with urllib.request.urlopen(request, timeout=FETCH_TIMEOUT) as response:
            return str(response.status), response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return f"HTTP {exc.code}", ""
    except (urllib.error.URLError, OSError) as exc:
        return f"error: {getattr(exc, 'reason', exc)}", ""


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("url", help="the live page or build file, http or https")
    parser.add_argument("sha", help="the deployed commit, 7 to 40 hexadecimal characters")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT, help="seconds to keep trying (default 600)")
    parser.add_argument("--interval", type=float, default=DEFAULT_INTERVAL, help="seconds between attempts (default 15)")
    args = parser.parse_args(argv)
    sha = args.sha.strip().lower()
    if not SHA.fullmatch(sha):
        parser.error(f"not a commit SHA: {args.sha!r}")
    if urllib.parse.urlsplit(args.url).scheme not in {"http", "https"}:
        parser.error(f"not an http or https URL: {args.url!r}")
    if args.timeout < 0 or args.interval <= 0:
        parser.error("--timeout must be 0 or more and --interval more than 0")
    deadline = time.monotonic() + args.timeout
    attempt = 0
    while True:
        attempt += 1
        status, body = fetch(busted(args.url, sha, attempt))
        if sha in body.lower():
            print(f"live: {args.url} serves {sha} (attempt {attempt})")
            return 0
        if time.monotonic() + args.interval > deadline:
            print(f"live: {args.url} does not serve {sha} after {attempt} attempt(s); last status {status}")
            return 1
        time.sleep(args.interval)


if __name__ == "__main__":
    sys.exit(main())
