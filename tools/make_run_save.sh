#!/usr/bin/env bash
# Builds a Brotato run save from tools/lag_build.json - a deep endless wave with a heavy build,
# for measuring where the frame time goes.
#
#   tools/make_run_save.sh                     # write dist/run_v3_0.json and stop
#   tools/make_run_save.sh --install           # ...and put it in the game's save folder
#   tools/make_run_save.sh --restore           # put the backed-up run save back
#   BUILD=other.json tools/make_run_save.sh    # a different loadout
#
# The save is produced by a headless Godot running against the decompiled game, so the file is
# written by the game's own serialisation rather than by a template that has to be kept in step
# with it. See tools/make_run_save.gd for why that matters, and docs/02-dev-setup.md for how to
# produce the decompiled tree.
#
# Only run_v3_<profile>.json is touched. The progress save beside it - unlocks, challenges,
# statistics - is never opened. An existing run save is moved aside, not overwritten, and
# --restore puts it back.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BROTATO_SRC="${BROTATO_SRC:-$HOME/Dev/BrotatoDecompiled}"
GODOT="${GODOT:-/Applications/Godot3.app/Contents/MacOS/Godot}"
BUILD="${BUILD:-$REPO_ROOT/tools/lag_build.json}"

# Where the game keeps saves. Brotato sets use_custom_user_dir, so this is a plain Brotato folder
# rather than the usual Godot/app_userdata one, and the GOG build shells out to its own subfolder.
case "$(uname -s)" in
	Darwin) SAVE_ROOT="$HOME/Library/Application Support/Brotato" ;;
	*)      SAVE_ROOT="$HOME/.local/share/Brotato" ;;
esac
if [[ -d "$SAVE_ROOT/GOG-Saves" ]]; then
	SAVE_DIR="${SAVE_DIR:-$SAVE_ROOT/GOG-Saves}"
else
	SAVE_DIR="${SAVE_DIR:-$SAVE_ROOT}"
fi

install=0
restore=0
for arg in "$@"; do
	case "$arg" in
		--install) install=1 ;;
		--restore) restore=1 ;;
		*) echo "unknown option: $arg" >&2; exit 2 ;;
	esac
done

profile_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("profile_id", 0))' "$BUILD")"
RUN_SAVE="$SAVE_DIR/run_v3_${profile_id}.json"
BACKUP="$RUN_SAVE.pre-lag-lab"

if (( restore )); then
	if [[ ! -f "$BACKUP" ]]; then
		echo "no backup at $BACKUP" >&2
		exit 1
	fi
	mv -f "$BACKUP" "$RUN_SAVE"
	echo "restored $RUN_SAVE"
	exit 0
fi

if [[ ! -x "$GODOT" ]]; then
	echo "Godot 3.x not found at $GODOT - set GODOT=/path/to/godot" >&2
	exit 2
fi
if [[ ! -f "$BROTATO_SRC/project.godot" ]]; then
	echo "No decompiled Brotato source at $BROTATO_SRC - set BROTATO_SRC=/path/to/it" >&2
	echo "See docs/02-dev-setup.md for how to produce it." >&2
	exit 2
fi
if [[ ! -f "$BUILD" ]]; then
	echo "No build file at $BUILD" >&2
	exit 2
fi

STAGED="$BROTATO_SRC/make_run_save.gd"
SANDBOX_HOME="$(mktemp -d)"
LOG="$(mktemp)"
OUT="$REPO_ROOT/dist/run_v3_${profile_id}.json"

cleanup() {
	rm -f "$STAGED"
	rm -rf "$SANDBOX_HOME" "$LOG"
	return 0
}
trap cleanup EXIT

if [[ -e "$STAGED" ]]; then
	echo "$STAGED already exists - refusing to overwrite it" >&2
	exit 2
fi

mkdir -p "$REPO_ROOT/dist"
cp "$REPO_ROOT/tools/make_run_save.gd" "$STAGED"

# The decompiled project.godot carries the game's own name, so a throwaway HOME keeps the engine
# from writing logs and mod profiles into the real game's user:// while it runs. macOS has no
# `timeout`, and a script error can leave the engine idling in the main loop.
run_godot() {
	HOME="$SANDBOX_HOME" "$GODOT" --no-window --path "$BROTATO_SRC" -s res://make_run_save.gd \
		"$@" > "$LOG" 2>&1 &
	local pid=$!
	local waited=0
	while kill -0 "$pid" 2>/dev/null; do
		if (( waited >= 120 )); then
			kill "$pid" 2>/dev/null || true
			echo "TIMED OUT after ${waited}s" >> "$LOG"
			break
		fi
		sleep 1
		(( waited++ ))
	done
	local status=0
	wait "$pid" 2>/dev/null || status=$?

	# Booting the whole game to write one file is loud, and none of the noise is ours: the GOG
	# bindings are a dylib that is not here, the DLC check runs once before we stand a scene up,
	# the sandbox HOME has no save to find, and the engine leaks its own object pool at exit.
	# Keep the script's own output and anything that looks like a real failure.
	# A SCRIPT ERROR and the `at:` line naming where it came from are two lines, so the benign ones
	# have to be dropped as a pair or the message survives its own address.
	awk '/SCRIPT ERROR|^\[1;31mERROR/ {
			msg = $0
			if ((getline at) <= 0) { print msg; exit }
			if (at ~ /get_active_dlc_ids|reset_dlc_resources_to_active_dlcs|GOGPlatform|CrashReporter|gdnative|nativescript/) next
			print msg; print at; next
		}
		{ print }' "$LOG" \
		| grep -vE "^(Godot Engine|OpenGL|Using |Current path|Async|arguments|[0-9]+: |UNSUPPORTED|Brotato v|LOG_PATH|ProgressData|ModLoader|INFO |SUCCESS |WARNING |DEBUG |---|Try to load|No save|$)" \
		| grep -vE "gog.bindings|libGalaxy|GDNative|NativeScript|GOGPlatform|First argument of yield\(\)" \
		| grep -vE "get_active_dlc_ids|reset_dlc_resources_to_active_dlcs|CrashReporter|mods-unpacked" \
		| grep -vE "ObjectDB instances leaked|Resources still in use|MemoryPool allocs|_first != nullptr" \
		| grep -vE "^ +Referenced from|^ +Reason: tried|at: (~List|cleanup|clear|load|open_dynamic_library|get_symbol|init_library|terminate|call) |self_list\.h|core/(object|resource|pool_vector|io)|modules/gdnative|modules/gdscript|platform/osx" || true

	return "$status"
}

if ! run_godot "--build=$BUILD" "--out=$OUT" || [[ ! -s "$OUT" ]]; then
	echo "generation failed" >&2
	exit 1
fi

# Read it back through the game's own loader before it goes anywhere near the real save folder. A
# run save the loader rejects is not an empty Continue button, it is a crash on launch.
echo
if ! run_godot "--verify=$OUT"; then
	echo "the generated save does not load - not installing" >&2
	exit 1
fi

if (( ! install )); then
	echo
	echo "not installed. Re-run with --install to put it in $SAVE_DIR"
	exit 0
fi

if [[ ! -d "$SAVE_DIR" ]]; then
	echo "no save folder at $SAVE_DIR - launch the game once first" >&2
	exit 1
fi

if [[ -f "$RUN_SAVE" ]] && [[ ! -f "$BACKUP" ]]; then
	cp "$RUN_SAVE" "$BACKUP"
	echo "backed up the existing run save to $BACKUP"
fi

cp "$OUT" "$RUN_SAVE"
echo "installed $RUN_SAVE"
echo "Start the game and pick Continue run. It opens the shop for the wave; press Go to play it."
