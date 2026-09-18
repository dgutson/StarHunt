#!/usr/bin/env bash
#
# Run StarHunt inside real headless sm64coopdx processes and read back what the
# probe mod saw.  This is the only check in the repository that exercises the
# game itself: loading, the folder-relative `require`, warping, networking and
# player collision, none of which test/run.lua can reach.
#
#   test/live/run.sh                 # referee + two players, the R-030 cases
#   test/live/run.sh --load-only     # one instance: does the mod load at all
#   test/live/run.sh --without r030  # prove the run can go red: take that fix out
#                                    # of each instance's COPY of the mod and
#                                    # require the case it protects to fail
#
# **Three processes, not two, and the two that collide are both clients.**
# A process started with `--headless --server` sets gServerSettings.headlessServer
# (src/pc/network/network.c:140), and that flag makes its own player inert: it
# never sends its position (network_update_player, packets/packet_player.c:430)
# and is_player_active returns FALSE for it on every instance
# (src/game/obj_behaviors.c:547), which is the first question interact_player asks
# about both bodies.  A headless host can referee a round but can never touch
# anybody, so the harness runs a dedicated server and two ordinary players.
#
# It needs a built sm64coopdx.  Point COOPDX at the binary, or let it find
# ~/src/sm64coopdx/build/us_pc/sm64coopdx:
#
#   git clone https://github.com/coop-deluxe/sm64coopdx ~/src/sm64coopdx
#   sudo apt install build-essential python3 libglew-dev libsdl2-dev libz-dev \
#                    libcurl4-openssl-dev
#   make -C ~/src/sm64coopdx -j"$(nproc)"
#
# It also needs a vanilla US Super Mario 64 ROM, which nobody can supply for you.
# The ROM is not needed to *build* Co-op DX -- it takes its assets from the ROM at
# first run instead, and `main_rom_handler` (src/pc/rom_checker.cpp) scans the
# instance's own folder for any `.z64` whose MD5 it recognises.  Point ROM at your
# own copy, or leave one at ~/.local/share/sm64coopdx/baserom.us.z64.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COOPDX="${COOPDX:-$HOME/src/sm64coopdx/build/us_pc/sm64coopdx}"
PORT="${PORT:-27015}"
TIMEOUT="${TIMEOUT:-240}"
WORK="${WORK:-$(mktemp -d "${TMPDIR:-/tmp}/starhunt-live-XXXXXX")}"
ROM="${ROM:-$HOME/.local/share/sm64coopdx/baserom.us.z64}"
LOAD_ONLY=0
WITHOUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --load-only) LOAD_ONLY=1 ;;
        --without)   WITHOUT="${2:-}"; shift ;;
        *) echo "usage: run.sh [--load-only] [--without <name>]" >&2; exit 2 ;;
    esac
    shift
done

if [[ -n "$WITHOUT" && ! -f "$ROOT/test/live/without/$WITHOUT.txt" ]]; then
    echo "no such removal: $WITHOUT. Available:" >&2
    ls "$ROOT/test/live/without/" | sed 's/\.txt$//' | grep -v README >&2
    exit 2
fi

if [[ ! -x "$COOPDX" ]]; then
    echo "no sm64coopdx binary at $COOPDX -- build it, or set COOPDX" >&2
    exit 2
fi

if [[ ! -f "$ROM" ]]; then
    echo "no Super Mario 64 ROM at $ROM -- set ROM to your own copy." >&2
    echo "Co-op DX reads its assets from the ROM at run time, so it cannot start" >&2
    echo "without one, and no part of this repository can provide it." >&2
    exit 2
fi

# Each instance gets its own save path, so its config, its save file and its
# mods folder are all disposable and neither instance can see the other's.
prepare() {
    local dir="$WORK/$1"
    mkdir -p "$dir/mods"
    cp -r "$ROOT/StarHunt" "$dir/mods/StarHunt"
    cp -r "$ROOT/test/live/mods/starhunt_probe" "$dir/mods/starhunt_probe"
    # The game scans its own folder for the ROM, so each instance needs one.
    # A hard link where possible: the file is 8MB and this runs often.
    ln "$ROM" "$dir/baserom.us.z64" 2>/dev/null || cp "$ROM" "$dir/baserom.us.z64"
    # The config has to exist before the game reads it, or --enable-mod is lost:
    # configfile_load_internal (src/pc/configfile.c) creates the file and RETURNS
    # when it is missing, and the loop that turns gCLIOpts.enableMods into queued
    # enables sits below that return. A first run on a fresh save path therefore
    # starts with every mod switched off however many --enable-mod flags it was
    # given. Writing the two lines ourselves settles it in one run; the option is
    # spelled with a trailing colon, as `functionOptions` declares it.
    printf 'enable-mod: StarHunt\nenable-mod: starhunt_probe\n' > "$dir/config.txt"
    remove_from_copy "$dir/mods/StarHunt"
}

# `--without <name>` takes a fix out of StarHunt so the run can be shown to go
# red. **It edits this instance's copy, never the working tree** -- the same rule
# tools/sweep_mutations.py follows, because a run killed halfway through leaves a
# half-applied edit behind when it edits in place.
#
# The block has to be found exactly once, and the run dies here if it is not.
# A removal that silently does nothing would turn the falsification check into a
# tautology, which is the failure this whole mechanism exists to prevent.
remove_from_copy() {
    [[ -z "$WITHOUT" ]] && return 0
    python3 - "$ROOT/test/live/without/$WITHOUT.txt" "$1" <<'PY' || exit 2
import sys
spec, moddir = sys.argv[1], sys.argv[2]
head, _, block = open(spec).read().partition("\n")
target = moddir + "/" + head.strip()
source = open(target).read()
found = source.count(block)
if found != 1:
    sys.exit("removal %r: found the block %d times in %s, expected exactly 1. "
             "The code has moved; update the .txt file." % (spec, found, head.strip()))
open(target, "w").write(source.replace(block, "", 1))
PY
}

# stdbuf keeps the probe's print() line-buffered: without it the last lines sit
# in stdio's buffer and are lost when the process is killed.
#
# **The caller's arguments must not come last.** `--client <ip> <port>` only reads
# its port when another argument follows it: the parser checks `(i + 2) < argc`
# after it has already consumed the IP (src/pc/cliopts.c), so a port written at
# the very end of the command line is ignored and the client quietly dials 7777.
# Putting --playername after "$@" is what keeps that from happening.
launch() {
    local name="$1"; shift
    # A fresh savepath means a fresh config, and a mod the config has never seen
    # is disabled: mods_enable() (src/pc/mods/mods.c) is what turns one on, and
    # --enable-mod is the only way to reach it without the menu. It matches the
    # mod's folder name under mods/, not its `-- name:` header.
    # The build links libdiscord_game_sdk.so and ships it beside the binary
    # rather than installing it, so the loader has to be told where it is.
    LD_LIBRARY_PATH="$(dirname "$COOPDX")${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    stdbuf -oL -eL "$COOPDX" --headless --savepath "$WORK/$name" \
        --configfile "config.txt" --skip-intro --skip-update-check --no-discord --hide-loading-screen \
        --enable-mod StarHunt --enable-mod starhunt_probe \
        "$@" --playername "$name" > "$WORK/$name.log" 2>&1 &
    echo $!
}

cleanup() {
    for pid in ${PIDS:-}; do kill "$pid" 2>/dev/null; done
    sleep 1
    for pid in ${PIDS:-}; do kill -9 "$pid" 2>/dev/null; done
}
trap cleanup EXIT

prepare server
PIDS="$(launch server --server "$PORT")"
if [[ $LOAD_ONLY -eq 0 ]]; then
    # The server has to finish booting and be listening before a client dials
    # it; there is no retry, a client that arrives early just sits there.
    sleep "${JOIN_DELAY:-15}"
    # p1 before p2, and with a gap: the probe decides which player stands still
    # and which walks into it from the global index the server hands out, and
    # that is assigned in join order. The gap keeps the order deterministic.
    prepare p1
    PIDS="$PIDS $(launch p1 --client 127.0.0.1 "$PORT")"
    sleep "${PAIR_DELAY:-8}"
    prepare p2
    PIDS="$PIDS $(launch p2 --client 127.0.0.1 "$PORT")"
fi

# What counts as finished: the referee has closed the last case, or an instance
# failed. The referee prints `end` once every player has reported every entry in
# the probe's CASE list, so nothing here has to know what is in it.
deadline=$((SECONDS + TIMEOUT))
done_line="^PROBE end role=server"
if [[ $LOAD_ONLY -eq 1 ]]; then done_line="^PROBE load"; fi
while (( SECONDS < deadline )); do
    if grep -qh "^PROBE fail" "$WORK"/*.log 2>/dev/null; then break; fi
    if grep -qh "$done_line" "$WORK"/*.log 2>/dev/null; then break; fi
    sleep 2
done

echo "--- probe lines -------------------------------------------------------"
grep -h "^PROBE" "$WORK"/*.log 2>/dev/null || echo "(none -- see $WORK/*.log)"
echo "-----------------------------------------------------------------------"

status=1
if grep -qh "could not find valid vanilla us sm64 rom" "$WORK"/*.log 2>/dev/null; then
    echo "FAILED: the game rejected the ROM at $ROM. It has to be a vanilla US"
    echo "Super Mario 64 ROM -- the game checks its MD5 and reads its assets."
elif grep -qh "^PROBE fail" "$WORK"/*.log 2>/dev/null; then
    echo "FAILED: the probe reported a failure."
elif [[ $LOAD_ONLY -eq 1 ]]; then
    if grep -qh "^PROBE load" "$WORK"/*.log; then
        echo "PASSED: StarHunt loads in a real sm64coopdx and its modules resolve."
        status=0
    else
        echo "FAILED: StarHunt did not load. See $WORK/server.log"
    fi
else
    # What the run asks, and the order the answers are read in matters.
    #
    #   shared -- the control. Two players the mod does not hide from each other
    #             must be pushed apart by the engine. If this fails, nothing else
    #             in the run means anything: a setup where the bodies never touch
    #             reports every other case as a pass, fix or no fix.
    #   hidden -- R-030 itself. Two players the mod hides, standing in one act so
    #             the engine is willing, must pass through. Deleting the branch in
    #             modules/goals.lua has to turn this red.
    #   split  -- the ordinary round arrangement, recorded rather than tested: the
    #             engine keeps two players on different acts apart on its own.
    #   ddd    -- two players holding different Dire Dire Docks acts, standing in
    #             one of them. Nothing in that course is gated on the act, so the
    #             mod must leave them alone and the engine must push them apart.
    #             Both clients also report the save flags the submarine and the
    #             poles read, which have to agree for the case to mean anything.
    #   wdw    -- the same question for Wet-Dry World, whose objects are ALL_ACTS
    #             in both areas and whose water level is not derived from the
    #             act. The mod must leave that pair alone as well.
    #   clock  -- not a pair at all: each client reports what ANOTHER LEVEL counts
    #             down to. The deadline is a frame number on the host's counter,
    #             so a client that read it against its own would add the server's
    #             head start to the two-minute cooldown. Both clients must report
    #             ok=true, which is skew > 0 -- their counter really is behind --
    #             and a countdown no longer than the cooldown.
    # Which case each named removal is expected to break. A removal whose case is
    # not named here would report a pass for doing nothing.
    declare -A WITHOUT_CASE=( [r030]=hidden [r035]=clock )
    # And what "that case went red" reads as: the collision cases report a
    # verdict per case, the clock reports its own answer.
    declare -A WITHOUT_RED=( [r030]="case=hidden passed_through=false"
                             [r035]="^PROBE clock role=player.*ok=false" )
    # Only look the removal up when there is one: under `set -u` an empty
    # subscript on an associative array is an error, printed on every ordinary
    # run.
    WITHOUT_BREAKS=""
    WITHOUT_RED_PATTERN=""
    if [[ -n "$WITHOUT" ]]; then
        WITHOUT_BREAKS="${WITHOUT_CASE[$WITHOUT]:-}"
        WITHOUT_RED_PATTERN="${WITHOUT_RED[$WITHOUT]:-}"
        if [[ -z "$WITHOUT_BREAKS" || -z "$WITHOUT_RED_PATTERN" ]]; then
            echo "FAILED: '$WITHOUT' has no expected case in WITHOUT_CASE, so there is"
            echo "nothing to check it against. Add it beside this line."
            echo "logs: $WORK"
            exit 1
        fi
    fi
    split=$(cat "$WORK"/*.log 2>/dev/null | grep -c "case=split passed_through=true")
    hidden=$(cat "$WORK"/*.log 2>/dev/null | grep -c "case=hidden passed_through=true")
    shared=$(cat "$WORK"/*.log 2>/dev/null | grep -c "case=shared passed_through=false")
    ddd=$(cat "$WORK"/*.log 2>/dev/null | grep -c "case=ddd passed_through=false")
    wdw=$(cat "$WORK"/*.log 2>/dev/null | grep -c "case=wdw passed_through=false")
    # One distinct value across the clients means every player in Dire Dire Docks
    # reads the same submarine and the same poles.
    clock_seen=$(cat "$WORK"/*.log 2>/dev/null | grep -c "^PROBE clock role=player")
    clock_ok=$(cat "$WORK"/*.log 2>/dev/null | grep -c "^PROBE clock role=player.*ok=true")
    gates_seen=$(cat "$WORK"/*.log 2>/dev/null | grep -c "^PROBE saveflags")
    gates_agree=$(cat "$WORK"/*.log 2>/dev/null | sed -n 's/^PROBE saveflags .*ddd_gate=//p' | sort -u | wc -l)
    # With `--without <name>` the whole run is inverted: the point is to show
    # that the harness can fail, so the case that fix protects MUST go red while
    # the control and the engine-only case stay exactly where they were. A run
    # that comes back green here means the removal measured nothing.
    if [[ -n "$WITHOUT" ]]; then
        broke=$(cat "$WORK"/*.log 2>/dev/null | grep -c "$WITHOUT_RED_PATTERN")
        if (( shared < 2 )); then
            echo "INCONCLUSIVE: the control case did not collide even with '$WITHOUT'"
            echo "removed, so this run says nothing about whether the removal mattered."
        elif (( broke >= 2 )); then
            echo "PASSED (inverted): with '$WITHOUT' removed from each instance's copy of"
            echo "the mod, the '$WITHOUT_BREAKS' case went red and the control still held."
            echo "The harness can fail, so a green run without --without means something."
            status=0
        else
            echo "FAILED: '$WITHOUT' was removed and the '$WITHOUT_BREAKS' case stayed green."
            echo "The case is measuring something other than that code -- a green ordinary"
            echo "run proves nothing until this is understood."
        fi
    elif (( shared < 2 )); then
        echo "FAILED: the control case did not collide, so this run proves nothing"
        echo "about the other two. Two players on the same act with the same goal"
        echo "must be pushed apart to about 74; see the overlap lines above."
    elif (( hidden < 2 )); then
        echo "FAILED: two players StarHunt hides from each other were pushed apart"
        echo "while standing in the same act. That is the R-030 case."
    elif (( split < 2 )); then
        echo "FAILED: two players on different acts touched each other, which the"
        echo "engine alone should already prevent. Something changed in Co-op DX."
    elif (( gates_seen < 2 || gates_agree != 1 )); then
        echo "FAILED: the two players in Dire Dire Docks do not read the same"
        echo "SAVE_FLAG_HAVE_KEY_2 | SAVE_FLAG_UNLOCKED_UPSTAIRS_DOOR, so they do"
        echo "not see the same submarine or the same poles. The course cannot be"
        echo "shared between acts on that basis; see the saveflags lines above."
    elif (( ddd < 2 )); then
        echo "FAILED: two players holding different Dire Dire Docks acts were kept"
        echo "apart while standing in the same act. Nothing in that course is gated"
        echo "on the act, so the mod is isolating a pair whose worlds agree (R-031)."
    elif (( wdw < 2 )); then
        echo "FAILED: two players holding different Wet-Dry World acts were kept"
        echo "apart while standing in the same act. Every object in that course is"
        echo "ALL_ACTS and its water level does not come from the act, so the mod is"
        echo "isolating a pair whose worlds agree (R-029)."
    elif (( clock_seen < 2 || clock_ok < 2 )); then
        echo "FAILED: a joined client is not counting ANOTHER LEVEL against the"
        echo "host's clock. Read the PROBE clock lines: skew is how far this"
        echo "client's frame counter is behind the host's, and remaining must be"
        echo "no more than cooldown. A skew of 0 means the offset was never"
        echo "measured, since the server is started first and each client joins"
        echo "JOIN_DELAY seconds later."
    else
        echo "PASSED: the pair StarHunt hides passed through each other while the"
        echo "engine was willing to collide them (R-030), the pair it does not hide"
        echo "was pushed apart at the engine's 74 units, two players on different"
        echo "acts never touched at all, two players on different Dire Dire Docks"
        echo "acts fought each other over one save file (R-031), and so did two on"
        echo "different Wet-Dry World acts (R-029). Both clients counted ANOTHER"
        echo "LEVEL against the host's clock rather than their own (R-035)."
        status=0
    fi
fi

echo "logs: $WORK"
exit $status
