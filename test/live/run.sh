#!/usr/bin/env bash
#
# Run StarHunt inside two real headless sm64coopdx processes and read back what
# the probe mod saw.  This is the only check in the repository that exercises
# the game itself: loading, the folder-relative `require`, warping, networking
# and player collision, none of which test/run.lua can reach.
#
#   test/live/run.sh                 # host + client, the R-030 pass-through case
#   test/live/run.sh --load-only     # one instance: does the mod load at all
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
[[ "${1:-}" == "--load-only" ]] && LOAD_ONLY=1

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
}

# stdbuf keeps the probe's print() line-buffered: without it the last lines sit
# in stdio's buffer and are lost when the process is killed.
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
        --playername "$name" "$@" > "$WORK/$name.log" 2>&1 &
    echo $!
}

cleanup() {
    for pid in ${PIDS:-}; do kill "$pid" 2>/dev/null; done
    sleep 1
    for pid in ${PIDS:-}; do kill -9 "$pid" 2>/dev/null; done
}
trap cleanup EXIT

prepare host
PIDS="$(launch host --server "$PORT")"
if [[ $LOAD_ONLY -eq 0 ]]; then
    prepare client
    # The host has to finish booting and be listening before the client dials
    # it; there is no retry, a client that arrives early just sits there.
    sleep "${JOIN_DELAY:-15}"
    PIDS="$PIDS $(launch client --client 127.0.0.1 "$PORT")"
fi

# What counts as finished: every instance has printed a verdict, or one failed.
want=$([[ $LOAD_ONLY -eq 1 ]] && echo 1 || echo 2)
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
        echo "FAILED: StarHunt did not load. See $WORK/host.log"
    fi
elif (( $(cat "$WORK"/*.log 2>/dev/null | grep -c "passed_through=true") >= want )); then
    echo "PASSED: two players the mod hid from each other stayed overlapped (R-030)."
    status=0
else
    echo "FAILED: the hidden players were pushed apart, or never got as far as touching."
fi

echo "logs: $WORK"
exit $status
