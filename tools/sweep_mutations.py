#!/usr/bin/env python3
"""Run the test suite against every mutation produced by tools/gen_mutations.py.

    tools/sweep_mutations.py                 # every mutation, every suite
    tools/sweep_mutations.py goals interact  # only those suites (much faster)
    ONLY=1,4,9-12 tools/sweep_mutations.py   # only those mutation ids
    WORKERS=4 tools/sweep_mutations.py       # parallelism, default 2

A mutation is "caught" when the suite fails with it applied, and "survived" when the suite
still passes — a survivor means either that the line is untested, or that the mutation is
equivalent and cannot change behaviour. Both need a human to decide which; the equivalent
ones are listed in REFACTOR_PLAN.md so a later sweep does not re-investigate them.

Each worker gets its own copy of the tree under a temporary directory and runs there, so
the real working tree is never mutated — a sweep killed partway through would otherwise
leave a half-applied mutation behind. Run this in the foreground with WORKERS=2: a
background sweep on this machine gets killed for low memory.

Reads $MUTATIONS (default /tmp/starhunt_mutations.json).
"""

import concurrent.futures
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MUTATIONS = os.environ.get("MUTATIONS", os.path.join(tempfile.gettempdir(), "starhunt_mutations.json"))
WORKERS = int(os.environ.get("WORKERS", "2"))
COPIED = ["StarHunt", "test", "tools", ".luacheckrc", ".luarc.json"]


def parse_only(spec):
    """"1,4,9-12" -> {1, 4, 9, 10, 11, 12}."""
    wanted = set()
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            lo, hi = part.split("-")
            wanted.update(range(int(lo), int(hi) + 1))
        else:
            wanted.add(int(part))
    return wanted


def make_worktree():
    tmp = tempfile.mkdtemp(prefix="sweep_")
    for name in COPIED:
        source = os.path.join(ROOT, name)
        if not os.path.exists(source):
            continue
        target = os.path.join(tmp, name)
        if os.path.isdir(source):
            shutil.copytree(source, target)
        else:
            shutil.copy2(source, target)
    return tmp


def apply(tree, mutation):
    """Write the mutated line into the worker's copy, and return the original lines."""
    path = os.path.join(tree, mutation["file"])
    with open(path) as fh:
        lines = fh.read().split("\n")
    index = mutation["line"] - 1
    original = lines[index]
    if original != mutation["old"]:
        raise SystemExit("mutation %d: line %d of %s is not what gen recorded; regenerate"
                         % (mutation["id"], mutation["line"], mutation["file"]))
    lines[index] = mutation["new"]
    with open(path, "w") as fh:
        fh.write("\n".join(lines))
    return path, original, lines


def restore(path, lines, index, original):
    lines[index] = original
    with open(path, "w") as fh:
        fh.write("\n".join(lines))


def run_one(tree, mutation, suites):
    path, original, lines = apply(tree, mutation)
    try:
        done = subprocess.run(["lua5.4", "test/run.lua"] + suites,
                              cwd=tree, env=dict(os.environ, PWD=tree),
                              capture_output=True, text=True)
        return done.returncode != 0
    finally:
        restore(path, lines, mutation["line"] - 1, original)


def main():
    suites = sys.argv[1:]
    with open(MUTATIONS) as fh:
        mutations = json.load(fh)
    only = parse_only(os.environ.get("ONLY", ""))
    if only:
        mutations = [m for m in mutations if m["id"] in only]
    if not mutations:
        sys.exit("no mutations selected")

    trees = [make_worktree() for _ in range(WORKERS)]
    survivors, caught = [], 0
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
            chunks = [mutations[i::WORKERS] for i in range(WORKERS)]

            def work(index):
                results = []
                for mutation in chunks[index]:
                    results.append((mutation, run_one(trees[index], mutation, suites)))
                return results

            for results in pool.map(work, range(WORKERS)):
                for mutation, was_caught in results:
                    if was_caught:
                        caught += 1
                    else:
                        survivors.append(mutation)
    finally:
        for tree in trees:
            shutil.rmtree(tree, ignore_errors=True)

    print("%d mutations: %d caught, %d survived" % (len(mutations), caught, len(survivors)))
    for mutation in sorted(survivors, key=lambda m: m["id"]):
        print("  SURVIVED %-4d %s:%d  %s" % (mutation["id"], mutation["file"],
                                             mutation["line"], mutation["rule"]))
        print("           %s" % mutation["old"].strip())
        print("        -> %s" % (mutation["new"].strip() or "(line deleted)"))
    if survivors:
        print("\nONLY=%s" % ",".join(str(m["id"]) for m in sorted(survivors, key=lambda m: m["id"])))


if __name__ == "__main__":
    main()
