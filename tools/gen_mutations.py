#!/usr/bin/env python3
"""Generate source mutations for a range of lines, for mutation-testing the suite.

This project's process requires that code moved by a refactor pass is mutation-checked:
change the moved code in small ways and confirm the test suite notices. That check has
found a real coverage gap in nineteen of twenty-one passes so far, so it is not optional.

    tools/gen_mutations.py StarHunt/modules/goals.lua 100,140 812,820

Arguments are the file and one or more 1-based inclusive line ranges within it. The
mutations are written as JSON to $MUTATIONS (default /tmp/starhunt_mutations.json), which
tools/sweep_mutations.py then runs. The default is outside the repository on purpose:
nothing here should leave an untracked file in `git status`.

Comments and the insides of string literals are blanked before any rule is matched, so a
rule cannot fire inside a player-visible label and produce a "mutation" that only changes
Spanish text. Candidates that do not compile under luac5.4 are dropped.

Rules applied: comparison flips, and/or swaps, numeric bumps (v+1, v-1, 0), whole-line
deletion, and swapping one named engine constant for another that the same file uses.
"""

import json
import os
import re
import subprocess
import sys
import tempfile

LUAC = "luac5.4"
OUT = os.environ.get("MUTATIONS", os.path.join(tempfile.gettempdir(), "starhunt_mutations.json"))


def mask(text):
    """Return text with comment bodies and string bodies replaced by spaces.

    Length and line structure are preserved, so an offset into the mask is the same
    offset into the original. Quotes and comment markers themselves are kept, which is
    enough: no rule matches on them.
    """
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "-" and text.startswith("--", i):
            if text.startswith("--[[", i):
                end = text.find("]]", i + 4)
                end = n if end < 0 else end + 2
            else:
                end = text.find("\n", i)
                end = n if end < 0 else end
            for j in range(i + 2, end):
                if out[j] != "\n":
                    out[j] = " "
            i = end
        elif c in "\"'":
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                if text[j] == "\\":
                    j += 1
                j += 1
            for k in range(i + 1, min(j, n)):
                out[k] = " "
            i = j + 1
        elif c == "[" and text.startswith("[[", i):
            end = text.find("]]", i + 2)
            end = n if end < 0 else end
            for j in range(i + 2, end):
                if out[j] != "\n":
                    out[j] = " "
            i = end
        else:
            i += 1
    return "".join(out)


COMPARISONS = [("==", "~="), ("~=", "=="), ("<=", "<"), (">=", ">"), ("<", "<="), (">", ">=")]


def candidates(line, masked, constants):
    """Yield (rule, mutated_line) for one line. `masked` is the same line, blanked."""
    # Comparison flips. Longest operators first so "<=" is not seen as "<".
    for old, new in COMPARISONS:
        start = 0
        while True:
            at = masked.find(old, start)
            if at < 0:
                break
            start = at + len(old)
            # "<=" contains "<"; skip a match that is really part of a longer operator.
            if old in ("<", ">") and masked[at:at + 2] in ("<=", ">="):
                continue
            if old == "==" and at > 0 and masked[at - 1] in "=~<>":
                continue
            yield ("cmp %s->%s" % (old, new), line[:at] + new + line[at + len(old):])

    # and / or swaps.
    for old, new in (("and", "or"), ("or", "and")):
        for m in re.finditer(r"\b%s\b" % old, masked):
            yield ("bool %s->%s" % (old, new), line[:m.start()] + new + line[m.end():])

    # Numeric bumps.
    for m in re.finditer(r"\b\d+(?:\.\d+)?\b", masked):
        text = m.group(0)
        try:
            value = float(text) if "." in text else int(text)
        except ValueError:
            continue
        for new in (value + 1, value - 1, 0):
            if new == value:
                continue
            rendered = ("%g" % new) if isinstance(value, float) else str(new)
            yield ("num %s->%s" % (text, rendered), line[:m.start()] + rendered + line[m.end():])

    # Named engine constants, swapped for another the same file uses.
    for m in re.finditer(r"\b(?:id_bhv\w+|[A-Z][A-Z0-9_]{2,})\b", masked):
        name = m.group(0)
        others = [c for c in constants if c != name]
        if not others:
            continue
        # Deterministic pick, so two runs produce the same numbering.
        new = others[sum(ord(ch) for ch in name) % len(others)]
        yield ("const %s->%s" % (name, new), line[:m.start()] + new + line[m.end():])

    # Whole-line deletion, when the line carries anything at all.
    if line.strip():
        yield ("delete line", "")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    path = sys.argv[1]
    ranges = []
    for spec in sys.argv[2:]:
        lo, hi = spec.split(",")
        ranges.append((int(lo), int(hi)))

    with open(path) as fh:
        text = fh.read()
    lines = text.split("\n")
    masked_lines = mask(text).split("\n")
    constants = sorted(set(re.findall(r"\b(?:id_bhv\w+|[A-Z][A-Z0-9_]{2,})\b", mask(text))))

    wanted = []
    for lo, hi in ranges:
        wanted.extend(range(lo, hi + 1))

    mutations, seen, dropped = [], set(), 0
    with tempfile.TemporaryDirectory() as tmp:
        probe = os.path.join(tmp, "probe.lua")
        for number in wanted:
            index = number - 1
            if index < 0 or index >= len(lines):
                continue
            line, masked = lines[index], masked_lines[index]
            for rule, mutated in candidates(line, masked, constants):
                if mutated == line:
                    continue
                key = (number, mutated)
                if key in seen:
                    continue
                seen.add(key)
                trial = list(lines)
                trial[index] = mutated
                with open(probe, "w") as fh:
                    fh.write("\n".join(trial))
                if subprocess.run([LUAC, "-p", probe],
                                  capture_output=True).returncode != 0:
                    dropped += 1
                    continue
                mutations.append({
                    "id": len(mutations) + 1,
                    "file": path,
                    "line": number,
                    "rule": rule,
                    "old": line,
                    "new": mutated,
                })

    with open(OUT, "w") as fh:
        json.dump(mutations, fh, indent=1)
    print("%d mutations over %d lines (%d dropped as uncompilable) -> %s"
          % (len(mutations), len(wanted), dropped, OUT))


if __name__ == "__main__":
    main()
