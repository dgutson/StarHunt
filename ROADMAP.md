# Roadmap

> Pending work only — finished items move to HISTORY.md.
> This is the durable record of what's outstanding. Read it instead of reconstructing
> the state of play from git history, old conversations, or a sweep of the code.
> Next thing to work on: the first item under the earliest horizon whose **Blocked-by**
> entries are no longer present in this file.

Format: 1
Next ID: R-012

Two documents carry the detail this file deliberately omits. `REFACTOR_PLAN.md` holds the
module boundaries, the extraction order, the per-symbol appendix and the working rules for
every `Refactor` item below. `DEVELOPMENT_CHECKLIST.md` holds the process that is mandatory
before editing `StarHunt/main.lua`, including the table of already-fixed bugs whose fixes
must not be undone.

**A standing constraint on every `Refactor` item:** extract at most one module per chat
session — and that is a ceiling, not a target. When a module is large, or only part of it
can move, take the smaller piece and stop. Each extraction carries a lot of supporting work
(proving the move is byte-identical, mutation-checking the moved code, and usually writing a
new test suite because the mutation check finds the area uncovered), and several in one
session fills the context window and invites mistakes.

---

## Now

### R-001 — Extract `modules/round.lua`

- **Category:** Refactor
- **What:** Move the round loop out of `StarHunt/main.lua` into `StarHunt/modules/round.lua` — 45 top-level declarations, roughly 796 lines, including `host_start_round`, `host_end_round`, `host_update_round`, `host_add_late_joiner`, `remember_player_index`, `host_assign_goal`, `host_prepare_player` and `force_return_to_lobby`. Run `python3 tools/module_deps.py <first,last> …` over the declarations first, re-deriving every line range with grep immediately beforehand; do not trust the per-symbol appendix in `REFACTOR_PLAN.md`, which is machine-derived and has been wrong about real dependencies more than once. Expect this to need two or three sessions under the one-module-per-session ceiling.
- **Why:** Round is the largest remaining module and the blocker for everything else in the split. Four already-extracted modules each left a part behind that calls into it: `goals.lua`, `team.lua`, `boss.lua` and `chaos.lua` (see R-002). `team.lua` in particular cannot be finished by re-localizing, because its three missing functions read `host_player_records`, which round **rebinds** (`host_player_records = {}`) — and Lua copies a value on `local x = other.x`, so a rebound top-level local cannot be shared across modules at all.
- **Outcome:** The round loop lives in `modules/round.lua`; `main.lua` is roughly 800 lines shorter; the moved lines are proven byte-identical in both directions, and every mutation tried against them is caught by a test.
- **Blocked-by:** —
- **Enables:** R-002

## Next

### R-002 — Finish the deferred halves of goals, team, boss and chaos

- **Category:** Refactor
- **What:** Move the parts left behind when four modules were extracted in two passes. `goals.lua` needs the interaction handlers (`on_allow_interact`, `on_interact`), star visibility, the power flags (`apply_goal_power`, `restore_starhunt_power`, `power_flags`) and `run_static_modifier_checks`. `team.lua` needs `participant_stats`, `pick_late`, `update_scores` and `update_manual_reroll_menu`, plus `TEAM_SCORE_PRIORITY_GAP`, which belongs with `pick_late`, its only caller. `boss.lua` needs the round loop, the attack queue and the hazards. `chaos.lua` needs `Team.host_update_chaos_round`, measured as depending on exactly `host_end_round`, `remember_player_index` and `host_add_late_joiner`.
- **Why:** Each of these was left in `main.lua` because it calls into the round loop, and passing those functions in as parameters would hide a real dependency in order to preserve an arbitrary extraction order. Until they move, four modules are misleadingly incomplete — a reader looking for Chaos's round handling finds it in `main.lua`, not in `chaos.lua`.
- **Outcome:** No module owns code that still lives in `main.lua`; `main.lua` holds only the Co-op DX metadata header, the `require` wiring, the flat hook-registration block and the `STARHUNT_TEST_API` table.
- **Blocked-by:** R-001
- **Enables:** R-010

### R-003 — Extract `modules/hud.lua`

- **Category:** Refactor
- **What:** Move the HUD drawing code out of `main.lua` into `StarHunt/modules/hud.lua` — around 31 declarations and 601 lines. Run the dependency scan first: whether round actually blocks this is unmeasured, and `REFACTOR_PLAN.md` says plainly that the leaf-first order past the modules already extracted was never validated against real dependencies.
- **Why:** HUD drawing is the second-largest block left in `main.lua`, and its heaviest couplings — `hud → i18n` at 51 references, `hud → team` at 26, `hud → modifiers` at 22 — are all to modules that are already out, so it may be readier than its position in the planned order suggests. It also carries the colon rule that is easy to break again: `FONT_HUD` renders `:` as an `X`, so nothing may call `djui_hud_print_text` on text containing a colon; it must go through `draw_hud_text` / `measure_hud_text`.
- **Outcome:** HUD drawing lives in `modules/hud.lua`, with the colon rule documented at the top of the file where the next person to add a string will see it.
- **Blocked-by:** —
- **Enables:** R-004

### R-004 — Extract `modules/menu.lua`, and settle the five unplaced declarations

- **Category:** Refactor
- **What:** Move the config menu into `StarHunt/modules/menu.lua` — around 18 declarations and 250 lines. Decide at the same time whether `draw_config_menu` belongs in `menu` rather than `hud`, where the plan's appendix put it purely because its name starts with `draw_`. Then give the five declarations that have no assigned module a home: `remove_castle_lakitu`, `remove_existing_castle_lakitu`, `local_lakitu_scan_at`, `on_find_water_level` and `gServerSettings.skipIntro`.
- **Why:** Menu is the last module in the planned split, and the five unplaced declarations are the only ones the whole planning pass could not assign — leaving them in `main.lua` by default would be a decision made by omission rather than on purpose.
- **Outcome:** All thirteen modules exist; every top-level declaration in the released file has a deliberate home; the split is structurally complete.
- **Blocked-by:** R-003
- **Enables:** R-010

### R-005 — Move the suite onto a Lua test framework

- **Category:** Testing
- **What:** Replace the hand-rolled `test/runner.lua` (102 lines: suite registration, six assertions, one `pcall` per test) with an established framework — busted is the obvious candidate, with luassert for assertions. This requires first pointing `luarocks` at Lua 5.4: it is installed at `/usr/bin/luarocks` but bound to **Lua 5.1** with zero rocks installed, while the mod needs 5.4 for its bitwise operators. Keep `test/harness.lua` and `test/engine_stub.lua` as they are — the engine doubling is the part no framework replaces.
- **Why:** The current runner works but gives nothing beyond pass/fail: no setup/teardown, no tags or filtering beyond a substring match on the suite name, no randomized order, and no route to coverage tooling. A framework is also what makes R-008 cheap rather than bespoke.
- **Outcome:** The suite runs under a standard framework, all 154 tests still pass, and the project no longer maintains its own test runner.
- **Blocked-by:** —
- **Enables:** R-008

### R-006 — Measure coverage with luacov

- **Category:** Testing
- **What:** Add luacov and produce a coverage report for `StarHunt/`. This does not require R-005: luacov runs against the existing runner via `lua5.4 -lluacov test/run.lua`.
- **Why:** Coverage is currently established by hand, one module at a time, by mutating the moved code and checking whether the suite notices. That has found a real gap in eight of the ten modules extracted so far — most severely in chaos, where all 17 mutations survived a green 138-test run and `Team.update_chaos_warp` was published in `STARHUNT_TEST_API` and called by no test at all. Manual mutation testing works but costs a large part of every extraction session and only ever covers the lines that just moved.
- **Outcome:** A coverage report exists for the whole mod, naming the untested areas that nobody has thought to mutate yet.
- **Blocked-by:** —
- **Enables:** —

### R-007 — CI pipeline running the test suite on every push

- **Category:** CI
- **What:** Add a CI workflow that installs `lua5.4` and runs `lua5.4 -e "assert(loadfile('StarHunt/main.lua'))"` followed by `lua5.4 test/run.lua`, failing the build on a non-zero exit. The suite has no third-party dependencies, so this stage needs nothing but a Lua 5.4 interpreter.
- **Why:** Every check in this project currently runs only when someone remembers to run it on this one machine, and the refactor is 28 unpushed commits deep on `refactor/modularize` with the test suite as its only safety net. A mutation was once left applied to `modules/modifiers.lua` and a full green run did not notice, which is exactly the class of mistake a pipeline catches at push time rather than three sessions later.
- **Outcome:** Every push to the repository runs the load check and the full test suite, and a red build is visible without anyone running anything locally.
- **Blocked-by:** —
- **Enables:** R-009

## Later

### R-008 — Randomize suite order to prove the suites are independent

- **Category:** Testing
- **What:** Run the suites in a randomized order (busted's `--shuffle`, if R-005 adopts it) and fix whatever that breaks.
- **Why:** Several suites call `math.randomseed(...)` at global scope — `test/suite/team.lua` at lines 48, 71 and 96, and `test/suite/chaos.lua` at 94, 105, 129 and 220 — so each one changes the random sequence every later suite draws from. Today that is known-harmless only because `test/suite/round.lua` was checked to pass both alone and after `chaos`. Nothing proves it stays that way, and an order-dependent suite fails in the worst way: intermittently, and only for whoever happens to run it differently.
- **Outcome:** The suite passes in any order, and cross-suite coupling through the global random seed is either removed or proven not to exist.
- **Blocked-by:** R-005
- **Enables:** —

### R-009 — Make the engine definitions reproducible, and add the lint stages to CI

- **Category:** CI
- **What:** Get the sm64coopdx API definitions into a form a CI runner can obtain, then add `luacheck StarHunt/ test/` and `lua-language-server --check <repo> --checklevel=Warning` as pipeline stages. Either vendor the generated files into the repository outside `StarHunt/`, or have CI run the equivalent of `~/.local/share/sm64coopdx/refresh.sh` against a pinned sm64coopdx version.
- **Why:** Both linters are useless without the engine API: `main.lua` calls about 59 engine functions and reads roughly 1,090 engine constants, which are undefined globals otherwise. Those definitions live in `~/.local/share/sm64coopdx/` on this machine only — deliberately outside the repo, because the game loads every `.lua` file it finds in a mod directory — and `.luacheckrc` reads `~/.local/share/sm64coopdx/luacheck_globals.lua` by absolute path. A fresh CI runner has none of it. Pinning the version is the point as much as availability: the checkers are only meaningful against the engine version being targeted.
- **Outcome:** CI runs luacheck and lua-language-server against a known sm64coopdx version, holding the baseline of 2 luacheck warnings / 0 errors and 10 type-checker problems in 2 files. A rise in either fails the build.
- **Blocked-by:** R-008
- **Enables:** —

### R-010 — Verify the split mod in a real sm64coopdx multiplayer session

- **Category:** Release
- **What:** Install the `StarHunt/` folder into `sm64coopdx/mods/` and play a real multiplayer session covering all four modes — Normal, Team, Boss and Chaos — with at least two players.
- **Why:** Nothing automated reaches rendering, networking, warping, collision or interaction with other mods, and `PROJECT_STATUS.md` is explicit that the validation does not cover them. The refactor changed how the mod is loaded — one file became thirteen, resolved through sm64coopdx's own folder-relative `require` — and that is precisely the mechanism no test can exercise, since `test/harness.lua` reimplements `require` rather than using the game's.
- **Outcome:** All four modes have been played end to end from the split mod, and the load order, warping and HUD behave as they did from the single released file.
- **Blocked-by:** R-002, R-004
- **Enables:** R-011

### R-011 — Reconcile the release documents and open the pull request

- **Category:** Release
- **What:** Recompute `sha256sum StarHunt/main.lua` and update the recorded hash in `PROJECT_STATUS.md`, which still carries the released v1.1 value `EBC76DBE…A906B883`. (`DEVELOPMENT_CHECKLIST.md` no longer carries a live copy — its verification record moved to `HISTORY.md`, where the released hash correctly stays as a historical fact.) Change the install instructions everywhere from "copy `main.lua`" to "copy the `StarHunt/` folder". Update `CLAUDE.md`'s "Known-clean baseline" section with the new luacheck and type-checker numbers, the `different-requires` entry in `.luarc.json`, the fact that the 24 `shadowing upvalue goal` warnings are gone with the `goal()` constructor, and the new `tools/module_deps.py`. `CLAUDE.md` also still describes `tools/` as holding only "generators for the test stub and linter data". Then push `refactor/modularize` and open the PR.
- **Why:** The hash reconciliation was deliberately deferred rather than done per commit: the line in `PROJECT_STATUS.md` reads "SHA-256 final de `main.lua`" and describes what shipped as v1.1, so rewriting it on every commit of an unmerged branch would misstate the release. It has to happen exactly once, at merge. Nothing on the branch has been pushed, so none of this work exists anywhere but this machine.
- **Outcome:** The project documents describe the mod as it is actually shipped and installed; the branch is pushed; the PR is open.
- **Blocked-by:** R-010
- **Enables:** —
