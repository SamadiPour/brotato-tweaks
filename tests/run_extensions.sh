#!/usr/bin/env bash
# Boots the real ModLoader against this mod, then compiles everything under extensions/ against
# the real vanilla source.
#
#   tests/run_extensions.sh
#   BROTATO_SRC=/path/to/decompiled GODOT=/path/to/godot3 tests/run_extensions.sh
#
# Two passes, both of which otherwise cost a game launch:
#
#   1. **Loader.** The decompiled tree carries the game's own addons/mod_loader, so starting it
#      with this mod symlinked into mods-unpacked/ runs the actual loader: manifest validation,
#      mod init, script extension installation. A manifest ModLoader rejects makes it log
#      FATAL-ERROR and carry on with a half-built mod, which in a release build (where `assert`
#      is compiled out) is a segfault on startup rather than an error message. This catches that.
#   2. **Parse.** Every adapter is compiled. tests/run.sh cannot: they `extends` a res:// path
#      that only exists inside the game, so it skips the directory. This is the pass that fails
#      when a vanilla method is renamed or its signature changes under us.
#
# The two cannot share a process. Once the loader has installed an extension,
# res://global/entity_spawner.gd *is* our script, so loading our file again makes it extend
# itself. So pass 2 runs separately, against a copy staged outside mods-unpacked/ where the
# loader will not touch it and the vanilla scripts are still pristine. The mod's core/ is the one
# thing put back in place for it, because the adapters preload out of it; nothing there is a mod
# the loader can install.
#
# Node paths and scene structure are the next harness's job: tests/run_menu.sh boots a real title
# screen and mounts the tab against it.
#
# Nothing is written to the decompiled tree that is not removed again on exit, and each run gets
# a throwaway HOME: the decompiled project.godot carries the game's own name, so without that
# they would write logs and mod profiles into the real game's user://.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BROTATO_SRC="${BROTATO_SRC:-$HOME/Dev/BrotatoDecompiled}"
GODOT="${GODOT:-/Applications/Godot3.app/Contents/MacOS/Godot}"

if [[ ! -x "$GODOT" ]]; then
	echo "Godot 3.x not found at $GODOT - set GODOT=/path/to/godot" >&2
	exit 2
fi
if [[ ! -f "$BROTATO_SRC/project.godot" ]]; then
	echo "No decompiled Brotato source at $BROTATO_SRC - set BROTATO_SRC=/path/to/it" >&2
	echo "See docs/02-dev-setup.md for how to produce it." >&2
	exit 2
fi

CHECK="$BROTATO_SRC/tweaks_check.gd"
LINK="$BROTATO_SRC/mods-unpacked"
STAGE="$BROTATO_SRC/tweaks_ext_check"
LOADER_HOME="$(mktemp -d)"
PARSE_HOME="$(mktemp -d)"
LOADER_LOG="$(mktemp)"
PARSE_LOG="$(mktemp)"

cleanup() {
	rm -f "$CHECK"
	if [[ -L "$LINK" ]]; then
		rm -f "$LINK"
	else
		# Pass 2 replaces the symlink with a real directory holding core/ — see below.
		rm -rf "$LINK"
	fi
	rm -rf "$STAGE" "$LOADER_HOME" "$PARSE_HOME" "$LOADER_LOG" "$PARSE_LOG"
	return 0
}
trap cleanup EXIT

if [[ -e "$LINK" && ! -L "$LINK" ]]; then
	echo "$LINK exists and is not a symlink - refusing to touch it" >&2
	exit 2
fi
if [[ -e "$STAGE" ]]; then
	echo "$STAGE already exists - refusing to overwrite it" >&2
	exit 2
fi

# macOS has no `timeout`, and a parse error can leave the engine idling in the main loop.
run_godot() {
	local sandbox_home="$1" log="$2"
	HOME="$sandbox_home" "$GODOT" --no-window --path "$BROTATO_SRC" -s res://tweaks_check.gd > "$log" 2>&1 &
	local pid=$!
	local waited=0
	while kill -0 "$pid" 2>/dev/null; do
		if (( waited >= 90 )); then
			kill "$pid" 2>/dev/null || true
			echo "TIMED OUT after ${waited}s" >> "$log"
			break
		fi
		sleep 1
		(( waited++ ))
	done
	wait "$pid" 2>/dev/null || true
}

# --- pass 1: the loader -----------------------------------------------------------------

ln -sfn "$REPO_ROOT/root/mods-unpacked" "$LINK"
cat > "$CHECK" <<'GDSCRIPT'
extends SceneTree

# The work happens before this runs: ModLoader is an autoload, so by the time the main loop
# exists the mod has been validated, initialised and its extensions installed. The log it wrote
# is the result.
func _initialize() -> void:
	quit(0)
GDSCRIPT
run_godot "$LOADER_HOME" "$LOADER_LOG"
rm -f "$LINK"

MODLOADER_LOG="$LOADER_HOME/Library/Application Support/Brotato/logs/modloader.log"

echo "== mod loader =="
if [[ -f "$MODLOADER_LOG" ]]; then
	grep -E "Brotato-Tweaks|script extension|FATAL-ERROR|ERROR" "$MODLOADER_LOG" || true
else
	echo "no loader log written - the loader did not run"
fi
# `-A 1` for the `at: res://…` line Godot prints under each one. Four of these are vanilla's and
# always there — see "Errors that are always in the loader pass" in docs/02-dev-setup.md — so
# without the site they came from, a real one from this mod reads exactly like the noise.
grep -E -A 1 "Parse Error|SCRIPT ERROR" "$LOADER_LOG" || true

# --- pass 2: the adapters ----------------------------------------------------------------

mkdir -p "$STAGE"
cp -R "$REPO_ROOT/root/mods-unpacked/Brotato-Tweaks/extensions/." "$STAGE/"

# The adapters `preload()` res://mods-unpacked/Brotato-Tweaks/core/tweaks_lookup.gd, and a preload
# is resolved at parse time: with the file absent every adapter fails to compile for a reason that
# has nothing to do with vanilla. So core/ is put back — and only core/. There is no manifest.json,
# no mod_main.gd and no extensions/ underneath it, so ModLoader has no mod to install in this pass
# and the vanilla scripts being compiled against stay pristine by construction rather than by
# timing.
mkdir -p "$LINK/Brotato-Tweaks"
cp -R "$REPO_ROOT/root/mods-unpacked/Brotato-Tweaks/core" "$LINK/Brotato-Tweaks/"
cat > "$CHECK" <<'GDSCRIPT'
extends SceneTree

func _initialize() -> void:
	var paths := []
	_collect("res://tweaks_ext_check", paths)
	var failed := 0
	for p in paths:
		# load() still hands back a GDScript that failed to compile; only can_instance() tells
		# the difference.
		var s = load(p)
		if s == null or not s.can_instance():
			print("EXT PARSE FAIL: ", p)
			failed += 1
		else:
			print("ok: ", p)
	print("---- ", paths.size() - failed, "/", paths.size(), " extensions parsed")
	quit(1 if failed > 0 else 0)

func _collect(dir_path: String, out: Array) -> void:
	var d := Directory.new()
	if d.open(dir_path) != OK: return
	d.list_dir_begin(true, true)
	var f := d.get_next()
	while f != "":
		var full := dir_path + "/" + f
		if d.current_is_dir():
			_collect(full, out)
		elif f.ends_with(".gd"):
			out.append(full)
		f = d.get_next()
	d.list_dir_end()
GDSCRIPT
run_godot "$PARSE_HOME" "$PARSE_LOG"

echo
echo "== adapter parse check =="
grep -E "^(ok|EXT PARSE FAIL|----)|Parse Error|TIMED OUT" "$PARSE_LOG" || true

# --- verdict --------------------------------------------------------------------------------

if grep -qE "EXT PARSE FAIL|Parse Error|TIMED OUT" "$PARSE_LOG"; then
	exit 1
fi
if [[ ! -f "$MODLOADER_LOG" ]] || grep -q "FATAL-ERROR" "$MODLOADER_LOG"; then
	exit 1
fi
if grep -qE "Parse Error|TIMED OUT" "$LOADER_LOG"; then
	exit 1
fi
