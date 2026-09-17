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
TIMEOUT="${TIMEOUT:-180}"
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
# tools/sweep_mutations.py follows, because a run killed halfway through has
# repeatedly left a half-applied edit behind when it worked in place.
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

# What counts as finished: both players have printed a verdict for every case,
# or one instance failed. The referee prints no verdict; it has no body in the
# measurement. Two players, three cases each: six verdicts in all.
want=$([[ $LOAD_ONLY -eq 1 ]] && echo 1 || echo 6)
deadline=$((SECONDS + TIMEOUT))
while (( SECONDS < deadline )); do
    if grep -qh "^PROBE fail" "$WORK"/*.log 2>/dev/null; then break; fi
    if [[ $LOAD_ONLY -eq 1 ]]; then
        (( $(cat "$WORK"/*.log 2>/dev/null | grep -c "^PROBE load") >= 1 )) && break
    else
        (( $(cat "$WORK"/*.log 2>/dev/null | grep -c "^PROBE verdict") >= want )) && break
    fi
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
    # Three questions, and the order they are answered in matters.
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
    # Which case each named removal is expected to break. A removal whose case is
    # not named here would report a pass for doing nothing.
    declare -A WITHOUT_CASE=( [r030]=hidden )
    WITHOUT_BREAKS="${WITHOUT_CASE[$WITHOUT]:-}"
    if [[ -n "$WITHOUT" && -z "$WITHOUT_BREAKS" ]]; then
        echo "FAILED: '$WITHOUT' has no expected case in WITHOUT_CASE, so there is"
        echo "nothing to check it against. Add it beside this line."
        echo "logs: $WORK"
        exit 1
    fi
    split=$(cat "$WORK"/*.log 2>/dev/null | grep -c "case=split passed_through=true")
    hidden=$(cat "$WORK"/*.log 2>/dev/null | grep -c "case=hidden passed_through=true")
    shared=$(cat "$WORK"/*.log 2>/dev/null | grep -c "case=shared passed_through=false")
    # With `--without <name>` the whole run is inverted: the point is to show
    # that the harness can fail, so the case that fix protects MUST go red while
    # the control and the engine-only case stay exactly where they were. A run
    # that comes back green here means the removal measured nothing.
    if [[ -n "$WITHOUT" ]]; then
        broke=$(cat "$WORK"/*.log 2>/dev/null | grep -c "case=$WITHOUT_BREAKS passed_through=false")
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
    else
        echo "PASSED: the pair StarHunt hides passed through each other while the"
        echo "engine was willing to collide them (R-030), the pair it does not hide"
        echo "was pushed apart at the engine's 74 units, and two players on"
        echo "different acts never touched at all."
        status=0
    fi
fi

echo "logs: $WORK"
exit $status
