#!/usr/bin/env bash
# Runs the mod's own scripts headless against stubbed game singletons.
#
#   tests/run.sh              # parse check + core checks
#   GODOT=/path/to/godot3 tests/run.sh
#
# Needs a Godot 3.x binary. On macOS the default below matches a standard install.
# The adapters under extensions/ are not covered here — see tests/run_extensions.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS="$REPO_ROOT/tests/godot"
GODOT="${GODOT:-/Applications/Godot3.app/Contents/MacOS/Godot}"

if [[ ! -x "$GODOT" ]]; then
	echo "Godot 3.x not found at $GODOT - set GODOT=/path/to/godot" >&2
	exit 2
fi

# The harness reads the mod from res://mods-unpacked, where the game reads it too.
ln -sfn "$REPO_ROOT/root/mods-unpacked" "$HARNESS/mods-unpacked"

PARSE_LOG="$(mktemp)"
CORE_LOG="$(mktemp)"
trap 'rm -f "$HARNESS/mods-unpacked" "$PARSE_LOG" "$CORE_LOG"' EXIT

# macOS has no `timeout`, and a parse error can leave the engine idling in the main loop, so
# every run is time-boxed.
run_godot() {
	local log="$1"
	shift
	"$GODOT" --no-window --path "$HARNESS" "$@" > "$log" 2>&1 &
	local pid=$!
	local waited=0
	while kill -0 "$pid" 2>/dev/null; do
		if (( waited >= 60 )); then
			kill "$pid" 2>/dev/null || true
			echo "TIMED OUT after ${waited}s" >> "$log"
			break
		fi
		sleep 1
		(( waited++ ))
	done
	wait "$pid" 2>/dev/null || true
}

echo "== parse check =="
run_godot "$PARSE_LOG" -s res://parse_check.gd
grep -E "^(ok|PARSE FAIL|skipped|----)|Parse Error|TIMED OUT" "$PARSE_LOG" || true

echo
echo "== core checks =="
run_godot "$CORE_LOG"
grep -E "^(ok|FAIL|----)|Parse Error|TIMED OUT" "$CORE_LOG" || true

if grep -qE "CHECK\(S\) FAILED|PARSE FAIL|Parse Error|TIMED OUT" "$PARSE_LOG" "$CORE_LOG"; then
	exit 1
fi
