# `test/live/without/` — proving the harness can still fail

A green run is worth exactly what its ability to go red is worth, so the harness has to be
able to run against a StarHunt with one fix taken out. It does that **without touching the
working tree**: `run.sh` already copies `StarHunt/` into each instance's own `mods/` folder,
so `--without <name>` edits those copies, after the copy and before the game starts.
`tools/sweep_mutations.py` follows the same rule for the same reason — a run killed halfway
through leaves a half-applied edit behind when it edits in place.

Each `<name>.txt` here is one named removal:

- the **first line** is the path inside `StarHunt/` to edit,
- **everything after it** is the exact block of Lua to delete, indentation included.

`run.sh` fails the run if that block is not found in the file, exactly once. That matters more
than it looks: if the code drifts and the removal silently does nothing, the falsification
check quietly becomes a tautology, which is the one failure this whole directory exists to
prevent.

| name | removes | the case it must turn red |
|---|---|---|
| `crossact` | the `core.enable_cross_act_players(gLevelValues)` call in `main.lua` | `split` |

To add one: write the block into `<name>.txt`, then give `run.sh` the case it is expected to
break, in the `WITHOUT_CASE` table beside the verdict block.
