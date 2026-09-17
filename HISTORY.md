# History

> Completed work, newest first. `ROADMAP.md` holds what is still pending.

This file exists so the living documents stay small. A document that is read at the start of
every session costs context every time, so finished work is moved here rather than
accumulating in `ROADMAP.md`, `REFACTOR_PLAN.md` or `DEVELOPMENT_CHECKLIST.md`.

Two kinds of record live here: completed roadmap items at the top, and below them the
development history inherited from v0.9 to v1.1, which predates the roadmap.

---

## Completed roadmap items

### 2026-09-17 — R-031: Dire Dire Docks is one world, whatever act a player was sent to

`players_have_private_variant` hid two players from each other, and refused the contact
between their bodies, whenever they held different DDD acts and either one was within 4600
units of the submarine. Nothing in the course is act-gated except the manta ray
(`levels/ddd/script.c:31`). The submarine, its door and the nine poles all test
`SAVE_FLAG_HAVE_KEY_2 | SAVE_FLAG_UNLOCKED_UPSTAIRS_DOOR` — `bhv_bowsers_sub_loop`
(`src/game/behaviors/ddd_sub.inc.c:4`) deletes the submarine once the flag is set and
`bhv_ddd_pole_init` (`src/game/behaviors/ddd_pole.inc.c:3`) deletes each pole until it is —
and the save file is common to the session: `packet_join.c:103-129` sends the host's whole
512-byte EEPROM to each joiner, `ultra_reimplementation.c:128` makes the client read from that
buffer instead of its own file, and `save_file.c:656-666` and `:707-721` broadcast every later
flag change. So every player in DDD sees the same submarine and the same poles.

`is_ddd_sub_zone` and the DDD branch are gone. The zone was also measured for geometry that
lives elsewhere: the submarine and the poles are in area 2, and the pole cluster reaches
x = 5760, outside the 4600-unit radius the zone tested.

`test/suite/world.lua` gained "Dire Dire Docks is one world for every act", which fails
against the previous code. Its last assertion also holds a DDD pair in deep water at
coordinates inside the box `is_jrb_ship_zone` tests, so a zone belonging to one level cannot
be reached from another.

786 passed / 0 failed, luacheck 2 warnings / 0 errors in 47 files, lua-language-server 10
problems in 2 files, `test/live/run.sh` PASSED with its six verdicts. Mutation sweep over
`players_have_private_variant`: 46 of 110 caught, against 44 of 119 on `main` — the survivors
are the BBH, WF and JRB branches, untested before and after, which R-028 replaces.

### 2026-09-17 — R-032: the live harness measures a collision, and says what it is measuring

`test/live/` booted, loaded StarHunt, started a real round and warped both players, but its
collision measurement was empty: the control pair that had to be pushed apart was not, and the
case under test stayed green with the R-030 branch deleted. The leading theory was that writing
`m.pos` from Lua moves a player locally without the engine transmitting the position. That was
wrong. `network_update_player` sends at least every third tick whatever moved the player, so a
teleport is transmitted like anything else.

The real cause was one flag. `gServerSettings.headlessServer` is set when a process is started
with both `--headless` and `--server` (`src/pc/network/network.c:140`), and it makes that
process's own player inert twice over: `network_update_player`
(`src/pc/network/packets/packet_player.c:430`) returns before sending its position, so every
client sees the host frozen where it first appeared, and `is_player_active`
(`src/game/obj_behaviors.c:547`) returns false for the server's player on **every** instance,
which is the first question `interact_player` asks about both bodies. A headless host can
referee a round but can never touch anybody, so the harness now runs a dedicated headless
server and **two** headless clients, and measures the collision between the two clients.

Two further traps were in the measurement itself. `resolve_player_collision` pushes along the
vector between the two torsos, so a pair placed at exactly the same point has a zero direction
and nobody moves however willing the engine is — the players are now placed 20 units apart. And
two players on different acts never exchange positions at all, because `network_receive_player`
drops a packet whose course, act, level or area does not match, so the meeting point travels
through the sync table rather than through the other player's body.

**The case that had been called `isolated` was measuring the engine, not the mod.** StarHunt
warps with `warp_to_level(goal.level, 1, goal.act)`, that act becomes the player's `currActNum`,
and `is_player_active` refuses any remote player whose act differs — so two players on TTC acts
6 and 1 are kept apart by Co-op DX before StarHunt is consulted. The run is now three cases:
`split` records that (it cannot fail, and says so), `shared` is the control, and a new `hidden`
case is the one that tests R-030 — the second player warps itself back into the first one's act
without its goal changing, so both `currActNum` agree and the engine is willing while
`players_have_private_variant`, which reads the assigned goals, still calls the pair private.

That arrangement is not artificial: `NEXT_GOAL_DELAY` is 90 frames, so a player who has just
been given a different act of the level they are standing in stays in exactly that state for
three seconds, next to whoever else is there.

Measured, in a real three-process run: `shared` pushed apart to 74.3 with a drift of 54.0,
`hidden` held at the 20 units it was placed at with a drift of 0.0, `split` never touching at
all with `active_them=0`. With the four-line `INTERACT_PLAYER` branch deleted from
`modules/goals.lua`, `hidden` turns red at `drift=47.3 reach=84.7` while `split` and `shared`
do not move. **So the live harness now confirms R-030, and fails when R-030 is removed.**

785 passed / 0 failed, luacheck 2 warnings / 0 errors in 47 files, lua-language-server 10
problems in 2 files. The mod itself is unchanged; the whole item is in `test/live/`. Not
covered, as ever: rendering, anything a person has to look at, real latency, and third-party
mods.

### 2026-09-17 — `PROJECT_STATUS.md` retired

The document mixed four unrelated things: a claim that the project was closed, a register of
tree hashes, a second copy of the release notes, and a list of which version folders existed
on one machine. Most of it had gone stale — it still called the modular mod unplayed, still
counted 780 tests, and still declared a closure that the act-divergence work has since
overtaken.

What was worth keeping moved rather than disappearing. The two hashes that identify a
published build — the single-file v1.1 and the file-set v1.1.1 — are now in *Lo que se
publicó, y su hash* below; the five intermediate tree hashes were dropped, because none of
them was published and the command recomputes any of them from the commit that carries it.
Everything else was already somewhere better: the installation rule is in `CLAUDE.md` and
`CHANGELOG.md`, the per-update notes are in `CHANGELOG.md`, and the limits of the automated
validation are in `CLAUDE.md`, `test/README.md` and roadmap item R-010.

`CLAUDE.md`, `ROADMAP.md` (R-014 and R-010) and `test/suite/catalog.lua` cited the file and
now state the fact instead.

The closure statement was not moved anywhere. StarHunt is under active development and takes
both bug fixes and new features; what it is working on is `ROADMAP.md`, and what it has done
is this file. Every statement of a development status is therefore gone from the documents
that carried one: the closure paragraph in `CLAUDE.md`, the *Estado del proyecto: FINALIZADO*
header and the no-new-versions paragraph in `DEVELOPMENT_CHECKLIST.md`, the *Versión final del
proyecto* line in `CHANGELOG.md`, the *Final project audit* line and the *Known limits at
project closure* heading in `BALANCE_AUDIT.md`, and the two sentences in R-014 that described
the project's phase rather than the practice being asked for. Dated entries in this file that
record what was declared at the time are left as written.

### 2026-09-17 — R-030: a player hidden for an incompatible world is no longer solid

StarHunt sends each player to their own star with `warp_to_level(goal.level, 1, goal.act)`, so
two players can stand in one course and area on different acts, with geometry that does not
agree. `players_have_private_variant` decides when that is true, and the mod answered it in two
places: `update_private_player_visibility` set `GRAPH_RENDER_INVISIBLE` on the other player's
Mario, and `on_allow_pvp_attack` refused the damage. Nothing stopped the two bodies touching.
`modules/round.lua:511` sets `gServerSettings.playerInteractions` to `PLAYER_INTERACTIONS_PVP`
for the whole round, so `interact_player` still reached `resolve_player_collision` and the
hidden player stayed an invisible wall to bump into and stand on.

The refusal went into `on_allow_interact` in `modules/goals.lua`, which already hooks
`HOOK_ALLOW_INTERACT`. Verified in the engine's own source rather than its documentation:
`interact_player` (`src/game/interaction.c`) is the only caller of `resolve_player_collision`,
and `mario_process_interactions` calls the hook for `INTERACT_PLAYER` before the handler and
lets remote players reach it. The check sits immediately after the round-active test, above the
per-mode branches, so the collision answer and the visibility answer come from the same
predicate for the same pair; Boss and Chaos exempt themselves through the predicate, Boss
because a boss round leaves every `sh5_goal` at 0.

`player_index_of_body` names the player an interaction object belongs to. The first version
walked `gMarioStates` comparing `marioObj`, the way the engine itself finds the other player;
the reviewer asked whether the walk was worth its cost, and it was not: the engine writes the
owner onto every Mario object once per frame in `bhv_mario_update`, and
`network_local_index_from_global` is arithmetic rather than a search, so
`SH.local_index_from_global(object.globalPlayerIndex)` answers in constant time. The single
comparison back against that player's own `marioObj` is what keeps it exact, because an
ordinary object carries `globalPlayerIndex` 0 and would otherwise read as the host's body. The
constant-time version also mutation-tested better: the walk left six survivors, all in its loop
bounds; the lookup left none.

The defect shipped in released v1.1 — `v1.1-monolithic` contains the predicate and its two
consumers and no mention of `INTERACT_PLAYER` — so it was not introduced by the modular split.

Four tests in `test/suite/world.lua` cover it: a hidden pair refused in both directions, a
shared pair still touching, the refusal ending with the round, and an object that is no
player's body left alone. 784 passed / 0 failed, luacheck 2 warnings / 0 errors in 46 files,
lua-language-server 10 problems in 2 files. The mutation sweep over the changed lines caught
13 of 13. Not covered, as ever: a real multiplayer session, which is the only thing that can
confirm two hidden players actually pass through each other.

### 2026-09-16 — R-019: three axes, two name spaces, one table too few

`modules/core.lua` declared `NORMAL = 0, BOSS = 1, MODE = 2, CHAOS = 3, EASY = 0, MEDIUM = 1,
HARD = 2, NIGHTMARE = 3, NONE = 0, RED = 1, BLUE = 2` flat on one table, so the mode, the
difficulty and the team colour — three unrelated axes — shared their integers. Passing one
where another was expected matched a real member of the wrong axis instead of failing.
`Team.NIGHTMARE` is 3 and 3 is Chaos mode, so a Normal round set to Nightmare would have
become a Chaos round; `Team.BOSS` is 1, which is `RED`, so a mode value reaching `sh5_team`
would have turned on friendly fire in a mode with no teams. All 104 use sites were audited
and every one was on its right axis, so **nothing shipped broken**: the defect was latent, and
it shipped in released v1.1 rather than being introduced by any recent change.

The same table was also two name spaces wearing one name. 74 of its 89 members applied in all
four modes and 15 were genuinely about Team mode, so the axes ended up on a table named for
one mode and `Team.Difficulty.NIGHTMARE` read as "Team mode's difficulty" in a Normal round.
The two halves were done as one ticket because neither finishes the job alone and done
separately they rewrite the same references twice.

The result is `SH.Mode`, `SH.Difficulty` and `Team.Color`, with the mod-wide members on `SH`
and the fifteen Team-mode ones keeping the name `Team`. Both tables are declared in
`core.lua`, which requires nothing, so no module gained a `require` edge; only `main.lua`,
`hud.lua`, `round.lua` and `team.lua` bind both. 443 references moved and 113 stayed. Every
number is what v1.1 put on the wire: `sh5_mode` and `sh5_difficulty` are synchronized and are
used arithmetically, so renumbering would have made a released client and a patched one
disagree about what mode a lobby is in.

Three names changed as they moved, because their references were being rewritten anyway:
`Team.is_mode` became `SH.is_team_mode` (the old name said nothing once it was off a table
called `Team`, and `STARHUNT_TEST_API` already published it as `is_team_mode`),
`Team.TeamColor` became `Team.Color`, and the per-team RGB table `Team.colors` became
`Team.color_rgb` so it no longer differs from the colour axis by a letter's case and a plural.
**Entries below this one still say `Team.x` for members that are now `SH.x`** — they were
written when there was one table, and a log is not rewritten.

**R-026 was folded into this item and no longer exists.** It was filed while the axes were
being split, to record that the shared table held all three axes in all four modes but was
named for one of them. That is the second half of what this entry describes, so R-019 absorbed
it rather than rewriting the same 443 references twice. Anyone who meets `R-026` in the commit
log — it is the subject of `ad48eb0` — should read this entry.

A rejected alternative, recorded so it is not re-proposed: an erroring metatable on each axis,
raising on an unknown key and refusing assignment. Review called it nonsensical and it was. It
guarded a mistake the split already makes hard, it added a new way for a released mod to stop
mid-round, and it grew its own test surface — three assertions pinning where `error(..., 2)`
points. `BOWSER_ACT` in `modules/boss.lua` is a plain table of named constants and needs
nothing around it. Also rejected: renaming the whole table to `SH`, which moves 556 references
instead of 443 and files `RED`, `BLUE`, the rosters and the palettes under a mod name.

Nothing behavioural changed, so there was no mutation sweep for the second half; the first
half's was 41 of 41. Undoing the rename mechanically over the whole tree left exactly six
differences: `core.lua`'s declaration split and its extra return field, one added `local` line
in each of the four files that bind both tables, `main.lua` publishing two name spaces where
it published one, and the two tests. Checks: 780 passed / 0 failed, luacheck 2 warnings /
0 errors in 46 files, lua-language-server 10 problems in 2 files. The suite was 779 before the
second half — dropping the metatable removed a test and the documents were left claiming 780 —
so the added test restores the count the documents already had.

`PROJECT_STATUS.md` was two hashes behind for the same reason and now records
`E71D18CF…CA3BA8336`, with the intermediate `AFF4D804…F563DDFA` named as the axis-split value.

### 2026-09-16 — R-018: the predicate is `boss_is_held` again, and tests only that

`boss_is_grabbed` returned true both when a player had Bowser in their hands and when he was
in `BOWSER_ACT.THROWN`. A thrown Bowser is in nobody's hands, so the name asserted something
false about half its branches, and the comment above it made that worse by claiming a grab
has two halves — the throw is what follows a grab, not part of one. The reviewer read it and
said so.

The throw moved out to the two call sites, where three comparisons against `oAction` were
already sitting. That was the reviewer's own suggestion and it is the better shape: the four
actions in which Bowser does not attack now read as one list at the place that uses them,
instead of three in the condition and a fourth hidden behind a name. What is left,
`boss_is_held`, tests the nil object and `oHeldState`, which is what "held" means.

So the predicate carries the name it had in R-015 again, but not the meaning: R-015's version
tested only the held state because the throw had not been covered yet, and this one tests
only the held state because the throw belongs elsewhere.

A rejected alternative, for the record: splitting it into `boss_is_held` and
`boss_is_thrown`. Both names would have been true, but a one-line predicate called once per
call site does not earn a name, and an `or` between two helpers hides a list that reads
better written out.

Behaviour is unchanged — 775 tests, none of them edited — and both sweeps were clean first
time, 24 of 24 on `boss.lua` and 21 of 21 on `round.lua`.

### 2026-09-16 — R-017: Bowser's action numbers have names

The mod read Bowser's `oAction` at four places and compared it against five bare numbers — 1,
4, 5, 6 and 20 — with the meaning carried only by a comment beside each. The reviewer of the
R-015/R-016 pull request could not read the conditions, which is a fair complaint: a bare 20
in the middle of a boolean says nothing about which part of the fight it is, and the reader
has to trust the comment rather than the code.

`modules/boss.lua` now declares `BOWSER_ACT` with the vanilla `BowserActions` enum's names —
`THROWN`, `DEAD`, `TEXT_WAIT`, `INTRO_WALK`, `WAIT` — and exports it; `modules/round.lua`
imports it. sm64coopdx's autogenerated definitions carry no `BOWSER_ACT_*` names, so the
engine cannot supply them and the mod has to. Behaviour is unchanged and the suite stayed at
775 without a single test being edited, which is the point of the change.

**The tests deliberately keep their literals.** A test that set `oAction = BOWSER_ACT.WAIT`
would agree with a wrong value in the table instead of catching it, so every member is still
pinned by a test that writes the number: the intro trio in `boss_hazards` and `round_host`,
`DEAD` in `round_host`'s death case, and `THROWN` in both grab suites. The mutation sweep
confirms it — changing a value in the table is caught.

One thing the sweep rejected: the named comparison no longer fits on one line with the nil
guard, so an intermediate version split it into an early `return false`. That line survived
mutation — both call sites already check for a nil Bowser, so the guard is unreachable — and
rather than add a fourth entry to the list of knowingly dead lines, the predicate keeps the
wrapped single expression it shipped with and the sweep comes back clean.

### 2026-09-16 — R-016: the throw is part of the grab

R-015 stopped Bowser's attacks while a player holds him and stopped at the release, which
left the other half of the grab uncovered: the throw is Bowser's vanilla action 1, roughly a
second of flight at a mine, and an attack queued in that window fired from a tumbling Bowser
at a player stuck in `ACT_RELEASING_BOWSER` with no way to dodge. R-015 named the gap and
left it alone because it was not what had been reported; the user asked for it on reviewing
the pull request.

`boss_is_held` became `boss_is_grabbed` and now reads
`oHeldState == HELD_HELD or oAction == 1`. The rename is the point: one predicate for both
halves of a grab, used unchanged at the two call sites R-015 had already prepared.

`HELD_THROWN` and `HELD_DROPPED` are still not tested, and the comment in `boss.lua` now says
why — the same thrown update that sets action 1 puts the held state back to `HELD_FREE` on
the next frame, so neither value lasts long enough to observe. **Action 1 is a single action
and not the start of a range**: actions 0 and 2 are Bowser acting on his own, and a test in
`boss_hazards` pins both, because widening the check to a range would silence the fight's own
attacks.

Three tests were added, two in `test/suite/boss_hazards.lua` and one in
`test/suite/round_host.lua`; the suite is 775. Both mutation sweeps were clean first time —
28 of 28 on `boss.lua` against `boss_hazards` alone, 17 of 17 on `round.lua` against
`round_host`.

### 2026-09-16 — R-015: Bowser stops attacking while a player is holding him

Reported from play: in Boss mode, grabbing Bowser by the tail and spinning him did not stop
the attacks his drawn modifiers create. Every attack spawns at Bowser's own position, so each
one went off on top of the player holding him, and a shockwave did more than hurt — its stun
empties the controller, which releases B and drops Bowser, so the mod's own hazard cancelled
the vanilla mechanic the fight is won by. `boss.lua`'s header already carried the other half
of this rule (no Boss player modifier may remove B, because every player has to stay able to
grab him) and it had never been applied to the attacks.

The fix is one predicate, `boss_is_held`, used on both sides of the host-authority line:

- `modules/round.lua` (`host_update_boss_round`) folds it into `boss_ready`, so the host
  queues nothing while Bowser is held and pushes the next attack a second out, exactly as it
  already did for his intro.
- `modules/boss.lua` (`apply_boss_hazards`) folds it into the intro branch, so each client
  consumes the sequence without playing it and drops the delayed waves and meteors already in
  flight. Suppressing on both sides is deliberate: a client whose view of the grab differs
  from the host's still refuses to play the attack.

The predicate reads `oHeldState == HELD_HELD` and treats a Bowser the engine does not answer
for as free, so an engine that stops reporting the field leaves the fight working instead of
silently switching every attack off. `HELD_THROWN` and `HELD_DROPPED` are deliberately not
covered: the vanilla thrown update resets the field to `HELD_FREE` on the next frame, so they
are a one-frame state and not what was reported.

Five tests were added, three in `test/suite/boss_hazards.lua` and two in
`test/suite/round_host.lua`; the suite is 772. The mutation sweep caught 22 of 24 candidates
on `boss.lua` first time; the two survivors were the `or 0` fallback the consume branch
reads when the ring has never been written, which the third hazard test now pins. The
`round.lua` sweep caught all 17. `test/engine_stub.lua` was regenerated for `HELD_HELD` and
is now 118 constants.

### 2026-09-16 — R-011: the refactor is reconciled, merged into `main` and tagged

The thirteen-module split was merged into `main` as a single merge commit, with
`v1.1-monolithic` marking the commit before it and `v1.1-modular` the merge itself. Both are
pushed. The release documents were reconciled in the same pass, which is what R-011 asked for
and had deliberately deferred to this moment:

- `PROJECT_STATUS.md` keeps the released single-file hash as the historical fact of what
  shipped as v1.1, and adds the modular layout separately. **A single file's hash no longer
  identifies the mod**, so the recorded identifier is now the SHA-256 of the sorted list of
  every shipped `.lua` file's hash,
  `27BEDAA8…5D3DD0C7`. The install instruction changed from "copy `main.lua`" to "copy the
  `StarHunt/` folder", which is not cosmetic: `main.lua` alone no longer runs.
- `CLAUDE.md` gained a module map with line counts and the `require` graph, and its
  known-clean baseline is now a table of all three checks — 767 tests, 2 luacheck warnings,
  10 type-checker problems in 2 files. The claim about 24 "shadowing upvalue `goal`" warnings
  was removed: they are gone, because `goal()` is file-local to `goals.lua` now.
- `ROADMAP.md` is reorganized around corrective maintenance. R-014 (take bug reports and turn
  them into items) and R-010 (play the split mod in a real session) are under Now; R-012 is
  under Next and stays deferred until a bug actually lands in `round.lua`'s host half.

**What this merge does not claim.** The split has never been played inside sm64coopdx. The 767
tests run outside the game against a double of the engine, so they do not reach rendering,
networking, warping or other-mod interaction — and they do not reach the game's own
folder-relative `require`, which is the one mechanism the split actually changed.
`test/harness.lua` reimplements `require` rather than using it. That is R-010, and
`v1.1-monolithic` is what to go back to if it fails.

### 2026-09-16 — R-013 finished: the client half of the round loop moves into `modules/round.lua`

`on_before_boss_cutscene`, `local_goal_warp_update` and `local_boss_warp_update` left
`main.lua` for `modules/round.lua`'s client half — 99 lines, the last of the eight
declarations R-004 found. `main.lua` is 518 → 420 and `round.lua` 966 → 1,079. **R-013 is
done**: every top-level declaration left in `main.lua` is the header, an import, a hook
callback with a recorded reason, the synchronized-table seed or `STARHUNT_TEST_API`.

The moved bodies were proven byte-identical three ways — the block in `round.lua` matches
lines 108-206 of `4f7b50f`'s `main.lua` exactly, the new `main.lua` is that file minus exactly
that block, and the new `round.lua` is the old one plus exactly it — and the check was run
again immediately before committing. Unlike the two passes before it this was **not** a pure
relocation: all three are registered as hooks, so `round.lua` exports them and `main.lua` binds
them back. That wiring is a separate, countable diff of five hunks in `main.lua` and four in
`round.lua`. `round.lua` gained `core.NEXT_GOAL_DELAY` and
`modifiers.reset_local_modifier_state`; `main.lua` lost `boss.BOSS_LEVELS` and the same
`reset_local_modifier_state`, which had no reader left.

**All three functions had no tests at all — the eighth time `STARHUNT_TEST_API` membership has
meant "untested", and the clearest case so far.** `goal_warp` and `boss_warp` were published
and called by nothing anywhere in `test/`; `on_before_boss_cutscene` was not published; and
`hook_event` in the harness only records a callback without running it. All 210 mutations of
those 99 lines survived a green 721-test run, confirmed against the full suite rather than
argued: the mod could have failed to warp anyone to their star, replayed a whole fight's worth
of Bowser attacks at a late joiner, or revived a dead player with no health, and nothing would
have gone red.

Forty-six tests were added to `test/suite/round_client.lua` (26 → 72; the suite total is 721 →
767). Three engine stubs had to gain real bodies first: `get_ttc_speed_setting` /
`set_ttc_speed_setting`, which made both the Tick Tock Clock guard and the choice between
stopped and slow invisible, and `set_mario_action` / `soft_reset_camera`, which are the half of
Boss's in-place death respawn that actually puts Mario back in play. After that, **201 of 202
mutations are caught**. The survivor is an equivalent mutant — `BOSS_LEVELS[... or -1]` cannot
differ from `[... or 0]` in a one-entry Lua array — and is recorded with the other twenty in
`REFACTOR_PLAN.md`.

Two things were corrected rather than left wrong. `round.lua`'s header claimed the host and
client halves **never call each other**; `on_before_boss_cutscene` calls `host_end_round`
behind a `network_is_server()` check, so the header now names that one exception and R-012 has
been updated — its cut is no longer free. And `tools/gen_mutations.py` was deleting
comment-only lines, which always survive and say nothing; six of one sweep's fifty-four
survivors were that noise. It now skips them.

Two traps worth carrying forward. The mutation range must be derived **after** the last edit to
the file: adding the two imports pushed the block down three lines, so a range worked out
beforehand mutated the tail of the function above it and missed three lines of the block. And
for a block this size the full suite is too slow to sweep against (43s × 202 is over two
hours), so the sweep ran against `round_client` alone and only the survivors were re-run
against everything — checked rather than assumed: all 54 agreed.

### 2026-09-16 — R-013, third of four destinations: the Nightmare pair picker moves into `modules/modifiers.lua`

`Team.pick_second_modifier` left `main.lua` for `modules/modifiers.lua`. Twelve lines moved,
proven byte-identical in both directions: the block in `modifiers.lua` matches lines 108-119
of `e0c6dd3`'s `main.lua` exactly, and the new `main.lua` is that file minus exactly that
range. `modifiers.lua` gained **no import at all** — the function reads only `Team` fields
(`Team.chaos_pair_allowed` from `chaos.lua`, `Team.difficulty_modifier_allowed` from
`difficulty.lua`) and the goal's own `mods` list, and its one caller, `host_assign_goal` in
`round.lua`, already reached it through `Team`. The require graph is unchanged. `main.lua` is
531 → 518 lines; `modifiers.lua` is 823 → 841, the twelve moved lines plus a blank and a
five-line header note.

**The header note is a real edit, not part of the move.** `modifiers.lua` opened by saying
"Everything here runs on the local player's own machine and is never synchronized", and
`pick_second_modifier` runs on the host and decides which second modifier a star race hands
out — exactly the kind of decision that sentence says lives elsewhere. Rather than leave a
false statement at the top of a file the next session reads, the header now names the one
exception and why it is here: its subject is the catalog and pair compatibility, not the
round. The move itself was verified separately from that edit, and `git diff -U0` on the file
shows exactly two hunks.

**The mutation sweep found the gap this time in the `#choices == 0` guard.** Before the move,
a sweep of the block caught 8 of 13 mutations; all five survivors were on one line,
`if #choices == 0 then return 0 end`. `test/suite/pairing.lua` had four tests touching
`pick_second_modifier`, and every one of them only inspected pairs that were successfully
formed — so the opposite case, nothing compatible and therefore no second modifier, was never
reached. It is unreachable with the real 93 goals, because every star has at least one legal
Nightmare pair and one of those tests asserts precisely that. Reaching it needs a synthetic
goal.

Three tests were added, each building a small goal from a real one so the level and act the
audit reads stay genuine, and searching for the modifiers rather than naming them so retuning
a star cannot quietly turn the tests into no-ops: a goal with a single modifier offers no
second; a goal whose only alternative is the same kind offers no second, because
`chaos_pair_allowed` refuses a kind paired with itself; and a goal with exactly one legal
alternative returns that one, in both directions. The first two also catch deleting the guard
outright, since the function then reaches `math.random(0)` and errors.

After the move the block caught **13 of 13**, and a sweep of the two caller lines in
`round.lua` that assign `sh5_modifier_2` caught **8 of 8**. The suite is 718 → 721 tests, all
passing. luacheck holds at 2 warnings / 0 errors in 46 files and lua-language-server at 10
problems in 2 files, both pre-existing.

### 2026-09-15 — R-013, second of four destinations: the lifetime star count moves into `modules/goals.lua`

`Team.lifetime` and `Team.update_lifetime_sync` left `main.lua` for `modules/goals.lua`. Seven
lines moved, proven byte-identical in both directions: the block in `goals.lua` matches lines
107-113 of `7af4b9e`'s `main.lua` exactly, and the new `main.lua` is that file minus exactly
that range. `goals.lua` gained **no import at all** — both are fields of the shared `Team`
table it already binds from `core`, and `main.lua` keeps reaching them the way it reaches
`Team.update_palettes`, so the require graph is unchanged. `main.lua` is 538 → 531 lines;
`goals.lua` is 877 → 890, the seven moved lines plus a five-line comment saying why the
counter lives there and a blank.

**`Team.update_lifetime_sync` was published in `STARHUNT_TEST_API` and called by no test at
all** — the seventh time that has been true. A sweep of the block before the move caught 4 of
8 mutations: the whole body of `update_lifetime_sync` could be deleted, the total could be
written into player 1's slot instead of player 0's, and a negative stored total could pass the
clamp, all with 709 tests still green.

`test/suite/lifetime.lua` is new — 9 tests over the stored total read at load, a first run with
nothing stored, a stored value that is not a number, a negative one clamped and a fractional
one floored, the republish that puts the total back when the synchronized value is lost, and
claiming a star raising, saving and republishing it while a star that is not the goal leaves it
alone. The re-sweep at the new location, over both the moved block and the three lines in
`on_interact` that increment and persist the total, caught 14 of 15. The one survivor is
equivalent and is recorded in `REFACTOR_PLAN.md`: the `or 0` that catches an absent total sits
inside `math.max(0, math.floor(...))`, so `or -1` still loads as zero.

**The mutation tooling is now committed**, at the user's decision, as `tools/gen_mutations.py`
and `tools/sweep_mutations.py`. It had been written from scratch into the session scratchpad
and lost with it at least twice, while the project's own verification rules require a mutation
check on every pass. `tools/` is outside `StarHunt/`, so nothing there ships with the mod.

718 tests pass. luacheck 2 warnings / 0 errors in 46 files and lua-language-server 10 problems
in 2 files, both unchanged baselines.

### 2026-09-15 — R-013, first of three: the Boss trio moves into `modules/boss.lua`

`Team.boss_reserve_bomb_count`, `Team.host_update_boss_bomb_supply` and
`ensure_boss_health_owner` with its four `local_boss_health_*` locals left `main.lua` for
`modules/boss.lua`. 137 lines moved, proven byte-identical in both directions: the two blocks
in `boss.lua` match lines 109-112 and 132-264 of `457289d`'s `main.lua` exactly, and the new
`main.lua` is that file minus those two ranges, minus one line, plus one import. The line
removed is `local FRAMES_PER_SECOND = core.FRAMES_PER_SECOND`, which had no reader left once
the bomb supply went; `boss.lua` gained the same binding and nothing else, so it still requires
only `core`. `main.lua` is 676 → 538 lines.

**`ensure_boss_health_owner` was published in `STARHUNT_TEST_API` and called by no test at
all** — the sixth time that has been true, and the reason the project does not treat being in
that table as evidence of coverage. A 136-mutation sweep of the moved code caught 90. Two
engine stubs were hiding most of the rest: `sync_object_is_owned_locally` returned `nil` from
the generated stub, so no client ever owned anything and the whole second half of the function
was unreachable, and `network_send_object` was inert, so a publication left no trace. A third,
`count_objects_with_behavior`, ignored its argument and answered `ctl.bomb_count` for any
behavior, which made asking the engine to count the wrong thing invisible. `test/harness.lua`
now drives ownership from `ctl.owned_sync_ids`, records publications in `ctl.sent_objects`,
counts only Bowser's bombs, and can fail a synchronized spawn on demand through
`ctl.spawn_failures`.

`test/suite/boss_health.lua` is new — 31 tests over who may write Bowser's health, what the
pool is per difficulty, why a new owner must never heal a fight already under way, and the
five-frame publication heartbeat. Nine more went into `test/suite/boss.lua` for the reserve
wave, and the existing "fires only once per round" test was strengthened: it advanced the
timer between two calls but never past the one-second wait, so a mutation that discarded the
already-spawned count still passed it.

Final sweep: **136 mutations, 117 caught by the suite, 4 caught by luacheck** (deleting a
`local` declaration turns the name into a global, which luacheck reports and no test can see),
**15 analysed as equivalent** and recorded in `REFACTOR_PLAN.md` so the next sweep does not
re-investigate them. Five of the fifteen are the entire body of the reset branch in
`ensure_boss_health_owner`, which is redundant with the object-change branch below it. Left
exactly as it is: a redundant clause found during a move is still not a move's business to
delete.

The suite is 670 → 709 tests, all passing. luacheck stays at 2 warnings / 0 errors (45 files
now), and lua-language-server at 10 problems in 2 files. **R-013 is not finished:** five
declarations remain, in three destinations — `goals.lua`, `modifiers.lua` and `round.lua`.

### 2026-09-15 — R-004: every remaining declaration has a reason, and Lakitu has a test

One commit, and no mod code changed at all — `StarHunt/main.lua` is byte-identical to
`457289d`. R-004 was an audit and a test, not an extraction. **R-004 is done**, and it split
into two findings.

**The five declarations R-004 was written about all stay in `main.lua`, on purpose.**
`gServerSettings.skipIntro`, `local_lakitu_scan_at`, `remove_castle_lakitu`,
`remove_existing_castle_lakitu` and `on_find_water_level` are castle-grounds lobby cleanup
that belongs to no StarHunt system: they run whether or not a round is active, read no
synchronized field, and have no caller but the hook block. A `modules/lobby.lua` was
considered and rejected — one variable and three short functions with a single reader, where
the `require` line costs about what the code does. The reasons are now a table in
`REFACTOR_PLAN.md`'s appendix, which is no longer a plan but the record of what is left in
`main.lua` and why.

**`test/suite/lobby.lua` is new: 12 tests.** `DEVELOPMENT_CHECKLIST.md` had carried "Sin
prueba" against the Lakitu row since the bug was fixed — nothing under `test/` mentioned
Lakitu at all. The suite covers both deletion paths, the behavior id that distinguishes the
camera Lakitu from anything else, the refusal to act away from the castle grounds, the
fifteen-frame gap between retroactive scans, the fact that time spent off the grounds does not
consume that gap, and the water-level hook handing back the height it was given. A
29-mutation sweep over the whole area caught **29 of 29**, each by the test written for it.
Three of them only fell after a twelfth test was added: `gServerSettings.skipIntro = 1` could
be deleted, or set to 0 or 2, with everything still green, because nothing had ever looked at
it. The harness sets it to 0 before `main.lua` runs, which is what makes the load-time
assertion mean something.

**The audit found a second group nobody had checked: eight declarations left behind.** The
handoff had flagged this as unverified and it turned out to be real. `Team.lifetime`,
`Team.update_lifetime_sync`, `Team.pick_second_modifier`, `Team.boss_reserve_bomb_count`,
`Team.host_update_boss_bomb_supply`, `ensure_boss_health_owner`, `on_before_boss_cutscene`,
`local_goal_warp_update` and `local_boss_warp_update` were all assigned to a module by the
original appendix — `boss`, `goals` or `i18n` — and were simply not taken when that module
came out. Only `on_joined_game` had a recorded decision. So `REFACTOR_PLAN.md`'s sentence
"Nothing else in `main.lua` belongs to a module that exists" was wrong, and the document had
asserted "the module is finished" five times on the strength of the planned *block* being out
rather than the *file* being clear. Each of the eight was checked against the real require
graph and none needs a new edge; `on_before_boss_cutscene` is the one that does not go where
it looks like it should, because it calls `host_end_round` and the graph already runs
`round -> boss`. Moving them is **R-013**, now the only item under Now, and R-010 was
re-pointed from R-004 onto it.

The cheap check that would have caught this, now written into the plan: grep `main.lua` for
its top-level declarations at the end of every pass, and treat anything that is not the
header, an import, a hook callback with a recorded reason, or `STARHUNT_TEST_API` as
unfinished.

Baselines after: **670 tests pass** (was 658), luacheck 2 warnings / 0 errors in 44 files
(was 43), lua-language-server 10 problems in 2 files — all unchanged apart from the file
counts. `test/README.md` gained the `lobby` row and now says plainly that its table is
incomplete: `core`, `i18n`, `team`, `world` and `modifiers` still have no row.
`DEVELOPMENT_CHECKLIST.md`'s code map had also gone stale on the HUD, still naming `main.lua`
for `draw_hud`, `draw_player_health_bar` and `draw_config_menu` three sessions after they
moved; that row is corrected.

### 2026-09-15 — `modules/hud.lua` is finished: the frame

One commit. `main.lua` fell from 857 to **676** lines, `modules/hud.lua` grew from 510 to
**708**, and the suite went from 601 to **658** tests. **R-003 is done**, and with it
`modules/hud.lua`. Every module named in the plan now exists and is complete except
`round.lua`, which R-012 wants split for being large rather than unfinished.

**Four declarations and three state locals moved as one piece, plus one constant.**
`draw_start_banner`, `draw_config_menu`, `draw_hud` and `local_round_notifications` were one
contiguous range in `main.lua` (402-578), and `START_BANNER_FRAMES`, `local_seen_round`,
`local_seen_result` and `local_start_banner_until` went with them. They had to travel
together: `draw_hud` calls the banner and the menu, and the notifications rebind the frame
number the banner reads, so the alternative was migrating that local onto `local_runtime`
first in its own commit.

**The two new require edges were the last ones the plan predicted.** `module_deps.py` named
`configured_time_range` and `connected_player_count` from `round`, and `config_option_count`,
`config_option_kind` and `config_status_text` from `menu`, so `hud.lua` now requires
`core`, `i18n`, `goals`, `boss`, `round` and `menu`. Neither `round` nor `menu` requires
`hud` and nothing else does either, so there is no cycle. The scan also reported `boss` as a
dependency and that was a false positive -- it matched the word inside the string literal
`"boss defeated"`. `main.lua`'s three `menu` option bindings had no reader left afterwards
and went with the move.

**The area was almost entirely untested, as expected.** `test/suite/hud.lua` reached
`draw_hud` exactly once, inside a `pcall` that only checked no colon had gone to the font;
`test/suite/menu.lua` tests what the menu does when a button is pressed, never what it draws;
and nothing tested the banner or the winner announcements at all. A first sweep of ten
mutations caught none of them. `local_round_notifications` was not in `STARHUNT_TEST_API`;
it and `draw_start_banner` were added.

**A new suite, `test/suite/hud_frame.lua`, with 57 tests, took the sweep to 232 of 238.**
The first full sweep caught 218 and left 20; fourteen of those were real gaps and every one
was killed by a test written for it, with the "which test caught it" column read rather than
the count alone.

**Four of those gaps were only reachable on a client**, which is worth carrying forward: the
host fills `sh5_round`, `sh5_result_seq` and both team scores in with zero in its load-time
block, so on a host the `or 0` defaults the notifications apply to those fields can never
fire. A client runs none of that block and sees nothing until the host's first sync, which is
exactly what those defaults are for. `harness.load(function(c) c.is_server = false end)` is
the fixture that reaches them.

**The six survivors are equivalent mutants, each checked rather than argued**, and recorded
in `REFACTOR_PLAN.md` so the next sweep does not re-investigate them. Four are bare `local`
declarations whose every branch assigns before anything reads; one is a fallback index into
`Team.menu_lock_labels` that all three writers of `Team.language` make unreachable; and one
is the floor of a `math.max` whose two candidate values format to the same `0:00`.

**Baselines held.** 658 tests pass, luacheck stayed at 2 warnings / 0 errors (43 files now),
and lua-language-server at 10 problems in 2 files. Byte-identity was proven in both
directions, and re-checked after the sweep before committing.

### 2026-09-15 — `modules/hud.lua`, second pass: the picture layer

One commit. `main.lua` fell from 1,164 to **857** lines, `modules/hud.lua` grew from 187 to
**510**, and the suite went from 534 to **601** tests. R-003 is still **not** finished and was
rewritten again: eight declarations and roughly 200 lines are left -- the start banner,
`draw_config_menu`, `draw_hud` itself and the round notifications.

**Nine declarations moved, in two ranges, and `hud.lua` gained its first imports.**
`Team.darkness_active` and `modifier_text` came out together, and the panels --
`Team.draw_hud_panel`, `Team.health_wedges`, `Team.health_color`, `draw_player_health_bar`,
`Team.draw_round_status_panels`, `Team.draw_objective_panel` and
`Team.draw_gun_mod_hud_compatibility` -- as one contiguous block. `module_deps.py` named ten
dependencies and every one was already imported by `main.lua` from a module that exists, so
the file now requires `i18n`, `goals` and `boss` as well as `core`, and there is still no
cycle because nothing requires `hud`. `main.lua`'s `local BOSS_MODIFIER_FIELDS` had no reader
left afterwards and went with it.

**This was the worst-covered area in the whole refactor by a wide margin: 500 of 507
mutations survived.** The seven the suite caught were caught by the darkness and
health-colour tests written for the first pass. `modifier_text` -- every modifier's name in
three languages -- was not published in `STARHUNT_TEST_API` at all, and neither was
`Team.draw_hud_panel`; both were added. The whole picture layer could have been moved,
resized, recoloured or deleted outright with the suite still green.

**Three engine stubs were hiding it, the same trap as the pass before.**
`djui_hud_render_rect` kept only the last rectangle and `djui_hud_render_texture` only a
count, and every card in the HUD is a stack of rectangles, so a panel's position, size and
colour were all invisible; `gTextures` was empty, which put the star and coin icons behind an
`if gTextures.x ~= nil` guard no test could satisfy. `ctl.hud` now carries `rect_calls` and
`texture_calls` with the colour in force at the time, each text call carries the same colour,
`djui_hud_set_font` records what it was given, and `gTextures.star` and `gTextures.coin` have
values. The harness also clears the five third-party globals a test installs to fake Gun Mod,
which nothing else would ever have cleared.

**A new suite, `test/suite/hud_panels.lua`, with 67 tests, brought the sweep to 503 of 507.**
Every one of the 20 survivors of the first re-sweep was killed by a test written for it, and
the "which test caught it" column was checked rather than the count alone. The four that are
left are all in one line: `Team.health_wedges` clamps twice around a `math.floor`, and the
bounds overlap so completely that raising any one of them changes nothing. That was settled
exhaustively rather than argued -- each mutant agrees with the original on `nil` and on every
integer from -5,000 to 20,000 -- and recorded in `REFACTOR_PLAN.md` so the next sweep does not
re-investigate it. **Leave all four exactly as they are.**

**Baselines held.** luacheck stayed at 2 warnings / 0 errors, and lua-language-server at 10
problems in 2 files -- though the new suite first pushed it to 33, all of them `need-check-nil`
on helpers whose nil branch ends in `t.fail`. The type checker does not know `t.fail` never
returns; the helpers now end `return got or {}`, which says the same thing in a way it reads.

### 2026-09-15 — `modules/hud.lua`, first pass: the text layer and the native HUD

One commit. `main.lua` fell from 1,286 to **1,164** lines, `modules/hud.lua` arrived at
**187**, and the suite went from 509 to **534** tests. All thirteen modules now exist. R-003
is **not** finished and was rewritten to what is left: about 470 lines of drawing that needs
the other modules.

**Thirteen declarations moved, in two ranges, and the new file imports only `core`.** The
text layer -- `format_remaining_time`, `measure_hud_text`, `draw_hud_text`,
`draw_centered_hud_text`, `Team.objective_text_max_width`, `Team.draw_scaled_centered_text`
-- came out with `apply_counter_visibility`, `update_native_hud_visibility`,
`Team.draw_darkness_behind` and `hide_native_hud_before_render`, which are one contiguous
block, plus `local_hud_flags_before_round` and `local_counter_round_active`, which sat with
the other `local_*` declarations far above and are read nowhere else. `module_deps.py` named
five dependencies and all five were in `core`, so there is no `i18n`, `menu` or `round` edge
yet. Nothing requires `hud`, so it can import anything in a later pass.

**Only part of the module could move, which is what the standing rule asks for.** The rest of
the HUD needs sequencing this pass established and recorded: `local_round_notifications`
rebinds `local_start_banner_until` and `draw_start_banner` reads it, so those two travel
together or that local is migrated onto `local_runtime` first, in its own commit.

**This was the worst-covered area in the whole refactor: 77 of 80 mutations survived.** The
three the suite caught were caught by the colon tests that were already there. Four functions
-- `counter_visibility`, `native_hud_visibility`, `hide_native_hud_before_render` and
`draw_darkness_behind` -- were published in `STARHUNT_TEST_API` and called by no test at all,
which is the third time that exact pattern has turned up.

**Seven engine stubs were making the area unobservable even in principle**, the largest single
case of that trap so far. `hud_get_value` answered 0 for every display value, `hud_set_value`
threw the write away, and `hud_hide`, `hud_show` and `hud_is_hidden` were a no-op, a no-op and
a constant `false`. Between them, the star and coin counters StarHunt saves before a round and
restores after it could have been deleted outright, and so could the code that gives a player
back a native HUD they had hidden themselves -- one of the behaviours `CLAUDE.md` lists as easy
to break again. `djui_hud_render_rect` discarded the rectangle's position and size, so a
darkness rectangle ten pixels wide looked identical to one covering the screen, and
`djui_hud_set_resolution` discarded the resolution. All seven now have real bodies driven by
`ctl.hud.values`, `ctl.hud.hidden`, `ctl.hud.last_rect` and `ctl.hud.resolution`.

`test/suite/hud.lua` went from 81 lines and 6 tests to 425 and 31. The second sweep caught 77
of the 80, each by the test written for it. One gap the first round of tests missed is worth
keeping: the colon's two dots are drawn by two separate lines, and a test that pins only the
upper dot's scale leaves the lower one free.

**Three survivors are equivalent mutants and stay exactly as they are.**
`local_hud_flags_before_round` starts as `nil` and is released back to `nil`, and the only
read of it sits behind a flag that is set on the line straight after the save, so neither
value can be reached. The `text_width > 0` guard in `Team.draw_scaled_centered_text` protects
a division by zero that needs a negative box width, and every caller passes a positive literal
or `Team.objective_text_max_width()`, whose floor is 24. The reasoning is in
`REFACTOR_PLAN.md` so the next sweep does not redo it.

Both byte-identity directions held, `main.lua` was reconstructed from the previous commit and
matched exactly, and the ranges were re-diffed immediately before committing. The only text
that is not a relocation is `hud.lua`'s header. 534 tests pass; luacheck stays at 2 warnings /
0 errors, now over 41 files; lua-language-server at 10 problems in 2 files.

### 2026-09-15 — `modules/menu.lua`, out of order and ahead of `hud`

Two commits. `main.lua` fell from 1,541 to **1,286** lines, `modules/menu.lua` arrived at
**320**, and the suite went from 469 to **509** tests. Twelve of the thirteen modules now
exist; only `hud` is left.

**The planned order was backwards, and the scan said so.** `ROADMAP.md` had `hud` first with
`menu` blocked behind it. `tools/module_deps.py` measured the opposite: the HUD block's only
dependencies still in `main.lua` were four menu declarations -- `config_option_count`,
`config_option_kind`, `config_status_text` and the selection -- while the menu block depended
on nothing outside the modules that already existed. Menu was the leaf, so menu went first and
the two roadmap items swapped. The order past the modules already extracted was planned from a
reference graph and never measured; **run the scan before trusting it.**

**`draw_config_menu` is settled and stays with the HUD.** The plan's appendix had it in `hud`
only because its name starts with `draw_`, and R-004 asked whether it belonged in `menu`. It
cannot: it draws through `draw_hud_text` and `draw_centered_hud_text`, and `draw_hud` calls it
back, so a `menu.lua` that owned it would be half of a require cycle. `Team.freeze_menu_mario`,
which the appendix suggested reconsidering against `modifiers`, did come here -- it pins Mario
only while the config menu is open and reads nothing from `modifiers`.

**The migration came first, in its own commit.** `config_selection` is rebound on every press
and `draw_config_menu` reads it, so it joined `config_open` on `local_runtime`.
`config_button_latch` and `config_stick_latched` are rebound too and were deliberately left
alone, because nothing outside the menu reads them: migrate what crosses a boundary, not every
rebound local in the block.

All three moved blocks are byte-identical in both directions, `main.lua` was reconstructed from
the previous commit and matched exactly, and the blocks were re-diffed immediately before
committing. The only text that is not a relocation is `menu.lua`'s header.

**The menu was the worst-covered area found so far.** `update_config_input` -- every key a
player can press -- was published in `STARHUNT_TEST_API` as `menu_input` and called by no test
at all; only `is_menu_open` was reachable. Of 67 mutations, **18 survived the first green run**
and 9 more were found once the first round of new tests went in. `test/suite/menu.lua` now
holds 40 tests and catches 63 of the 67.

Three of those gaps came from the same trap, and it is worth remembering: **the menu zeroes the
controller on its way out**, so a test that holds a button or a stick has to set it again every
frame, exactly as the engine does. Tests that did not looked like they were exercising the
latch and were only observing the zeroing.

**Four mutations survive and cannot be caught**, each recorded in `REFACTOR_PLAN.md` with its
reason. Three are clauses a second, outer check has already settled: `if Team.language < 0`
after a `%` is unreachable because Lua's `%` follows the sign of the divisor; the
`and network_is_server()` on the mode, difficulty and time branches cannot fire on a client,
because `config_option_kind` only names those rows inside its own server branch; and the
`clamp` before `host_start_round` is redundant because that function clamps its own argument.
The fourth, `set_config_menu_open(true)` after `host_end_round`, is a no-op because the branch
only runs while the menu is already open. All four stay exactly as they are.

`test/README.md` gained rows for `menu` and, in the previous pass, `round_host`. Five suites
are still missing from that table: `core`, `i18n`, `team`, `world` and `modifiers`.

### 2026-09-15 — R-002 finished: Chaos's round loop reaches `modules/round.lua`

One commit. `Team.host_update_chaos_round`, the last function in `main.lua` that belonged to a
module, moved into `round.lua` next to `host_update_boss_round`. `main.lua` fell from 1,562 to
**1,541** lines, `round.lua` grew from 942 to **966**, and the suite went from 456 to **469**
tests. With this, **no module owns code that still lives in `main.lua`**; what is left there is
`hud` and `menu`, which have no module yet.

**The decision R-002 existed to make.** The two options were the ones the Boss pass chose
between: move what the caller needs into `core.lua`, or accept that a round loop belongs to
`round.lua`. The second was taken, and the first was measured rather than skipped.
`tools/module_deps.py` named exactly three dependencies -- `host_end_round`,
`host_add_late_joiner` and `remember_player_index` -- and all three are the round's own host
machinery, not plain helpers: `host_end_round` rebinds two of the round's tables, and
`host_add_late_joiner` goes through `host_prepare_player`, which reads three more. Moving those
into `core.lua` to satisfy one caller would have put the round's own decisions outside the
round. So the rule the pass leaves behind is narrower than "shared helpers go to core": **a
shared helper moves into `core.lua`; a module's own machinery does not.** The move needed no
new `require` edge at all -- all three names were already file-local in `round.lua`, and
`Team.host_reroll_chaos_modifiers` is reached through the shared `Team` table.

The move is byte-identical in both directions, and was re-diffed against the original
immediately before committing. The only text that is not a relocation is the header of
`round.lua` and of `chaos.lua`, both of which said the loop was still in `main.lua`.

**The loop was completely untested.** Replacing its whole body with an empty one left all 456
tests green. Thirteen tests now drive it through its real caller, `host_update_round`, in a
Chaos round: the survivor count and the four things that must not be counted, the latecomer the
loop enrols as a spectator, the snapshot that makes a reconnect different from a fresh arrival,
the reroll, the last player standing, and the roster lock that has to be set before an empty
lobby means anything.

**31 mutations, 27 caught, 4 equivalent.** Each of the 27 is caught by the test written for it,
with a readable assertion rather than a nil-index error. The 4 survivors are all the same shape
-- a default or a seed no reachable state can reach -- and are recorded in `REFACTOR_PLAN.md` so
the next sweep does not re-investigate them: `alive_name`'s seed is never read, which also makes
reducing `alive_count == 1 and alive_name or "Nobody"` to `alive_name` equivalent; and the
`or 0` on `sh5_chaos_eliminated` and on `sh5_chaos_roster_locked` both guard fields that are
always written before the loop can read them.

One thing worth knowing for any later test of this area, and now a comment in the suite:
`host_start_round` already seeds `sh5_chaos_alive` with the connected player count, so a test
where nobody has dropped out agrees with the loop even when the loop publishes nothing. Only a
test that changes the count proves anything.

`test/README.md` also gained the `round_host` row it never had. Six suites are still missing
from that table -- `core`, `i18n`, `team`, `world`, `modifiers` and `chaos`.

### 2026-09-14 — R-002, fifth part: Bowser's attack queue and hazards reach `modules/boss.lua`

Two commits. The first moved `is_local_player_on_floor` out of `modifiers.lua` and into
`core.lua`; the second moved the 172 lines from `spawn_violet_split_fire` to
`apply_boss_hazards` out of `main.lua` and into `boss.lua`. `main.lua` fell from 1,735 to
**1,562** lines, `boss.lua` grew from 158 to **348**, and the suite went from 407 to **456**
tests.

**The cycle this pass had to settle.** `REFACTOR_PLAN.md` had recorded two ways out and chosen
neither: move the shared helper into `core.lua`, or move `BOSS_PLAYER_MODIFIERS` out of
`boss.lua` so the `modifiers -> boss` edge disappears. The first was taken. The second would
have put Boss's own player catalog outside `boss.lua` to satisfy a four-line predicate, and
that predicate is a plain read of Mario's state with no modifier meaning of its own -- the same
shape as `player_record_key`, which moved into `core.lua` for the same reason in R-001. With
the helper in `core.lua`, the hazards moved **with no new require edge at all**: `boss.lua`
still requires only `core`.

Both moves are byte-identical in both directions. The only text that is not a relocation is
`boss.lua`'s header, which now says why the round loop is not there and cannot be.

**`is_local_player_on_floor` was completely untested, and so were the seven modifiers gated on
it.** All four first-pass mutations survived a green 407-test run, including replacing the
whole body with `return true`. The cause was the suite's own Mario: it has no `floor`, so the
predicate always answered false and the cursed floor, the jump limit, Slippery, Keep Moving,
the jump cooldown, the momentum burst and Overheat were skipped in every test that armed them.
Five tests in `test/suite/modifiers.lua` now drive it through the cursed floor -- on the ground,
with no floor underneath, swimming, at 21 and at exactly 22 units up, and 100 units below --
and all ten mutations fail.

**The hazards had no tests whatsoever**, and three engine stubs would have kept it that way.
`api.boss_hazards` was published to `STARHUNT_TEST_API` and called by nothing.
`dist_between_objects` answered 0 for every pair, so `distance < 4800` was true whatever the
positions were and a shockwave stunned from any range. `obj_scale` discarded its arguments, so
every flame was the same size. And `atan2s` answered `nil`, which does not disable hunter fire
but **crashes** it, because the attack adds `0x0800` to the yaw it reads. All three now have
real bodies in `test/harness.lua`. That makes **ten** stubs found to have silently disabled a
guard.

`test/suite/boss_hazards.lua` is 44 tests: the four gates, Instant Knockout's one-kill-per-hit
lock, the stun and the menu it spares, attacks waiting through Bowser's absence rather than
being consumed, the intro consuming them, the delayed wave and the meteor fall, the ring's
replay window and its wrap and its newest-slot fallback, and each of the nine attacks that
create a hazard of their own.

**97 mutations, 92 caught.** The first sweep caught 81; the 16 survivors split into 11 real
gaps and 5 that cannot be caught. Both the gaps and the reasoning for the five are worth
recording, because the pattern repeats:

- Three `if bowser == nil then return end` guards sit in helpers that only ever run after
  `apply_boss_hazards` has already returned on a nil Bowser. Unreachable from any test.
- The `return` ending the intro branch is equivalent: the branch sets
  `boss_hazard_seq = attack_seq` first, so falling through hits the sequence check below and
  returns anyway, with both pending queues already emptied.
- The fast-path `if attack_seq == local_runtime.boss_hazard_seq then return end` is equivalent:
  `first_seq` then lands one past `attack_seq`, so the replay loop runs zero times.

The 11 real gaps were all the same kind of thing -- a test that pinned a value only where the
mutation happened not to change it. Four are worth naming because they would recur: asserting
the flame damage only for the attack that spawns its flames a different way; testing the meteor
blast radius at 600 units, which is outside both 580 and the mutant's 480; setting the arena
index to 0 explicitly, so the `or 0` **default** was never exercised; and asserting only that
hunter fire aimed *differently* at two opposite positions, which the reversed-aim mutant
satisfies just as well as the real code.

The sweep itself took 14 minutes: 97 mutations x a full 456-test run, four at a time on a
four-core machine, where four concurrent runs contend and each takes ~33s rather than ~23s.
**Run the targeted suites first and re-run the full suite only for the survivors** -- the
re-check of the 16 took 30 seconds that way. The sweep script also wrote its results only at
the end, so nothing was readable while it ran; write each result as it lands.

`DEVELOPMENT_CHECKLIST.md`'s code map now puts Boss entirely in `modules/boss.lua` and
`modules/round.lua`, and the do-not-undo row for the attack queue names a test that actually
proves a client replays more than one attack. The row had pointed at
`test/suite/boss.lua`, which only pins the queue's size and the existence of its eight
synchronized fields.

### 2026-09-14 — R-002, fourth part: the load-time self-check moves to `modules/modifiers.lua`

`MODIFIER_KINDS` and `run_static_modifier_checks` left `main.lua` for `modifiers.lua`, which is
where the require graph put them: the check reads `GOALS` from `goals.lua`,
`NORMAL_MODIFIER_CATALOG`, `MODIFIER_AUDIT` and `MODIFIER_AUDIT_COUNTS` from `audit.lua`, and
`capped_horizontal_velocity`, `swap_button_bits` and `rotate_stick` from `modifiers.lua` itself.
`goals.lua` could not have it, because `audit.lua` already requires `goals.lua`. **The move
needed no new require edge at all** -- the first pass in this refactor that added none.
`main.lua` fell from 1,835 to 1,729 lines and `modifiers.lua` grew from 708 to 828.

Byte-identical in both directions, with no exception this time: `modifiers.lua` has no `goal()`
constructor, so the `for index, goal in ipairs(GOALS)` loop kept its name and the two blocks
diff clean against `HEAD:StarHunt/main.lua` in both directions. `main.lua` also lost four import
lines that only the check used, and gained one for the check itself.

**The area was almost entirely untested.** One test existed -- `mechanics` asserts the load
banner says "checks passed" and that no line says "failed" -- and it covers the happy path only.
Every refusal the check makes could be deleted with a green 382-test run: the required-power
list, the 100-coin exclusion for all fifteen main courses, the empty-modifier-list guard, the
accepted-kind gate, the cursed-floor 4-to-9-second range, and every hole the 93 x 32 audit
matrix could have. `test/suite/selfcheck.lua` adds 25 tests and the suite is now 407.

The useful shape the suite settled on: **every failure test asserts twice** -- that the right
complaint was printed, and that the success banner is gone. The second assertion is what catches
a branch that complains and then forgets `valid = false`, which is six separate mutations.
`harness.capture_print(fn)` is new and returns the captured lines plus the pcall result;
`harness.load` now uses it for the banner it was already capturing by hand.

**60 of 66 mutations caught.** The six survivors are equivalent mutants rather than gaps, and
they divide into two kinds:

- `or modifier_data.kind == "auto_crouch"` can be deleted with no effect. `MODIFIER_KINDS` has
  no `auto_crouch` key, so `not MODIFIER_KINDS["auto_crouch"]` is already true and the clause
  can never change the outcome. `auto_crouch` appears nowhere else in the mod. It was left
  exactly as it is: a move may not change the code it moves.
- The water-cap, A/B-swap and control-drift checks call helpers that are file-local to
  `modifiers.lua`, so no test can hand them a broken one. Their failure branches are unreachable
  from the suite (three `valid = false` mutations survive), and one condition -- `math.abs(x1 -
  x2) > 0.001 or ... z ...` -- can become `and` unnoticed because neither side is ever true.
  `swap_button_bits(A_BUTTON, A_BUTTON, B_BUTTON)` can also have its last two arguments swapped
  and still return `B_BUTTON`, because the call is symmetric. Only the shipped helpers are ever
  exercised there, and `test/README.md` now says so.

**Two things the check turns out not to do**, both found by the mutation sweep rather than by
reading it. It pins the catalog at 93 goals but never pins the modifier catalog at 32 entries --
the "32 modifiers" in its banner is a literal string, and `test/suite/catalog.lua` is what
actually holds that number. And the banner's audited-pair count could have been hard-coded
without any test noticing, because the only legal way to move that number is to change the size
of the catalog. `selfcheck` now does exactly that, with a thirty-third template repeating a kind
the matrix already holds.

**A live row in `DEVELOPMENT_CHECKLIST.md` was citing a v0.8 number.** Its do-not-undo table gave
"Matriz de 2.232 pares" as the check guarding impossible modifier pairs. 2,232 is 93 x 24, the
matrix as it stood when the catalog had 24 modifiers; the shipped matrix is 93 x 32 = 2,976.
`BALANCE_AUDIT.md` still carries 2,232 correctly, inside its "v0.8 additions" section. The row
now names the real matrix and the suite that checks it.

### 2026-09-14 — R-002, third part: `modules/goals.lua` is finished

The interaction handlers and star visibility left `main.lua` for `goals.lua`: `is_hmc_metal_portal`,
`in_castle_lock_level`, `has_interaction`, `on_allow_interact`, `on_interact`,
`reset_hidden_object_tracking` and `update_star_visibility`. `main.lua` fell from 1,972 to 1,835
lines and `goals.lua` grew from 721 to 877, which makes it the second-largest file in the mod
after `round.lua`. Two new require edges were needed and neither is a cycle: `save.lua` for
`remove_starhunt_save_flag` and `boss.lua` for `boss_has_modifier`, both of which require only
`core.lua`.

Byte-identical in both directions, with the same single exception for the third time: three
`local goal` declarations shadow this file's own `goal()` constructor and are `goal_data` here,
as `audit.lua` already does. That is 13 lines and nothing else — `rejection.goal` and the
`goal = goal_id` table key are not variables and were left alone.

**The mutation check found the area completely uncovered, exactly as it did for the cap code.**
`allow_interact` and `interact` were published in `STARHUNT_TEST_API` and called by no test at
all, and `update_star_visibility` and `reset_hidden_object_tracking` were not published at all.
Every guarantee in these 142 lines could be deleted with a green 353-test run: the castle lock
that stops a player leaving the lobby, the HMC Metal Cap portal, the whole star gate, Boss's
one-hit-death modifier, and the rule that only the invisibility flags StarHunt itself set are
ever cleared.

The most valuable thing the suite now pins is the rejection memory. Once a player has attempted
a star object that did not belong to their goal, that object stays refused for that player, goal
and round — because a spawned star keeps receiving object-sync updates, and without the memory an
act value arriving late would turn a star the player already tried into a valid target. Three
tests pin it, one per key, and a fourth proves one player's attempt does not bind another.

`test/suite/interact.lua` adds 29 tests and the suite is now 382. **All 78 mutations are caught**,
each by the test written for it — the first pass in this refactor with no survivor and no
unreachable case to document.

Two engine stubs had to be made real before any of it was reachable, which is the fifth and
sixth time that trap has been hit. `obj_has_behavior_id` returned `false`, so
`obj_has_behavior_id(o, id) == 0` was never true and the portal guard could not fire;
`obj_get_first` returned nil, so the object walk inside `update_star_visibility` never ran a
single iteration. Both now carry the engine's own `@return Object` annotation, which is not
decoration: lua-language-server merges a global defined in `test/harness.lua` with the engine
definition of the same name, and without the annotation the `object = obj_get_next(object)` walk
in `goals.lua` became a type error that raised the checker baseline from 10 problems in 2 files
to 11 in 3.

Also found and left alone, because it belongs to R-004 rather than here:
`DEVELOPMENT_CHECKLIST.md` names "Prueba de borrado por behavior ID" as the check guarding the
Lakitu fix, and **no such test exists** — nothing under `test/` mentions Lakitu. The stub change
made in this pass is what would let one be written.

### 2026-09-14 — R-002, second part: the required-cap code moves into `modules/goals.lua`

`power_flags`, `restore_starhunt_power`, `apply_goal_power` and their four state locals
(`STARHUNT_SPECIAL_CAP_MASK`, `local_starhunt_power`, `local_starhunt_added_flags`,
`local_power_original_timer`) left `main.lua` for `goals.lua`. `main.lua` fell from 2,033 to
1,972 lines and `goals.lua` grew from 645 to 721. One `require` line was needed in `main.lua`
and none in `goals.lua`: every name the block referenced was already there -- `local_runtime`,
`is_round_active` and `is_boss_mode` from `core.lua`, and `get_local_goal` and
`goal_matches_player_area` from `goals.lua` itself.

Byte-identical in both directions, with one deliberate exception that is now the second time
this exact trap has been hit: `apply_goal_power` declares `local goal`, which shadows this
file's own `goal()` constructor, so it is `goal_data` here exactly as `audit.lua` does.

**The mutation check found the area completely uncovered.** `apply_goal_power` was published
in `STARHUNT_TEST_API` as `power` and called by no test at all, and no suite mentioned
`capTimer` or any cap flag. That matters more here than in most passes, because
`DEVELOPMENT_CHECKLIST.md` lists "gorras desaparecían o quedaban permanentes" as a fixed bug
whose fix must not be undone, and the whole of that fix lives in these 57 lines. Every
guarantee in it could be deleted with a green 341-test run: removing the wrong cap, keeping a
cap forever, stealing a cap another mod granted, or never restoring the player's own cap timer.

`test/suite/caps.lua` adds 12 tests and the suite is now 353. 31 of 34 mutations are caught,
each by the test written for it. The three survivors are unreachable rather than untested and
are documented in the suite's header: `restore_starhunt_power`'s resets of
`local_starhunt_added_flags`, `local_runtime.power_external_timer` and
`local_runtime.power_original_head` are all written again by `apply_goal_power` on the only
path that can reach the next restore, so a stale value is never read. Confirmed by
`grep -rn "power_external_timer\|power_original_head" StarHunt/` -- nothing outside this block
reads either field.

One test found a real hole the first sweep exposed: a player who walks onto a Wing-cap star
already wearing a Wing cap from another mod. StarHunt adds nothing, so it must take nothing
away at the end -- and recording the whole required cap as "added" instead of only the missing
part passed every other test in the suite.

**`run_static_modifier_checks` cannot go to `goals.lua`, and this was measured rather than
assumed.** It needs `NORMAL_MODIFIER_CATALOG`, `MODIFIER_AUDIT` and `MODIFIER_AUDIT_COUNTS`
from `audit.lua` and `capped_horizontal_velocity`, `swap_button_bits` and `rotate_stick` from
`modifiers.lua`, and both of those modules already require `goals.lua`. R-002 had listed it as
part of this pass; it is now recorded against `modifiers.lua`, which already imports both.

### 2026-09-14 — R-002, first part: `modules/team.lua` is complete

The five declarations `team.lua` had been waiting for moved out of `main.lua`:
`TEAM_SCORE_PRIORITY_GAP`, `Team.participant_stats`, `Team.pick_late`, `Team.update_scores`
and `Team.update_manual_reroll_menu`. All 73 lines are byte-identical to the original and
`main.lua` reconstructs exactly from the previous commit minus the three ranges. `main.lua`
fell from 2,107 to 2,033 lines; `team.lua` grew from 189 to 271. No `require` line was needed:
all five attach to the shared `Team` table, which every module already reaches by reference.

**R-002 said these were unblocked because `player_record_key` is exported from `round.lua`.
They were not, and the reason is a require edge nobody had looked for.** `modifiers.lua`
requires `team.lua` for `on_allow_pvp_attack`, and `round.lua` requires `modifiers.lua` for
`grant_infinite_lives`, so the graph already runs `round → modifiers → team`. An import of
`round.lua` from `team.lua` would close that cycle, which makes round's export a route team
could never take. `player_record_key` needs nothing from round -- it reads `gNetworkPlayers`
and builds a string -- so it moved into `core.lua` beside `Team.host_player_records`, the table
it names entries in, in its own verified commit before anything else moved. That is the same
shape as R-001's migration of `host_player_records`, and the same rule the plan already states:
a shared helper moves into `core.lua` when the first module actually needs one.

**The whole area was untested: 25 of 28 mutations survived a green 325-test run.** Among the
survivors were putting every late joiner on the same team, counting a disconnected player's
score twice, publishing red's total as blue's, and renaming the mod menu button on every frame
for the whole session. Sixteen new tests in `test/suite/team.lua` bring that to 27 of 28, and
each mutation is caught by the test written for it rather than incidentally.

**The one survivor is unreachable rather than untested**, and is documented in the suite
header instead of being faked into a test: the `record.enrolled == 1` check in
`participant_stats`. Host records are written in exactly one place, which always writes
`enrolled = 1`; nothing ever lowers it, and a record is deleted rather than cleared.

**A fifth engine stub was hiding a branch.** `update_mod_menu_element_name` in
`test/harness.lua` only recorded a rename that landed on a button that exists, so a call aimed
at a nil index left no trace at all — and the guard that protects Co-op DX versions without a
mod menu could be deleted with the suite still green. It now records every call in
`ctl.menu_renames`.

What R-002 still has to settle: `goals.lua`'s interaction handlers, star visibility and power
flags; Boss's attack queue and hazards, still blocked by the `modifiers → boss` cycle; and a
home for `Team.host_update_chaos_round`.

### 2026-09-14 — R-001: the host half of the round moved into `modules/round.lua`

681 lines across nine blocks, proven byte-identical in both directions: the host half appears
verbatim in `round.lua`, the client half was untouched, and `main.lua` rebuilt from the
previous commit minus the deleted ranges plus the eleven import lines compared character for
character with the working file. `main.lua` fell from 2,780 to 2,101 lines; `round.lua` grew
from 207 to 949. The whole round loop now lives in one file.

**One preparatory change was needed first, in its own commit.** `host_start_round` replaces
`host_player_records` wholesale at the start of every round, and `Team.participant_stats` --
which belongs in `team.lua`, not in round -- reads it. A rebound local cannot be shared across
modules at all, so the table was migrated onto the shared `Team` table in `core.lua`, following
the pattern already used for the 23 locals moved onto `local_runtime` before the split began.
That also unblocks `team.lua`'s three deferred functions.

**The require graph settled two questions R-002 had open.** `round.lua` must require `boss.lua`
(the time range, the modifier slots, the health report) and `chaos.lua` (`CHAOS_REROLL_FRAMES`),
so an edge back the other way is a cycle. `host_update_boss_round` therefore **cannot** live in
`boss.lua` and moved into `round.lua` with the rest of the host half, and
`Team.host_update_chaos_round` **cannot** live in `chaos.lua` either -- R-002 has to decide
where it goes instead.

**The coverage this found was the worst of the refactor so far: 139 of 156 mutations survived
a green 212-test run.** Nothing in the suite drove the round loop past starting it. The new
`test/suite/round_host.lua` is 108 tests covering the clock, the goal pool, the winner tally,
the reconnect records, the per-frame loop and Bowser's attack scheduling; the suite went from
212 to 320 tests.

Two engine stubs were silently hiding whole branches from every test and were fixed in
`test/harness.lua`:

- `obj_get_first_with_behavior_id` returned `nil`, so **the entire Boss attack queue was
  unreachable** -- with no Bowser object the host loop always decided he was not ready and
  returned before choosing an attack. Tests now supply the object through `ctl.objects`.
- `djui_popup_create_global` discarded its second argument, so the round banner's height could
  be wrong with nothing noticing.

Two surviving mutations are equivalent and are documented in the suite rather than faked into
a test: `goal_is_active_for_anyone` starting its scan at player 1 (it duplicates a guarantee
`host_used_goals` already gives), and `winner_text_and_score` seeding its best score at -2
instead of -1 (scores are never negative). A third, the fallback in `host_assign_goal` when the
modifier filter empties, is unreachable because every goal in the catalogue has at least ten
allowed modifiers; what the suite guards instead is the filter itself, over 80 draws.

---

## The modularization of `main.lua`

Branch `refactor/modularize`, begun after v1.1 was declared final. `REFACTOR_PLAN.md` holds
the method; this is the record of what it produced. Remaining work is R-002 to R-004 in
`ROADMAP.md`.

### Where it started and where it stands

The released v1.1 `main.lua` was 5,171 lines and 271 top-level declarations, with 72 tests.
After eleven of the thirteen modules, `main.lua` is 2,101 lines and the suite is 320 tests.
Modules extracted, in order: `core`, `i18n`, `save`, `goals` (catalog only), `audit`,
`difficulty`, `team` (rosters, palettes, PvP), `boss` (data and health), `modifiers`, `chaos`
(all but the round loop), `round` (client side only), `boss` again (its readers), `round`
again (the whole host half).

luacheck fell from 26 warnings to 2 as modules left, because the 24 `shadowing upvalue goal`
warnings went with the `goal()` constructor. The type checker has stayed at 10 problems in 2
files throughout: 3 known `save_file_do_save(file, true)` false positives and 7 partial engine
stubs in `test/harness.lua`. **A rise in either is a regression.**

### The `local_runtime` migration, which came before any file moved

Measured on the released file: 53 of the 78 top-level locals were rebound at least once, 33 of
them from two or more top-level scopes. Exactly 5 were mutated only by field assignment and so
were already safe to share: `Team`, `local_runtime`, `MODIFIER_AUDIT`, `MODIFIER_AUDIT_COUNTS`
and `BOSS_ACTIVE_ATTACK_LOOKUP`.

Treating each variable and the scopes that rebind it as one bipartite graph gave 12 independent
state clusters. Eleven were self-contained and travelled with their own module. The twelfth was
the whole problem: **23 variables written from 14 scopes**, spanning boss hazards, chaos, death,
warping, interaction and star visibility. Without the migration that cluster would have dragged
all 14 writing functions into one module — `boss.lua` at 66 declarations and ~1,100 lines, with
a boss→modifiers coupling of 100 references.

Those 23 were moved onto `local_runtime` as four commits (`d532e86`, `2fec87b`, `d77bfe2`,
`8841aa9`) with no files moved at all. 135 references were rewritten via tree-sitter identifier
nodes, so strings and comments could not be touched. Afterwards: top-level locals 78 → 55,
locals rebound from two or more scopes 33 → 14, state clusters 12 → 11, and the largest cluster
23 variables / 14 scopes → 6 / 6, sitting entirely inside the future `round.lua`.

### What the mutation checks found

Every extraction was verified twice — byte-identity of the moved lines, then mutation of the
moved code. The second check found a real coverage gap in **ten of the twelve** passes, which
is the reason the habit continues.

| module | what was uncovered | what closed it |
|---|---|---|
| i18n | everything — `translated()` could return English always | 9 tests |
| save | the flush and retry logic; one assertion could never fail | 10 tests |
| goals | all catalog data — swapped English/Spanish columns, a retuned value, a typo'd world name | 18 pinned world names, and a digest over the whole catalog |
| core | every `local_runtime` initial value — a sentinel starting at 0, a dropped queue, a lock starting engaged | 4 invariants |
| difficulty | which direction "harder" runs per modifier | a per-kind direction table stated in the test |
| team | Team mode entirely — rosters, palettes, the PvP rule | the `team` and `world` suites |
| modifiers | the effects players actually feel | the `modifiers` suite |
| chaos | the entire mode — **all 17 mutations survived a green 138-test run** | 16 tests |
| round (client side) | the client's whole reaction to a round — **all 26 mutations survived a green 154-test run** | 34 tests |
| boss (readers) | how long a Boss round lasts, which of Bowser's modifiers are drawn, when his desperate phase begins, and which health figure the host believes — **all 28 mutations survived a green 188-test run** | 24 tests |

Areas that had *zero* coverage before the refactor began: Team mode, world-sharing, the PvP
rule, the goal readers, `local_runtime`'s initial values, the Boss data invariants, the
modifier entry points, and all of Chaos. Several of those were already published to
`STARHUNT_TEST_API` and simply never called by any suite.

Chaos was the worst until round's client side matched it. Chaos could have lost a level from
its map pool, handed every player the same modifier forever, ignored its 15-second reroll
interval, kept rerolling eliminated spectators, or warped a knocked-out player straight back
into the arena, with nothing reporting a problem. The client side of the round could have
failed to warp anyone home when a round ended, retried that warp every frame instead of once a
second, let a player quit mid-round from the pause menu, shown every nametag it was meant to
hide, permanently revealed a player another mod had made invisible, charged one death as two
forfeits or as none, or left Bowser's intro textbox blocking the Boss round.

### Two conclusions worth keeping

- **One surviving mutation is an equivalent mutant, not a gap.** This has now happened twice,
  both times around the same function. Removing the area comparison from
  `players_can_share_world` changes no answer, because `players_have_private_variant` re-decides
  the same way one line later. Removing the `index ~= 0` check from `on_nametags_render` changes
  no answer either: `players_have_private_variant` compares its two players symmetrically, so
  asked about player 0 twice it returns false down every branch. Both checks were left in place,
  and the test for the second says plainly that it pins the contract rather than guarding the
  code that meets it.
- **The catalog digest** in `test/suite/catalog.lua` (`e5cd39707be1e49f`) is an FNV-1a hash over
  every goal's level, act, world names, titles, power and hand-tuned values. It was computed
  from the release commit `2111c0b` and the catalog was confirmed byte-identical to the released
  file, so it asserts what shipped rather than what merely happens to be present.

---

## Historial de desarrollo v0.9 – v1.1

Archivado desde `DEVELOPMENT_CHECKLIST.md`, que ahora conserva solo lo vigente: el proceso
obligatorio, el mapa del código y la tabla de errores cuya solución no se debe deshacer.

### Lo que se publicó, y su hash

Dos entregas llegaron a los jugadores. El identificador de cada una se conserva aquí porque
`PROJECT_STATUS.md`, que era donde vivía, se retiró el 17 de septiembre de 2026.

- **v1.1**, del 30 de julio de 2026, un solo `main.lua`. SHA-256 del archivo publicado:
  `EBC76DBEC1554D24522E907B49FF2DE5948282029E95C6DA51C31B42A906B883`.
- **v1.1.1**, del 16 de septiembre de 2026, ya repartido en catorce archivos. Un solo hash
  dejó de identificar al mod, así que el identificador es el SHA-256 de la lista ordenada de
  los hashes de todos los `.lua` bajo `StarHunt/`:
  `E4677DF5C91F14519C50D41AB4E548B89F1B1430ADCC5534121DC68C21024F53`.

El identificador se recalcula así:

```bash
(cd StarHunt && find . -name '*.lua' | sort | xargs sha256sum | sha256sum)
```

Las etiquetas `v1.1-monolithic`, `v1.1-modular` y `v1.1.1` marcan esos árboles en git. Los
hashes intermedios que `PROJECT_STATUS.md` acumulaba — el árbol antes y después de cada
corrección — no se conservaron: ninguno se publicó, y el comando de arriba los vuelve a
calcular sobre el commit que interese.

### Cambios implementados en v1.1

Estos ítems estaban bajo «Cambios pendientes» y todos están implementados.

- **2026-08-04 — reserva de bombas de Boss (implementado):** evitar que Hard y
  Nightmare queden sin forma de terminar la pelea cuando desaparecen las cinco
  bombas originales de Bowser in the Sky. El host debe confirmar primero que
  las cinco bombas nativas llegaron a cargarse y, cuando su contador llegue a
  cero, crear una sola oleada sincronizada en posiciones originales elegidas
  sin repetir: dos bombas en Hard y cuatro en Nightmare. Easy y Medium no deben
  crear bombas adicionales. Dos campos globales sincronizados conservarán el
  avistamiento y la oleada ante entradas tardías o un cambio de host.

- **2026-08-04 — Pulsos Easy y parejas Nightmare (implementado):** corregir el
  reinicio tardío que reduce a un solo fotograma las restricciones pulsadas de
  Easy; hacer simétrica la validación de parejas para que invertir el orden no
  permita efectos que se cancelan; y excluir combinaciones donde un reto obliga
  a detenerse mientras otro castiga hacerlo. La solución solo toca estado local
  de modificadores y selección autoritativa del host, sin cambiar objetivos,
  puntuación, guardado ni la cantidad de retos.

- **2026-08-01 — Retos redundantes y congelación estable (implementado):** sustituir
  `landing_stun`, que inmoviliza después de casi cada salto y se solapa con
  `periodic_freeze`, por un reto de monedas mecánicamente distinto. Durante la
  congelación periódica también se fijará la orientación de Mario antes y
  después del moveset para impedir giros residuales. Se conservarán los 32
  modificadores, la dificultad independiente y la auditoría por estrella; se
  añadirán regresiones directas antes de instalar.

- **2026-07-31 — Apertura obligatoria del menú de espera (implementado):** abrir el menú de
  StarHunt automáticamente cuando todavía no existe una ronda activa, consumir
  B/START y cualquier intento de alternarlo mientras se espera, y cerrarlo para
  todos cuando comience la ronda. Si la ronda termina, el menú debe reaparecer.
  La solución conserva el bloqueo existente de movimiento y el control del host;
  no modifica objetivos, balance, guardado, red ni compatibilidad de modos.

### Arquitectura añadida en v1.0

#### Revisión v1.1

- v1.1 parte de la fuente final verificada de v1.0 y no modifica ese respaldo.
- `/starhunt updates` explica el propósito del mod, los cuatro modos, la
  independencia de la dificultad y los cambios principales de v1.1.
- El comando informativo usa el mismo registro `/starhunt`; no añade entradas
  duplicadas a `/help`.
- La prueba inicia las 16 combinaciones de cuatro modos por cuatro dificultades
  y comprueba sus invariantes principales.
- Los textos del comando se comprueban en los seis idiomas.

- `Team.CHAOS` es eliminación todos contra todos: no asigna estrellas y gana el
  último jugador vivo.
- El host elige uno de los 15 mundos principales y un acto al azar. Todos son
  enviados al mismo nivel, área y variante para que el PvP sea posible.
- En Chaos cada jugador recibe sus propios modificadores, que cambian cada 15
  segundos. Easy, Normal y Hard asignan uno; Nightmare asigna dos distintos y
  compatibles por jugador.
- En Normal y Team, Nightmare asigna dos modificadores compatibles a cada
  jugador. En Boss asigna dos modificadores de jugador, conserva las tres
  ventajas de Bowser y mantiene sus 9 puntos de vida.
- Las estrellas quedan ocultas e inusables. Morir marca al jugador como
  eliminado y lo envía al castillo como espectador.
- CHAOS requiere al menos dos jugadores. Las entradas tardías son espectadores
  y no pueden atacar ni recibir ataques.
- `sh5_difficulty` sincroniza Easy, Medium, Hard o Nightmare. El valor queda
  bloqueado mientras una ronda está activa.
- `Team.effective_modifier_for_goal()` aplica la dificultad y vuelve a pasar el
  resultado por la auditoría de la estrella. Una dificultad nunca debe saltarse
  los filtros mecánicos ni los márgenes numéricos.
- Normal conserva los valores de v0.9. Easy convierte restricciones binarias en
  pulsos de tres segundos; Hard y Nightmare aumentan presión, daño y frecuencia.
- Boss usa 3/5/7/9 puntos de vida según dificultad y acelera sus ataques en Hard
  y Nightmare.
- Los idiomas locales son inglés, español, portugués de Brasil, francés, alemán
  e italiano. Cambiar idioma nunca modifica el estado sincronizado de la ronda.
- Los nombres propios de estrellas sin traducción segura conservan el texto
  original de SM64; menú, dificultad, modos y modificadores sí se localizan.

### Historial heredado del tercer piso

Objetivo: añadir **Tick Tock Clock** y **Rainbow Ride**, seis estrellas por
curso y sin las de 100 monedas. El total pasará de 75 a 87 objetivos.

1. Añadir ambos mundos y sus 12 objetivos, con títulos inglés/español.
2. Marcar las rutas con espera, precisión, plataformas, vuelo, cañón y botones
   requeridos antes de elegir retos.
3. Ejecutar de nuevo las cuatro etapas de auditoría **solo para las 12 nuevas
   estrellas**, además de mantener la matriz global.
4. Probar visualmente cada reto candidato: plataformas de TTC, péndulos,
   agujas, alfombra mágica, barco y secciones de Rainbow Ride.
5. Rechazar combinaciones que pidan esperar quieto, dependan de un salto
   perfecto o requieran un botón bloqueado.
6. Añadir pruebas automáticas para los casos mecánicos conocidos; lo que no se
   pueda simular se marca para prueba humana.
7. Actualizar límites de tiempo según 87 estrellas y hasta 16 jugadores.

#### Riesgos específicos del tercer piso

- **TTC:** tiempos variables, péndulos y plataformas pueden hacer injustos
  Piso Maldito, Sigue Moviéndote, Congelación, Gravedad Alta y controles
  alterados.
- **Rainbow Ride:** alfombra mágica, barco, cañones y vuelo hacen sensibles
  los retos de velocidad, saltos limitados, viento y control aéreo.
- Ninguna estrella debe aprobarse solo porque el código no falla: debe tener
  una ruta humana con margen de error.

### Historial de cambios cerrados

| Pedido | Solución propuesta | ¿Confirmada? | Pruebas necesarias |
|---|---|---:|---|
| Tercer piso | TTC + RR, 12 estrellas sin 100 monedas | Implementado; falta prueba humana | Auditoría nueva + prueba humana |
| Big Boo's Haunt | Seis estrellas normales; los jefes conservan B y las rutas precisas se auditan | Implementado; falta prueba humana | Auditoría BBH + prueba humana |
| Borrado inmediato al terminar | Host limpia al cerrar; cada cliente limpia al recibir la orden de volver al lobby | Implementado | F12 + retorno global tardío |
| HUD sin `X` | Render común que convierte `:` en dos puntos dibujados | Implementado | HUD normal, Boss y menú |
| Menú repetía acciones al mantener un botón | Detectar pulsaciones nuevas con un registro propio hasta soltar el botón | Implementado | Mantener dirección/A varios frames y exigir una sola acción |
| Nombre del mod con colores seguros | Amarillo para Star, celeste para Hunt, blanco para v1.1 y cierre en gris predeterminado | Implementado | Validar encabezado exacto, longitud, sintaxis y carga |
| Movimiento residual con menú abierto | Anular velocidad horizontal, velocidad de deslizamiento e impulso frontal | Implementado | Abrir menú con impulso activo y exigir velocidad horizontal cero |
| Cambio de personaje durante TEAM | Asociar la paleta guardada a la identidad del modelo y no restaurarla sobre otro personaje | Implementado | Cambiar modelo antes y después de una actualización de paleta |
| Asignación TEAM tras desconexiones | Equilibrar jugadores conectados y, con empate numérico, ayudar al equipo que pierde por 2+ puntos | Implementado | Reserva desconectada, diferencia de 1 punto y diferencia de 2 puntos |
| Compatibilidad con mods populares | Mantener HUD de Day/Night y Gun Mod sobre DARKNESS PULSE, impedir fuego aliado de sus balas, coordinar el menú de WiddlePets y reaplicar límites seguros tras movesets personalizados | Implementado; falta prueba humana | Capas HUD, bala aliada/rival/Boss/área privada, exclusión de menús y límites posteriores al moveset |
| `/help` repetía StarHunt tres veces | Registrar únicamente el comando exacto y en minúsculas `/starhunt` | Implementado | Exigir un solo registro llamado `starhunt` |
| Revisión integral y HUD nocturno | Separar marcador, reloj, objetivo y vida en paneles legibles; sustituir la barra de vida por ocho segmentos; corregir solamente fallos demostrables sin cambiar reglas de balance | Implementado; Normal panorámico verificado dentro del juego | Geometría y colores del HUD, 0/1/4/7/8 de vida, Normal/Boss/TEAM, textura opaca, 30 regresiones completas y prueba visual Normal 1920x1009 |
| StarHunt v0.9 | Añadir ocho modificadores auditados; completar el menú español; inmovilizar por completo al jugador mientras el menú está abierto; permitir que aliados y rivales se vean al coincidir en nivel y área durante TEAM; reforzar la identificación azul/roja usando todas las partes de paleta que admite el motor | Implementado y automatizado; falta prueba humana. Los botones amarillos fijos del modelo no son una parte de paleta expuesta por Lua | Matriz ampliada, efectos aislados, posición/velocidad del menú, texto español, visibilidad, PvP, paleta y restauración |
| Posición final del objetivo | Restaurar la composición compacta de v0.7: nivel, estrella y modificador centrados directamente en la parte superior, sin una tarjeta que ocupe casi toda la pantalla; escalar dentro del espacio entre los paneles laterales | Implementado y automatizado; la captura real confirmó el fallo anterior y falta validar visualmente la corrección | Normal, TEAM, Boss, 320 y 426 unidades; comprobar textos en `y = 3/15/28/40`, centrados y sin panel de objetivo |
| COIN TOLL rehabilitaba una estrella incorrecta | Recordar por jugador que un objeto de estrella ya fue rechazado para el objetivo y ronda actuales, y mantenerlo bloqueado aunque después se pague el peaje o cambien sus parámetros sincronizados | Implementado y automatizado; falta prueba humana | Rechazar estrella incorrecta antes de 20 monedas, mutar su ID, pagar el peaje y exigir que siga bloqueada; la estrella asignada debe habilitarse |
| Retiro de v0.7 y v0.8 | Eliminar sus fuentes, instalaciones y pruebas auxiliares sin tocar v1.0 | Implementado | Verificar que no quede ninguna ruta o archivo de esas versiones |
| Comando de novedades v1.1 | Usar `/starhunt updates` para explicar mod, modos, dificultad y cambios sin crear otra entrada en `/help` | Implementado | Comando, alias, texto y seis idiomas |
| Cierre del proyecto | Eliminar v0.9, conservar v1.0 como respaldo y declarar v1.1 como versión final | Implementado | Ausencia de v0.9, hashes de v1.0/v1.1 y documento de estado |
| Botón Otro nivel | Añadirlo al menú de pausa de SM64CoopDX, limitarlo a Normal/Team, exigir dos minutos por objetivo y escoger otro curso | Implementado y automatizado; falta prueba visual | Entrada tardía, 1:59.29, 2:00, doble pulsación, curso distinto, reinicio del temporizador, Boss/Chaos |

### Correcciones de estabilidad posteriores

| Problema | Solucion aplicada | Estado |
|---|---|---:|
| Retos antes de llegar | Activar reto y gorra solo cuando nivel, acto y area coinciden | Implementado |
| Agua invisible global | Conservar la altura hallada y bajar solo las regiones reales del foso | Implementado |
| Reconexiones mezcladas | No reutilizar el slot si el nombre del jugador cambio | Implementado |
| Bowser se curaba | La vida autoritativa solo puede bajar durante una ronda | Implementado |
| Ataques diferidos perdidos | Guardar ondas y meteoritos en colas independientes | Implementado |
| Un cuadro de animacion de muerte | Cancelar acciones mortales antes de que comiencen | Implementado |
| Menu filtraba controles | Consumir todos los botones, camara y stick mientras esta abierto | Implementado |
| HUD ajeno modificado | Guardar y restaurar flags solo al entrar y salir de una ronda | Implementado |
| Lakitu ya cargado | Escaneo periodico ademas de `HOOK_ON_OBJECT_LOAD` | Implementado |
| BBH incompatible | Aislar actos distintos solo dentro de habitaciones | Implementado |
| Lobby grande sin objetivos | Reducir el maximo de tiempo entre 8 y 16 jugadores | Implementado |
| Objetivo centrado en la zona superior | Texto compacto de v0.7 sin tarjeta; reservar las esquinas para puntuación, vida y reloj; ancho adaptativo limitado al hueco central | Implementado |
| COIN TOLL aceptaba una estrella rechazada previamente | Registrar el rechazo por objeto, jugador, objetivo y ronda; limpiarlo al recargar el nivel | Implementado |
| Mario podía rotar durante Congelación Periódica | Capturar su orientación al congelarse y reaplicarla después del moveset; liberarla al finalizar el efecto | Implementado |
| Aturdimiento al aterrizar repetía otra inmovilización | Sustituirlo por Impulso de moneda, auditar su velocidad y evitar parejas Nightmare que anulan el impulso | Implementado |
| Restricciones Easy duraban un solo fotograma | Inicializar la clave y el reloj del reto antes de comprobar su ventana pulsada | Implementado |
| Slippery Easy recuperaba velocidad de un pulso anterior | Limpiar la inercia privada durante cada intervalo inactivo | Implementado |
| Parejas Nightmare dependían del orden | Consultar los conflictos de ambos modificadores y probar las 496 parejas en ambos sentidos | Implementado |
| Nightmare podía obligar a detenerse y castigar esa detención | Incompatibilizar Congelación con Sigue moviéndote y Piso maldito; aplicar el filtro también en Boss | Implementado |
| Hard/Nightmare podían agotar las cinco bombas antes de derrotar a Bowser | Tras observar y agotar las cinco nativas, crear una sola reserva sincronizada de 2/4 bombas en posiciones originales aleatorias y distintas | Implementado |

### StarHunt v0.9 — TEAM

- `MODE_TEAM` conserva objetivos individuales, pero suma resultados por equipo.
- `starhunt_lifetime_stars` es local, permanente y no aparece en pantalla.
- Los equipos se equilibran por experiencia y nunca difieren en más de una persona.
- Los participantes desconectados conservan puntuación y objetivo, pero no
  ocupan una plaza activa al asignar jugadores nuevos.
- Una reconexión recupera su equipo anterior si el balance activo y una
  desventaja de dos o más puntos no requieren asignarla al otro equipo.
- `sh5_team` debe sobrevivir reconexiones y limpiarse al terminar.
- El fuego amigo se bloquea; los rivales requieren mundo y geometría compatibles.
- Las ocho partes de la paleta se guardan, pintan y restauran exactamente.
- TEAM no puede iniciar con menos de dos jugadores.
- Los nuevos retos pasan por la misma matriz de auditoría de cuatro etapas.

### Verificación histórica de v0.9

- 93 objetivos y 32 modificadores.
- 2.976 pares auditados: 2.222 aprobados y 754 rechazados.
- Los ocho efectos nuevos tienen pruebas mecánicas directas.
- El menú español, el bloqueo de posición XYZ y la velocidad vertical están
  cubiertos.
- TEAM permite visibilidad/PvP entre actos distintos al coincidir en nivel y
  área, mantiene el fuego amigo bloqueado y conserva el aislamiento entre
  áreas.
- La cobertura heredada de v0.8 permanece integrada en la prueba de v1.1; las
  copias y pruebas independientes de v0.8 fueron retiradas por solicitud.
- La prueba humana dentro del juego sigue siendo necesaria para dificultad,
  apariencia, geometría entre actos y modelos personalizados.

Las fuentes, instalación y prueba independiente de v0.9 fueron eliminadas al
cerrar el proyecto. Su comportamiento heredado permanece integrado en v1.1.

### Verificación automatizada de v1.1

- `lua -e "assert(loadfile('StarHunt_v1.1/main.lua'))"` pasa.
- `lua work/starhunt_v11_load_test.lua` pasa completo.
- La prueba conserva los flujos heredados Normal, Boss y Team.
- Las cuatro dificultades se prueban sobre el catálogo y conservan la auditoría
  heredada de 2.976 pares estrella/modificador en Normal y Team.
- Cada dificultad conserva modificadores personales válidos para Chaos.
- Se prueban mapa y acto compartidos, ausencia de estrella, un modificador
  personal por jugador en Easy/Normal/Hard, dos por jugador en Nightmare,
  incompatibilidades, renovación a 15 segundos y contador de saltos.
- Se prueban eliminación, espectador tardío, bloqueo de estrellas, PvP exclusivo
  entre supervivientes y victoria del último jugador vivo.
- Se verifica que Nightmare pueda formar una pareja compatible en los 93
  objetivos y que Normal, Team, Boss y Chaos reciban el modificador adicional.
- Se prueban los cuatro idiomas añadidos en el menú.
- Se prueban las 16 combinaciones de modo y dificultad.
- `/starhunt updates` conserva una sola entrada en `/help` y se prueba en los
  seis idiomas.
- El menú de pausa registra un solo botón `Otro nivel`; el host valida los dos
  minutos, evita el curso anterior y reinicia el temporizador al reasignar.
- Se prueba que Normal conserva valores, Easy pulsa restricciones y Nightmare
  eleva la vida de Bowser a 9.
- Se prueba que una arena todavía sin cargar no activa la reserva; Nightmare
  crea cuatro bombas y Hard dos, sin repetir posiciones originales, sin una
  segunda oleada y sin alterar Medium.
- SHA-256 de `main.lua`:
  `EBC76DBEC1554D24522E907B49FF2DE5948282029E95C6DA51C31B42A906B883`.
- Fuente e instalación de v1.1 coinciden por SHA-256. v1.0 permanece intacta
  como respaldo; v0.9 fue eliminada al finalizar el proyecto.
- Estas comprobaciones no sustituyen una prueba visual y de red dentro de
  SM64CoopDX.
- Se prueba al menos una ronda Normal y una Boss si el cambio toca red, HUD,
  gorras, muerte o retorno.
