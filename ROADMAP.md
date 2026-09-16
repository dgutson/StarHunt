# Roadmap

> Pending work only — finished items move to HISTORY.md.
> This is the durable record of what's outstanding. Read it instead of reconstructing
> the state of play from git history, old conversations, or a sweep of the code.
> Next thing to work on: the first item under the earliest horizon whose **Blocked-by**
> entries are no longer present in this file.

Format: 1
Next ID: R-027

Two documents carry the detail this file deliberately omits. `DEVELOPMENT_CHECKLIST.md` holds
the process that is mandatory before editing the mod, the code map that says which module a
system lives in, and the table of already-fixed bugs whose fixes must not be undone — **read
that table first on every bugfix**, because several of those fixes look like redundant code.
`REFACTOR_PLAN.md` holds the module boundaries, the per-symbol appendix and the working rules
for every `Refactor` item; the split itself is finished, so it is now a reference rather than
a plan.

**A standing constraint on every `Refactor` item:** extract at most one module per chat
session — and that is a ceiling, not a target. When a module is large, or only part of it
can move, take the smaller piece and stop. Each extraction carries a lot of supporting work
(proving the move is byte-identical, mutation-checking the moved code, and usually writing a
new test suite because the mutation check finds the area uncovered), and several in one
session fills the context window and invites mistakes.

---

## Now

### R-019 — URGENT: three axes share one set of numbers, on a namespace named for one mode

- **Category:** Bugfix — urgent
- **What:** Two halves of one change to `modules/core.lua`, to be done together. **(a)** `Team` declared `NORMAL = 0, BOSS = 1, MODE = 2, CHAOS = 3, EASY = 0, MEDIUM = 1, HARD = 2, NIGHTMARE = 3, NONE = 0, RED = 1, BLUE = 2` flat in one table, so three unrelated axes — the mode, the difficulty and the team colour — shared their integers and passing one where another was expected matched a real member of the wrong axis. Split the names onto three tables. **(b)** `Team` is also two namespaces wearing one name: 15 of its 89 members are genuinely about Team mode (the colour axis, the rosters, the palettes, the per-team scores, the balancing) and 74 are mod-wide (the mode and difficulty axes, the language, the HUD helpers, Bowser's health, the modifier readers, Chaos, the menu, third-party compatibility). The team-mode members keep the name `Team`; the rest move to a namespace named for the mod (`SH` or `StarHunt`). The finished shape is `SH.Mode`, `SH.Difficulty` and `Team.Color`.
- **Why they are one ticket, not two:** (b) does not fix (a) on its own — the mode and the difficulty are *both* mod-wide, so splitting the namespace lands them in the same new table still sharing their numbers. And (a) alone leaves the axes on a namespace named for one mode, so `Team.Difficulty.NIGHTMARE` reads as "Team mode's difficulty". Done separately they rewrite the same references twice: (a) touches 104, (b) touches 443 including most of those 104.
- **Why the bug matters even though nothing has shipped broken:** all 104 uses were audited and every one is on its right axis, so this is latent. What it would do if it bit: `Team.NIGHTMARE` is 3 and 3 is Chaos mode, so a Normal round set to Nightmare would become a Chaos round — no star objective, everyone warped to one random course, modifiers rerolled every 15 seconds, death eliminating instead of reassigning. The reverse turns Chaos into Nightmare scaling for every player. And `Team.BOSS` is 1, which is `RED`, so a mode value reaching `sh5_team` turns on friendly fire in a mode with no teams, because `on_allow_pvp_attack` only checks that both players are on a team and differ.
- **The constraint that decides the approach:** the numbers are on the wire. `sh5_mode` and `sh5_difficulty` are synchronized, so renumbering makes a released v1.1 client and a patched one disagree about what mode a lobby is in. They are also used arithmetically — `(selected_mode() + delta) % 4` in `menu.lua`, `selected_difficulty() + 1` as a table index in `boss.lua`, `round.lua` and `hud.lua`, `clamp(..., 0, 3)` in `difficulty.lua`. **Keep every number exactly as it is**; this change is names only.
- **Half of it is already done and verified on `fix/team-axis-collision`** (commits `158fc24`, `8c5265c`, `ad48eb0`; PR #2 was closed unmerged so the whole ticket could arrive as one review). That branch has part (a): the three plain tables, all 104 use sites rewritten, four tests in `test/suite/core.lua`, and 779 passed / 0 failed with luacheck and lua-language-server at their baselines and a 41-of-41 mutation sweep. **Start from that branch rather than from `main`**, and do part (b) on top of it; redoing (a) from scratch buys nothing.
- **Three calls to make before starting (b):** (1) `Team.is_mode()` is a predicate *about* Team mode but belongs with `selected_mode`, `is_boss_mode` and `is_chaos_mode` on the mod-wide side; splitting those four apart would be worse than the name is. (2) `Team.Color` collides with `Team.colors`, the palette table, differing only in case and plural — rename the palette table in the same commit, or keep the stutter as `Team.TeamColor`. (3) Whether `core`'s return table renames its field too (`core.Team` → `core.SH`), which is read in twelve places, or only the local bindings.
- **Why (b) is mechanical:** `Team` is a **local binding** — eleven modules and `main.lua` do `local Team = core.Team`. Each file gains `local SH = core.SH` and a substitution over the members that moved. Nothing crosses a file boundary except the two field names on `core`'s return table. Both tables stay declared in `core.lua`, which requires nothing, so no module needs a new `require` edge; declaring the team side in `team.lua` would instead force `round.lua` and `hud.lua` to require it.
- **Do it in a fresh session.** Part (b) moves 443 references across every module in the mod. One commit that changes nothing but names, proven identical apart from the identifiers, with no mutation sweep because nothing behavioural changes. Every document naming `Team` and every `STARHUNT_TEST_API` key carrying a moved member goes with it.
- **Outcome:** No two axes share a name space; each namespace is named for what it holds; `core.lua`'s header no longer has to correct its own name; a test asserts the axes stay separate and that every number is the one v1.1 put on the wire. The three documented checks stay at their baselines.
- **Blocked-by:** —
- **Enables:** R-021 (which gets the axis guarantee from the compiler instead)

### R-014 — Take the bug reports and turn them into roadmap items

- **Category:** Bugfix
- **What:** The refactor is finished and merged, and the next work on this mod is corrective maintenance. There is no bug list yet — the intent is that the reports arrive at the start of a session. For each one, write a roadmap item with What / Why / Outcome, find the affected system in `DEVELOPMENT_CHECKLIST.md`'s `Mapa del código` to learn which module it lives in, and **read `Errores ya encontrados y solución que no se debe deshacer` before touching anything**: several already-fixed bugs look like redundant code and are not.
- **Why:** `PROJECT_STATUS.md` declares v1.1 final and accepts only corrective maintenance, so a bug report is the only kind of work this project takes. Writing each one down before fixing it is what stops a session from fixing the symptom it happened to notice rather than the bug that was reported.
- **Outcome:** Each reported bug is a roadmap item under Now, with the module it affects named. This item stays here and is worked through repeatedly rather than being completed once.
- **Blocked-by:** —
- **Enables:** —

### R-010 — Verify the split mod in a real sm64coopdx multiplayer session

- **Category:** Release
- **What:** Install the `StarHunt/` folder into `sm64coopdx/mods/` and play a real multiplayer session covering all four modes — Normal, Team, Boss and Chaos — with at least two players. **This one needs you at the keyboard**; no part of it can be done from a session. Copy the whole folder, not `main.lua` alone. The first thing to watch for is simply that the mod loads at all: if a `require` fails, sm64coopdx reports it at load time and nothing else in this list matters.
- **Why:** Nothing automated reaches rendering, networking, warping, collision or interaction with other mods, and `PROJECT_STATUS.md` is explicit that the validation does not cover them. The refactor changed how the mod is loaded — one file became fourteen, resolved through sm64coopdx's own folder-relative `require` — and that is precisely the mechanism no test can exercise, since `test/harness.lua` reimplements `require` rather than using the game's.
- **Outcome:** All four modes have been played end to end from the split mod, and the load order, warping and HUD behave as they did from the single released file.
- **Blocked-by:** —
- **Enables:** —

## Next

### R-012 — Split `modules/round.lua`, now the largest file in the mod

- **Category:** Refactor
- **What:** `round.lua` is 1,079 lines — larger than `goals.lua` (890), larger than `modifiers.lua` (841), larger than `hud.lua` (708), and two and a half times `main.lua` (420), which is now finished. Split it. The cut is the one the file documents in its own header: the host half (89-786) and the client half (787-1079) meet through the synchronized tables and, since the client half of the loop moved in, at exactly one other point (re-derive both ranges with grep; they have shifted three times already). So they can become `round_host.lua` and `round_client.lua` with no shared state to arrange, but the cut is **no longer free**: `on_before_boss_cutscene` is in the client half and calls `host_end_round` behind a `network_is_server()` check. `round_client` requiring `round_host` is the obvious answer and adds no cycle — nothing requires `round` — but decide it deliberately rather than discovering it half way through. Measure both the ranges and that one call again before acting on this line. Note also that the cut as it stands does **not** reach the outcome below: the halves are roughly 700 and 290, so getting the host half under 600 needs the second cut described next, in its own verified commit first. Splitting the host half any further is a different job and needs the migration step first: `host_start_round` rebinds `host_used_goals`, `host_seen_done` and `host_seen_forfeit`, which `host_pick_goal`, `host_prepare_player` and `host_update_round` all read, so those three tables have to move onto a shared table before the functions can live in separate files — exactly what was done for `host_player_records` in R-001, and in its own verified commit before anything moves.
- **Why:** The file got large for a reason that no longer applies. Its two halves were extracted in separate passes months apart, and the second one landed in the file the first had created because that was where the name `round` already lived — not because the two belong in one file. They are the two sides of the mod's host-authority rule and share nothing, which is the clearest possible sign they are two units. Being the largest file in the mod also makes it the most expensive one to read at the start of a session, which is the cost the whole split exists to reduce.
- **Outcome:** Neither half of the round is larger than roughly 600 lines; the host and client sides are separate files; every move is proven byte-identical in both directions and the 767 tests still pass. (`goals.lua` is now 890 lines and the second-largest file in the mod. Whether it wants the same treatment is a separate question this item does not answer.)
- **Blocked-by:** —
- **Enables:** —

### R-005 — Move the suite onto a Lua test framework

- **Category:** Testing
- **What:** Replace the hand-rolled `test/runner.lua` (102 lines: suite registration, six assertions, one `pcall` per test) with an established framework — busted is the obvious candidate, with luassert for assertions. This requires first pointing `luarocks` at Lua 5.4: it is installed at `/usr/bin/luarocks` but bound to **Lua 5.1** with zero rocks installed, while the mod needs 5.4 for its bitwise operators. Keep `test/harness.lua` and `test/engine_stub.lua` as they are — the engine doubling is the part no framework replaces.
- **Why:** The current runner works but gives nothing beyond pass/fail: no setup/teardown, no tags or filtering beyond a substring match on the suite name, no randomized order, and no route to coverage tooling. A framework is also what makes R-008 cheap rather than bespoke.
- **Outcome:** The suite runs under a standard framework, all 670 tests still pass, and the project no longer maintains its own test runner.
- **Blocked-by:** —
- **Enables:** R-008

### R-006 — Measure coverage with luacov

- **Category:** Testing
- **What:** Add luacov and produce a coverage report for `StarHunt/`. This does not require R-005: luacov runs against the existing runner via `lua5.4 -lluacov test/run.lua`.
- **Why:** Coverage is currently established by hand, one module at a time, by mutating the moved code and checking whether the suite notices. That has found a real gap in nine of the twelve extraction passes so far — most severely in round's host half, where 139 of 156 mutations survived a green 212-test run, and in chaos, where all 17 survived and `Team.update_chaos_warp` was published in `STARHUNT_TEST_API` and called by no test at all. Manual mutation testing works but costs a large part of every extraction session and only ever covers the lines that just moved.
- **Outcome:** A coverage report exists for the whole mod, naming the untested areas that nobody has thought to mutate yet.
- **Blocked-by:** —
- **Enables:** —

### R-007 — CI pipeline running the test suite on every push

- **Category:** CI
- **What:** Add a CI workflow that installs `lua5.4` and runs `lua5.4 -e "assert(loadfile('StarHunt/main.lua'))"` followed by `lua5.4 test/run.lua`, failing the build on a non-zero exit. The suite has no third-party dependencies, so this stage needs nothing but a Lua 5.4 interpreter.
- **Why:** Every check in this project currently runs only when someone remembers to run it on this one machine, and the refactor is 28 unpushed commits deep on `refactor/modularize` with the test suite as its only safety net. A mutation was once left applied to `modules/modifiers.lua` and a full green run did not notice, which is exactly the class of mistake a pipeline catches at push time rather than three sessions later.
- **Outcome:** Every push to the repository runs the load check and the full test suite, and a red build is visible without anyone running anything locally.
- **Blocked-by:** —
- **Enables:** R-009, R-020

### R-020 — Add the Teal compiler to the pipeline and decide what it compiles

- **Category:** CI
- **What:** With a pipeline in place, add a stage that installs the Teal compiler (`luarocks install tl`; `tl` is not on this machine, luarocks 3.8.0 is, and the current release is 0.24.8 from October 2025), add a `tlconfig.lua` that points `global_env_def` at the engine declaration file, compile the `.tl` sources, and **fail the build if the committed `.lua` differs from what the compiler produces**. No module is migrated by this item.
- **Why:** Everything Teal-shaped below depends on a build step, and this project's defining property is that it has none. The mod folder is a strict boundary — sm64coopdx loads every `.lua` under `StarHunt/` recursively — so compiler output has to land exactly there while the `.tl` sources live outside it. A release is identified by the SHA-256 of the shipped `.lua` files, which would then be a hash of generated code, and the only thing keeping that honest is a job proving the committed output matches the sources. Without it, a hand-edit to a generated file is invisible.
- **Also to settle here, before any module moves:** whether `tools/gen_mutations.py` mutates the `.tl` sources and recompiles, or mutates the shipped `.lua`. Every line range in `DEVELOPMENT_CHECKLIST.md`'s process refers to a file that would no longer be the one the tests load.
- **Outcome:** CI installs `tl`, compiles the sources, and diffs the result against what is committed. The mutation question is answered in writing. No `.tl` file exists yet beyond whatever the stage needs to prove itself.
- **Blocked-by:** R-007
- **Enables:** R-021, R-022, R-023, R-024, R-025

## Later

### R-021 — Migrate `modules/core.lua` to Teal, starting with the three enums

- **Category:** Refactor
- **What:** `core.lua` requires nothing, so it is the one module that can move on its own. Convert it to `core.tl` and declare the mode, difficulty and team axes as three Teal enums, which are nominal and mutually unassignable. R-019 splits the names apart, so a name off the wrong axis reads as `nil`, but the three stay sets of plain integers: nothing stops a difficulty *value* being passed where a mode is expected. That last step is what the compiler adds.
- **Why:** This is the largest single win the language offers this codebase, and `core.lua` is where it lives. It is also the smallest possible first migration, which is what makes it the right one to learn the build on.
- **The catch, which this item must resolve rather than discover:** Teal enums are **string** values only — confirmed against the current documentation, not recalled. The mod's modes and difficulties are integers that are synchronized between players and used arithmetically (`% 4` when cycling, `+ 1` as a table index, `clamp(..., 0, 3)`). So either the wire format changes to strings, which breaks a mixed-version lobby, or the sync tables keep carrying integers and the enum is converted at the boundary, which means two representations and a conversion that can itself be wrong. Decide this before writing any `.tl`.
- **Outcome:** `core.tl` compiles to a `core.lua` byte-identical in behaviour, the three axes are distinct enum types, the 775 tests pass against the compiled output, and the wire format question is answered in writing.
- **Blocked-by:** R-020
- **Enables:** R-023, R-024, R-025

### R-022 — Declare the two sync tables in a `.d.tl`

- **Category:** Refactor
- **What:** Write a declaration file giving `gGlobalSyncTable` and `gPlayerSyncTable` record types covering the 60 distinct `sh5_` fields, and load it with `global_env_def` in `tlconfig.lua` — the mechanism LÖVE uses for its predefined globals.
- **Why:** This is the largest class of mistake the language could catch here. Those 60 fields are read and written at 355 places by name, and a typo creates a new field, writes to it, and reads back `nil` for the rest of the round. Neither luacheck nor lua-language-server can see it, because the tables are engine-provided and open to any key, so nothing in the current toolchain covers this at all.
- **Known hole, worth recording rather than rediscovering:** the Boss attack queue is read as `gGlobalSyncTable["sh5_boss_attack_queue_" .. tostring(slot)]` in `boss.lua:368` and seeded the same way in `main.lua:406`. A constructed key cannot be checked by a record type, so the eight queue slots stay unprotected whatever this item does.
- **Outcome:** Both sync tables have record types, the declaration is generated or checked against the fields the mod actually uses, and a deliberately misspelled field fails the build.
- **Blocked-by:** R-020
- **Enables:** —

### R-023 — Migrate `modules/i18n.lua` and make the complete dictionaries `<total>`

- **Category:** Refactor
- **What:** Convert `i18n.lua` and mark `Team.boss_modifier_translations` and `Team.modifier_translations` as `<total>` maps keyed by an enum of the twelve Boss modifier kinds and the six language codes, so a missing translation fails the build.
- **Why:** Adding a modifier today means remembering to add its twelve translations by hand, and a forgotten one shows up as English at runtime, in a language the author probably does not read. `<total>` is a Teal-specific attribute that forces every key of an enum-keyed map to be present.
- **Careful:** this is right for the modifier and Boss dictionaries, which are meant to be complete, and **wrong** for star titles, which fall back to English deliberately — only text with a safe translation is localized. Do not make that one total.
- **Blocked-by:** R-020, R-021
- **Enables:** —

### R-024 — Migrate the difficulty-keyed lookup tables in `boss.lua` and `round.lua`

- **Category:** Refactor
- **What:** Convert the tables that hold one value per difficulty or per attack — `attack_intervals` and `difficulty_factors` in `round.lua:684` and `:690`, Bowser's `{ 3, 5, 7, 9 }` health in `boss.lua:113`, the difficulty names in `hud.lua:574` — into `<total>` maps keyed by the enums from R-021.
- **Why:** Each of these currently ends in `or <default>`, so a difficulty with no entry is indistinguishable from one that deliberately takes the default. A `<total>` map makes a missing case a compile error instead.
- **Blocked-by:** R-020, R-021
- **Enables:** —

### R-025 — Migrate `modules/goals.lua` and `modules/audit.lua` to record types

- **Category:** Refactor
- **What:** Give the goal and the modifier record types — `goal(level, act, title, title_es, mods, power)` at `goals.lua:61` and `modifier(kind, value, label)` at `core.lua:143` — and let the 93 goals and 32 modifiers be checked against them.
- **Why:** It is the last place in the mod with a repeated hand-built shape, 93 times over. Expect a smaller gain than the others: lua-language-server already infers part of this from the constructors, and `rebuild_audited_modifiers` replaces every goal's `mods` wholesale at load time, which is a runtime rewrite no type system observes.
- **Blocked-by:** R-020, R-021
- **Enables:** —

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
