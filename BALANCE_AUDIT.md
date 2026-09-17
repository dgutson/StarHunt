# StarHunt v1.1 — Modifier and difficulty audit

## Coverage

- 93 goals: all 15 main courses plus the three Cap courses.
- 32 Normal/Team/Chaos modifiers.
- 2,976 goal/modifier pairs checked by compatibility rules.
- 2,222 approved pairs.
- 754 rejected pairs.
- All 15 100-coin stars remain excluded.

## Difficulty guarantees

- **Easy:** the same catalog remains available, numeric penalties are softened,
  damage is reduced and permanent binary restrictions become 3-second pulses
  in a 10-second cycle.
- **Normal:** exactly preserves v0.9 modifier values and Boss balance.
- **Hard:** strengthens values, raises Boss health to 7 and shortens Boss attack
  intervals, while retaining every per-goal safety rejection. After the five
  native arena bombs are exhausted, one synchronized reserve supplies the two
  additional bombs required by the seven-hit health total.
- **Nightmare:** uses the strongest values allowed by the same mechanical and
  numeric audit, raises Boss health to 9 and permits 2-second minimum attack
  intervals. It adds one compatible modifier in every mode: two personal
  modifiers in Normal/Team, two player modifiers in Boss and two personal
  modifiers per player in Chaos. “Absurd” does not mean knowingly impossible.
  Its one synchronized reserve supplies four bombs after the five native bombs
  are exhausted, matching the nine-hit health total.
- The effective value is re-audited for the active goal after difficulty
  scaling. Rejected results cannot be assigned.

## Chaos pair audit

- Chaos has no star objective. All players fight on one randomly selected main
  course and act, and the last living player wins.
- Easy, Normal and Hard assign one independent modifier to every living player.
  Each player's modifier rerolls every 15 seconds.
- Nightmare assigns two distinct compatible personal modifiers to every player.
- Pairs that cancel controls or create known unfair locks are rejected:
  B-lock/A-B swap, reverse/mirror control families and low-jump/high-gravity.
- Pair validation is symmetric: reversing first/second modifier order cannot
  bypass a conflict. Periodic Freeze cannot pair with Keep Moving or Cursed
  Floor, and Control Pulse cannot partially cancel either mirror modifier.
- Nightmare Boss uses the same player-modifier compatibility filter.
- Coin Toll is excluded because there is no target star to unlock.
- Death eliminates instead of assigning a new objective. Late joiners spectate,
  stars cannot be collected, and eliminated players cannot deal or receive PvP
  damage.
- Automated tests verify shared warping, independent personal rerolls, elimination, late
  spectators and correct last-player-standing results.

## Four-stage process

1. **Mechanical filter:** rejects a modifier when it removes a required button, affects a star with no relevant mechanic, or makes a Wing Cap route lose reliable altitude.
2. **Route filter:** rejects known bad combinations for precision routes, races, forced waiting, cannons and forced slides.
3. **Per-star tuning:** values written in each goal definition override catalog defaults. Untuned long or precision routes receive conservative fallback values.
4. **Numeric safety limits:** speed cap is never below 32, low-jump vertical speed never below 38, gravity penalty never exceeds 1.1, air control never falls below 60%, jump cooldown never exceeds 26 frames, Coin Surge never adds more than 20 speed per coin, Momentum Burst never adds more than 14 speed, Control Pulse never lasts more than 45 frames and Gravity Wave never adds more than 0.6 downward velocity per frame.

These checks are a conservative compatibility matrix, not an automated playthrough of all 2,976 combinations. Real multiplayer route testing remains necessary, and feedback should be recorded as a per-star override or rejection.

## Big Boo's Haunt audit

- Six normal goals were added; its 100-coin star is excluded.
- All 192 goal/modifier pairs were checked: 126 approved and 66 rejected.
- Ghost Hunt, Merry-Go-Round and Big Boo's Balcony reject B Button Locked,
  because their Big Boo fights require punching.
- Haunted Books, Big Boo's Balcony and Eye to Eye are precision routes, so
  they reject low jumps, high gravity, wind, weak air control, turbo,
  slippery movement, drifting controls, coin surge and jump cooldown.
- Every mansion route rejects wind, turbo, slippery movement, drifting
  controls, which would make its cramped rooms unreliable.
- Eye to Eye receives the Vanish Cap for the secret room.

## Third-floor audit

- Tick Tock Clock and Rainbow Ride add 12 goals.
- Their 384 goal/modifier pairs were audited separately.
- 160 pairs were approved and 224 rejected.
- All 12 reject low jump, high gravity, wind gusts, weak air control,
  turbo, slippery shoes, wavy controls, coin surge, jump cooldown,
  periodic freeze and the water-only modifier.
- The same 12 routes reject Slow Pulse, Air Mirror, Momentum Burst, Control
  Pulse and Gravity Wave. Coin Leak, Coin Weight and Overheat remain usable
  because they do not take control away on a precision platform.
- TTC Acts 1-5 and Rainbow Ride Acts 1, 2 and 6 also reject Keep Moving
  because their normal route contains forced platform or cannon waiting.
- Cursed Floor is 9 seconds on moving-platform routes and 8 seconds on
  TTC's stopped-clock red-coin route.
- TTC Acts 1-5 force slow clock speed; Act 6 forces stopped time.

## Existing modifiers

- **A/B Buttons Swapped:** remaps pressed and held input states.
- **Keep Moving:** defeats a player after three stationary grounded seconds; excluded from forced-wait and water routes.
- **Jump Cooldown:** adds a 24-frame delay after a grounded jump; excluded from flight and precision routes.
- **Coin Surge:** collecting a coin adds 12 forward speed, capped at 64 total speed; red/blue coin gains are capped to two boosts. Difficulty scales the boost from 9 in Easy to 19 in Nightmare. It is excluded from courses without reliable coins and from flight, precision, race and slide routes.
- **Wavy Controls:** rotates analog input gradually by at most 20 degrees; excluded from precision and slide routes.

## Automated verification

- Lua syntax compilation.
- Startup matrix for all 16 game-mode/difficulty combinations.
- Complete matrix-count and entry-presence checks.
- Modifier kind and numeric bounds.
- No act-7/100-coin goals.
- Required cap combinations.
- Water-cap idempotence.
- A/B remapping and analog rotation calculations.
- Runtime behavior for all 32 modifier kinds.
- Periodic Freeze pins Mario's facing before and after custom movesets, then
  releases it on the exact frame the freeze ends.
- Coin Surge triggers only after a real coin-count increase and has a hard
  audited boost limit.
- Easy restrictions are tested across their complete inactive/active cycle;
  the three-second window must persist beyond its first frame.
- Easy Slippery clears private momentum between pulses instead of reviving an
  old speed. All 496 unordered modifier pairs are checked in both directions.
- HUD geometry for Normal, TEAM and Boss at 320- and 426-unit widths.
- The objective uses the compact v0.7 top-center layout at both widths: level,
  star and modifier begin at y=3, y=15 and y=28, with optional counters at
  y=40. No screen-wide objective card is rendered, and adaptive scaling keeps
  the text between the corner status cards.
- Health decoding at 0, 1, 4, 7 and 8 wedges, including safe, warning and
  danger colors.
- Opaque star/coin textures, colon-safe text and synchronized Boss health.
- COIN TOLL keeps a star object blocked after it was rejected for the current
  player, goal and round, even if its synchronized behavior parameters later
  change to the assigned star ID after the 20-coin toll is paid.
- `/starhunt updates` explains the mod, modes, difficulty and v1.1 changes in
  all six supported languages without registering another `/help` command.
- The in-game Mods menu exposes one Another Level button in Normal/Team. The
  host rejects requests during the first 120 seconds, selects a different
  course and restarts the cooldown after every assignment.

## v1.1 additions

- Keeps v1.0 intact as the previous stable version.
- Adds `/starhunt updates`; `update`, `actualizaciones` and `cambios` are
  accepted aliases after `/starhunt`.
- Preserves the requirement that `/help` list only the lowercase `starhunt`
  command.
- Adds explicit start-state checks for Normal, Boss, Team and Chaos under Easy,
  Normal, Hard and Nightmare.
- Moves the language preference to `starhunt_v11_language` while importing the
  v1.0 preference on first use.
- Adds an authoritative two-minute manual objective reroll in the SM64CoopDX
  pause menu; Boss and Chaos cannot use it.

## HUD redesign and visual QA

- Normal, TEAM and Boss now use separate status, timer, health and objective
  panels instead of sharing one crowded top row.
- Personal health uses eight discrete wedges. Green, amber and red replace the
  long blue bar and the visually noisy `8/8` fraction.
- Boss Mode adds a five-wedge synchronized Bowser-health panel; the previous
  HUD exposed no direct shared-health readout.
- The start banner remains separated from the compact top objective text.
- A real 1920x1009 SM64CoopDX v1.5.1 Normal round verified the earlier wide
  layout, readable colon and eight health wedges. A later real-game capture
  showed that the 252-unit objective card still occupied almost the full
  screen width and started too low. The source now restores the text-only
  v0.7 arrangement with automated coverage; this latest change still needs a
  new visual pass.
- That real-game pass exposed a translucent star inherited from the panel
  border. Star and coin textures now reset to opaque white immediately before
  rendering, and an automated regression test covers the failure.
- Temporary QA auto-start code was used only in an isolated direct session;
  it is absent from both the source and installed final `main.lua`.

## TEAM assignment

- Initial teams remain balanced by connected-player count and lifetime stars.
- Disconnected participants keep their score and objective but do not occupy an
  active roster slot for a new assignment.
- A new or returning player first fills the smaller connected roster.
- With equal rosters, a team trailing by at least two points receives priority.
- A reconnect keeps its previous team when neither roster balance nor the
  two-point comeback rule requires the opposite team.

## v0.8 additions

- `DAMAGE EVERY 6 SEC`: one curable health wedge every six seconds.
- `COIN TOLL`: requires 20 coins, is limited to the fifteen main courses and
  cannot rehabilitate a star object already rejected for the current goal.
- `DARKNESS PULSE`: 1.2 seconds of darkness every ten seconds; rejected on
  flight, races, dynamic precision and unsafe waiting platforms.
- `MIRRORED STEERING`: flips only horizontal steering; rejected on flight,
  races, slides and precision routes.
- Full matrix: 93 goals × 24 modifiers = 2,232 audited pairs.
- Required-B filtering for combat and wall-kick goals.
- Real-displacement detection for Keep Moving.
- Wind-gust recovery when an exact timer frame is skipped.
- Periodic-freeze recovery when its original frame window is skipped.
- Zero-based save-course targeting and forced cleanup.
- Normal and Boss start/stop flow.
- Internal-area visibility and PvP isolation.
- Reconnection and delayed lobby return.
- Bowser health ownership, modifier uniqueness, active-attack selection, queued lag recovery and attack gating.
- Boss reserve gating before level load, exact 2/4 counts, distinct vanilla
  positions, synchronized object type and one-shot behavior.
- Silent attacks, local death recovery and temporary Bowser disappearance.
- Camera Lakitu deletion, life/HUD restoration and cap ownership.
- Correct encoded health-wedge display.
- Twelve third-floor goals and their separate 288-pair audit.
- Six Big Boo's Haunt goals, its Vanish Cap and required-B filtering.
- Deterministic slow/stopped TTC state and private-world isolation.
- Colon-safe HUD rendering for every StarHunt HUD string.
- A single lowercase `/starhunt` registration, avoiding duplicate `/help`
  entries from capitalization aliases.

## v0.9 additions

- **Coin Leak:** removes exactly one coin every five seconds; Cap courses reject
  it because they do not have a reliable coin supply.
- **Slow Pulse:** caps movement at 32 for 1.5 seconds every eight seconds.
- **Air Mirror:** reverses only horizontal input and only while airborne.
- **Momentum Burst:** adds 12 forward speed every eight seconds while the
  player is grounded and actively moving.
- **Control Pulse:** reverses both stick axes for 1.2 seconds every nine
  seconds.
- **Coin Weight:** gradually lowers the speed cap as coins accumulate, with a
  hard safety floor of 35.
- **Gravity Wave:** alternates every three seconds between normal gravity and a
  mild extra downward acceleration.
- **Overheat:** removes one curable health wedge after two continuous seconds
  above 48 forward speed.
- Full matrix: 93 goals × 32 modifiers = 2,976 audited pairs.
- All eight new mechanics have direct runtime tests and every approved
  modifier still executes at least one neutral frame.
- The menu defaults to Spanish on a fresh v0.9 install, preserves an earlier
  saved language choice and translates the mode values to `JEFE` and
  `EQUIPOS`.
- The menu pins all three position axes in both Mario-update phases, clears
  vertical and horizontal velocity, and still requires a release before a
  held control can act again.
- TEAM visibility and PvP now use the players' current level and area instead
  of requiring the same assigned goal act. Normal mode retains its conservative
  geometry isolation.

## TEAM palette scope

- SM64CoopDX exposes eight per-player palette parts: pants, shirt, gloves,
  shoes, hair, skin, cap and emblem. StarHunt captures, colors and restores all
  eight, including Character Select model changes.
- The yellow overall buttons in the stock Mario geometry are not a ninth
  `PlayerPart`; the Lua palette API cannot recolor them independently.
- Replacing the entire player model just to alter those vertices would break
  Character Select and custom-model compatibility, so v0.9 deliberately keeps
  the player's model and colors every part the engine exposes.

## Popular-mod compatibility safeguards

- `DARKNESS PULSE` now renders behind normal HUD elements, chat and mod HUDs
  instead of covering them in the regular HUD layer.
- Day/Night Cycle's public behind-HUD hook draws the pulse before its clock;
  the frame guard prevents a later duplicate rectangle from covering it.
- Gun Mod's ammo and crosshair are repeated above an active darkness pulse.
- Gun Mod's public Mario hitbox follows the same StarHunt PvP decision as
  ordinary attacks: allies, Boss teammates and private world variants are
  protected, while valid Normal/TEAM rivals keep the original gun damage.
- Opening `/starhunt` closes WiddlePets' menu, and WiddlePets cannot reopen
  while the StarHunt menu owns the controller.
- Speed, jump, swimming and Fragile caps are rechecked after custom moveset
  updates. Cumulative effects and input remaps are intentionally not repeated.
- Night Mode, Weather Cycle, Environment Tint and Bubble Chat require no
  state takeover from StarHunt; keeping the darkness rectangle behind their
  HUD preserves their own rendering and lighting ownership.
- Weather Cycle 1.2.1 requires Day/Night Cycle API 2.6.0 or newer. An older
  Day/Night installation is an external dependency mismatch, not a StarHunt
  round-state error.

## Known limits

The automated suite does not claim that the following real-game scenarios were
visually verified:

- Human difficulty and route margin for every approved pair.
- Real network ownership transfer with multiple machines.
- OMM, Character Select and popular-mod combinations.
- Real TEAM and Boss HUD layouts with multiple machines and unusual aspect
  ratios. Normal widescreen was visually verified previously.
