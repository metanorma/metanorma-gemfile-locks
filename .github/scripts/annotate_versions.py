#!/usr/bin/env python3
"""Annotate metanorma/versions data/gemfile/versions.yaml with release provenance.

Usage: annotate_versions.py VERSION CREATED_AT_ISO RUN_ID RUN_URL [PATH]
Default PATH: data/gemfile/versions.yaml

Idempotent: an entry already carrying release_provenance is left untouched.
Updates metadata.count / metadata.latest_version only when a new entry is
appended. Exits non-zero on structural surprises (never silently corrupts).
"""
import re
import sys
from datetime import datetime, timezone

VERSION_RE = re.compile(r"^- version: (\S+)\s*$", re.M)


def vkey(v):
    return tuple(int(x) for x in v.lstrip("v").split(".") if x.isdigit() or x)


def main():
    if len(sys.argv) < 5:
        sys.exit("usage: annotate_versions.py VERSION CREATED_AT RUN_ID RUN_URL [PATH]")
    ver, created, run_id, run_url = sys.argv[1:5]
    path = sys.argv[5] if len(sys.argv) > 5 else "data/gemfile/versions.yaml"
    ver = ver.lstrip("v")
    src = open(path, encoding="utf-8").read()

    matches = list(VERSION_RE.finditer(src))
    if not matches:
        sys.exit("no version entries found — refusing to touch file")

    existing = next((m for m in matches if m.group(1) == ver), None)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    provenance = (
        f"  rubygems_created_at: '{created}'\n"
        f"  release_provenance:\n"
        f"    published_via: workflow\n"
        f"    workflow_run_id: {run_id}\n"
        f"    workflow_url: {run_url}\n"
        f"    annotation: 'rubygems-release.yml post-publish writer (ci#367)'\n"
    )

    if existing is not None:
        # entry exists — insert the two fields unless already annotated
        start = existing.start()
        nxt = VERSION_RE.search(src, existing.end())
        end = nxt.start() if nxt else len(src)
        block = src[start:end]
        if "release_provenance:" in block:
            print(f"entry {ver} already annotated — no change")
            open(path, "w", encoding="utf-8").write(src)
            return
        # insertion point: end of the entry's last populated line (strip
        # trailing blank lines between entries, put fields, restore gap)
        stripped = block.rstrip("\n")
        new_block = stripped + "\n" + provenance.rstrip("\n")
        trailing = block[len(stripped):]
        out = src[:start] + new_block + trailing + src[end:]
        open(path, "w", encoding="utf-8").write(out)
        print(f"annotated existing entry {ver}")
        return

    # new entry — schema-valid with gemfile_exists: false (docker channel
    # not yet published; mnenv refresh later flips it and fills the paths)
    entry = (
        f"- version: {ver}\n"
        f"  published_at: null\n"
        f"  parsed_at: '{now}'\n"
        f"  gemfile_exists: false\n"
        f"  gemfile_path: null\n"
        f"  gemfile_lock_path: null\n"
        f"{provenance}"
    )
    # versions list is the last top-level key and entries carry no blank
    # lines between them — append at EOF.
    out = src.rstrip("\n") + "\n" + entry

    # metadata: count + latest_version
    def bump_count(m):
        return f"  count: {int(m.group(1)) + 1}"

    out = re.sub(r"(?m)^  count: (\d+)$", bump_count, out, count=1)

    latest_m = re.search(r"(?m)^  latest_version: (\S+)$", out)
    if latest_m and vkey(ver) > vkey(latest_m.group(1)):
        out = out.replace(
            latest_m.group(0), f"  latest_version: {ver}", 1,
        )

    open(path, "w", encoding="utf-8").write(out)
    print(f"appended new entry {ver}; count/latest updated")


if __name__ == "__main__":
    main()
