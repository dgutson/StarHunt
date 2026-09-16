#!/usr/bin/env python3
"""What a module still needs from main.lua, before extracting it.

    python3 tools/module_deps.py 73,79 301,346 1137,1164

Give it the line ranges (inclusive, 1-based) of the blocks a module is about to
take.  It prints every top-level name declared in StarHunt/main.lua that those
blocks reference, marking each one DEP (still in main.lua, or already an import)
or SELF (declared inside the ranges themselves).

Read the output like this:

  * A DEP whose declaration line is one of main.lua's `local x = require(...)`
    import lines is already satisfied -- the new module requires the same thing.
  * Any other DEP is a real blocker: that name is still a top-level local of
    main.lua and the new module cannot see it.  Either it belongs in the module
    too, or it belongs in core.lua, or the module has to wait for whichever
    module owns it.
  * `SH.x` and `Team.x` fields never appear here and never block anything.
    Every module reaches the same two tables by reference, so a function
    assigned onto either in one module is visible from all of them.

This exists because REFACTOR_PLAN.md's per-symbol appendix is machine-derived
and has been wrong about real dependencies more than once.  Running the scan
showed `modifiers` was blocked on exactly three names rather than the dozen the
appendix implied, and that `chaos` was blocked on one function rather than the
whole of round.  Do not guess from the appendix; measure.

Ranges go stale the moment anything is edited, so re-derive them with grep
immediately before running this, never by arithmetic on earlier numbers.
"""

import re
import sys
import os

MAIN = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "StarHunt", "main.lua")


def top_level_declarations(lines):
    """Name -> line number, for every top-level `local` in main.lua.

    Only column-0 declarations count: anything indented is inside a function and
    is not a name another module could ever reach.
    """
    decls = {}
    patterns = (r'^local function ([A-Za-z_]\w*)',
                r'^local ([A-Za-z_]\w*)\s*=',
                r'^local ([A-Za-z_]\w*)\s*$')
    for number, line in enumerate(lines, 1):
        for pattern in patterns:
            match = re.match(pattern, line)
            if match:
                decls[match.group(1)] = number
                break
    return decls


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    try:
        ranges = [tuple(int(part) for part in arg.split(",")) for arg in argv]
    except ValueError:
        print("ranges must be written as first,last -- e.g. 301,346")
        return 1

    lines = open(MAIN).read().split("\n")
    decls = top_level_declarations(lines)

    body = []
    for first, last in ranges:
        body.extend(lines[first - 1:last])
    body_text = "\n".join(body)

    print("%s: %d top-level locals; scanning %d lines in %d blocks"
          % (MAIN, len(decls), len(body), len(ranges)))

    for name, declared_at in sorted(decls.items(), key=lambda item: item[1]):
        if not re.search(r'\b' + re.escape(name) + r'\b', body_text):
            continue
        inside = any(first <= declared_at <= last for first, last in ranges)
        source = lines[declared_at - 1]
        note = "  <- already an import" if "require(" in source else ""
        print("  %5d  %s  %s%s"
              % (declared_at, "SELF" if inside else "DEP ", name, note))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
