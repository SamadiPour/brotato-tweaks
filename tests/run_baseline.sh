#!/usr/bin/env bash
# Checks what this mod believes about vanilla against tests/vanilla_baseline.json.
#
#   tests/run_baseline.sh              # check, and fail on anything that moved
#   tests/run_baseline.sh --update     # re-record the file, after reading what moved
#   BROTATO_SRC=/path/to/decompiled GODOT=/path/to/godot3 tests/run_baseline.sh
#
# The other harnesses catch what the compiler catches. This one exists for what it does not:
#
#   1. **Default arguments.** GDScript takes a default from the most-derived method, so
#      `init_elites_spawn(base_wave := 10, horde_chance := 0.4)` on the adapter *replaces* vanilla's
#      defaults for every caller that omits them. Vanilla retunes one, the adapter goes on handing
#      out the old number, and nothing anywhere fails.
#   2. **Copied bodies.** Ten vanilla methods have their logic reimplemented rather than called —
#      the item recycle, the piggy-bank payout, the spawner's tick budget. A copy that vanilla has
#      moved on from still compiles; it is simply no longer what the game does. Each one's source is
#      hashed, and a mismatch names the copy and says why it was made.
#   3. **Signal names.** Two signals are looked up by string at runtime. Renaming one is not a parse
#      error, it is a feature that quietly stops happening.
#
# Nothing is installed and no mod is loaded: the mod's own files are read from the repo by absolute
# path, so the decompiled tree is left exactly as pristine as it was found. As in the other
# harnesses, the run gets a throwaway HOME, because that project.godot carries the game's own name.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BROTATO_SRC="${BROTATO_SRC:-$HOME/Dev/BrotatoDecompiled}"
GODOT="${GODOT:-/Applications/Godot3.app/Contents/MacOS/Godot}"

UPDATE=""
for arg in "$@"; do
	case "$arg" in
		--update) UPDATE="--update" ;;
		*) echo "usage: $0 [--update]" >&2; exit 2 ;;
	esac
done

if [[ ! -x "$GODOT" ]]; then
	echo "Godot 3.x not found at $GODOT - set GODOT=/path/to/godot" >&2
	exit 2
fi
if [[ ! -f "$BROTATO_SRC/project.godot" ]]; then
	echo "No decompiled Brotato source at $BROTATO_SRC - set BROTATO_SRC=/path/to/it" >&2
	echo "See docs/02-dev-setup.md for how to produce it." >&2
	exit 2
fi

CHECK="$BROTATO_SRC/tweaks_baseline_check.gd"
SANDBOX_HOME="$(mktemp -d)"
LOG="$(mktemp)"

cleanup() {
	rm -f "$CHECK"
	rm -rf "$SANDBOX_HOME" "$LOG"
	return 0
}
trap cleanup EXIT

cat > "$CHECK" <<'GDSCRIPT'
extends SceneTree

# Reads vanilla, builds the same shape the baseline file records, and either writes it or compares.

const MOD_REL := "/root/mods-unpacked/Brotato-Tweaks"

var _repo := ""
var _update := false
var _fail := 0


func _initialize() -> void:
	var args := OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--repo" and i + 1 < args.size():
			_repo = args[i + 1]
		elif args[i] == "--update":
			_update = true

	if _repo == "":
		print("FAIL: no --repo given")
		quit(2)
		return

	var path := _repo + "/tests/vanilla_baseline.json"
	var baseline := _read_json(path)
	if baseline.empty():
		print("FAIL: could not read ", path)
		quit(2)
		return

	var built := {
		"$comment": baseline.get("$comment", []),
		"game_version": _manifest_game_version(),
		"overrides": _build_overrides(),
		"bodies": _build_bodies(baseline.get("bodies", [])),
		"signals": _build_signals(baseline.get("signals", [])),
	}

	if _update:
		if _fail > 0:
			print("---- refusing to write: read the failures above first")
			quit(1)
			return
		_write_json(path, built)
		print("wrote tests/vanilla_baseline.json against game ", built.game_version)
		print("  overrides: ", _count_methods(built.overrides), " method(s) in ", built.overrides.size(), " adapter(s)")
		print("  bodies:    ", built.bodies.size(), " copied method(s) hashed")
		print("  signals:   ", built.signals.size(), " looked up by name")
		quit(0)
		return

	_compare(baseline, built)
	print("---- ", _fail, " baseline check(s) failed")
	quit(1 if _fail > 0 else 0)


# --- building ---------------------------------------------------------------------------

func _manifest_game_version() -> String:
	var manifest := _read_json(_repo + MOD_REL + "/manifest.json")
	var versions = manifest.get("compatible_game_version", [])
	if not (versions is Array) or versions.empty():
		_bad("manifest.json declares no compatible_game_version")
		return ""
	return str(versions[0])


# Every method an adapter overrides that vanilla itself declares, with vanilla's default arguments.
# A method the adapter adds of its own is not an override and is not recorded; a method vanilla no
# longer declares drops out of the answer, which is what the comparison notices.
func _build_overrides() -> Dictionary:
	var files := []
	_collect_gd(_repo + MOD_REL + "/extensions", files)
	files.sort()

	var out := {}
	for path in files:
		var source := _read_text(path)
		var base := _extends_path(source)
		if base == "":
			continue

		var vanilla := _read_text(base)
		if vanilla == "":
			_bad("%s extends %s, which is not in the decompiled tree" % [_rel(path), base])
			continue

		var defaults := {}
		var script = load(base)
		if script != null:
			for method in script.get_script_method_list():
				defaults[method.name] = method.default_args

		var names := _declared_funcs(source)
		names.sort()

		var methods := {}
		for name in names:
			# Reflection may or may not carry inherited methods, so what makes a name an override is
			# vanilla's own source declaring it.
			if not _declares(vanilla, name):
				continue
			methods[name] = {"default_args": _normalise_args(defaults.get(name, []))}

		if not methods.empty():
			out[_rel(path)] = {"extends": base, "methods": methods}
	return out


# The hand-kept list, with each named method's source hashed. Everything but the hash is carried
# through untouched: which copy it is about and why are a human's to write.
func _build_bodies(entries: Array) -> Array:
	var out := []
	for entry in entries:
		var built := {
			"script": str(entry.get("script", "")),
			"method": str(entry.get("method", "")),
			"copied_by": str(entry.get("copied_by", "")),
			"why": str(entry.get("why", "")),
			"md5": "",
		}

		var source := _read_text(built.script)
		if source == "":
			_bad("%s is not in the decompiled tree" % built.script)
		else:
			var body := _method_body(source, built.method)
			if body == "":
				_bad("%s no longer declares %s()" % [built.script, built.method])
			else:
				built.md5 = body.md5_text()

		out.append(built)
	return out


func _build_signals(entries: Array) -> Array:
	var out := []
	for entry in entries:
		var built := {
			"script": str(entry.get("script", "")),
			"signal": str(entry.get("signal", "")),
			"used_by": str(entry.get("used_by", "")),
			"why": str(entry.get("why", "")),
			"present": false,
		}

		var script = load(built.script)
		if script == null:
			_bad("%s is not in the decompiled tree" % built.script)
		else:
			for declared in script.get_script_signal_list():
				if str(declared.name) == built.signal:
					built.present = true
					break

		out.append(built)
	return out


# --- comparing --------------------------------------------------------------------------

func _compare(baseline: Dictionary, built: Dictionary) -> void:
	_check("the baseline was recorded against this manifest's game version",
		str(baseline.get("game_version", "")) == str(built.game_version),
		"baseline says %s, manifest.json says %s" % [
			str(baseline.get("game_version", "")), str(built.game_version)])

	_compare_overrides(baseline.get("overrides", {}), built.overrides)
	_compare_bodies(baseline.get("bodies", []), built.bodies)

	for entry in built.signals:
		_check("%s still declares %s" % [entry.script, entry.signal], entry.present,
			"%s looks it up by name, so a rename is silent - %s" % [entry.used_by, entry.why])


func _compare_overrides(was: Dictionary, now: Dictionary) -> void:
	for path in was.keys():
		if not now.has(path):
			_bad("%s no longer overrides anything vanilla declares" % path)
			continue

		var was_methods: Dictionary = was[path].get("methods", {})
		var now_methods: Dictionary = now[path].get("methods", {})

		for name in was_methods.keys():
			if not now_methods.has(name):
				_bad("%s: vanilla no longer declares %s(), which this adapter overrides" % [path, name])
				continue
			var before := _args_key(was_methods[name].get("default_args", []))
			var after := _args_key(now_methods[name].get("default_args", []))
			_check("%s %s() default arguments" % [path, name], before == after,
				"vanilla now defaults to %s, the adapter still declares %s - GDScript takes the derived method's defaults, so every caller that omits them gets the adapter's" % [after, before])

		for name in now_methods.keys():
			if not was_methods.has(name):
				_bad("%s: %s() overrides vanilla but is not in the baseline - run tests/run_baseline.sh --update" % [path, name])

	for path in now.keys():
		if not was.has(path):
			_bad("%s is not in the baseline - run tests/run_baseline.sh --update" % path)


func _compare_bodies(was: Array, now: Array) -> void:
	var index := {}
	for entry in now:
		index[str(entry.script) + "::" + str(entry.method)] = entry

	for entry in was:
		var key := str(entry.get("script", "")) + "::" + str(entry.get("method", ""))
		if not index.has(key):
			_bad("%s is in the baseline but was not built - the file is malformed" % key)
			continue

		var built = index[key]
		if built.md5 == "":
			continue  # _build_bodies() already said why

		_check("%s is unchanged" % key, str(entry.get("md5", "")) == built.md5,
			"%s copies this method's logic. Re-read both, then run --update. %s" % [
				str(entry.get("copied_by", "")), str(entry.get("why", ""))])


# --- vanilla source ---------------------------------------------------------------------

# A method's source: its `func` line plus every line indented under it, trailing whitespace and
# blank lines dropped. Indentation is kept, because in GDScript it is the nesting.
func _method_body(source: String, method: String) -> String:
	var lines := source.split("\n")
	var start := -1
	for i in lines.size():
		if _is_declaration(lines[i], method):
			start = i
			break
	if start < 0:
		return ""

	var body := [lines[start].rstrip(" \t")]
	var i := start + 1
	while i < lines.size():
		var line: String = lines[i]
		var trimmed := line.strip_edges()
		# A non-blank line at column zero is the next top-level declaration.
		if trimmed != "" and not (line.begins_with("\t") or line.begins_with(" ")):
			break
		if trimmed != "":
			body.append(line.rstrip(" \t"))
		i += 1

	return PoolStringArray(body).join("\n")


func _is_declaration(line: String, method: String) -> bool:
	return line.begins_with("func " + method + "(") \
		or line.begins_with("static func " + method + "(")


func _declares(source: String, method: String) -> bool:
	for line in source.split("\n"):
		if _is_declaration(line, method):
			return true
	return false


func _declared_funcs(source: String) -> Array:
	var out := []
	for entry in source.split("\n"):
		var line: String = entry
		var head: String = ""
		if line.begins_with("func "):
			head = line.substr(5, line.length())
		elif line.begins_with("static func "):
			head = line.substr(12, line.length())
		if head == "":
			continue
		var open: int = head.find("(")
		if open > 0:
			out.append(head.substr(0, open).strip_edges())
	return out


func _extends_path(source: String) -> String:
	for entry in source.split("\n"):
		var line: String = entry
		if not line.begins_with("extends \"res://"):
			continue
		var first: int = line.find("\"")
		var last: int = line.find("\"", first + 1)
		if last > first:
			return line.substr(first + 1, last - first - 1)
	return ""


# --- helpers ----------------------------------------------------------------------------

# Defaults survive a JSON round trip, where every number comes back a float and nothing else does.
# Both sides are put through this so the comparison is of values rather than of how they were typed.
func _normalise_args(args) -> Array:
	var out := []
	if not (args is Array):
		return out
	for arg in args:
		out.append(arg)
	return out


func _args_key(args) -> String:
	if not (args is Array):
		return "[]"
	var parts := []
	for arg in args:
		if typeof(arg) == TYPE_BOOL:
			parts.append("true" if arg else "false")
		elif typeof(arg) == TYPE_INT or typeof(arg) == TYPE_REAL:
			parts.append("%.6f" % float(arg))
		else:
			parts.append(str(arg))
	return "[" + PoolStringArray(parts).join(", ") + "]"


func _collect_gd(dir_path: String, out: Array) -> void:
	var dir := Directory.new()
	if dir.open(dir_path) != OK:
		return
	dir.list_dir_begin(true, true)
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path + "/" + entry
		if dir.current_is_dir():
			_collect_gd(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _rel(path: String) -> String:
	var root := _repo + MOD_REL + "/"
	return path.substr(root.length(), path.length()) if path.begins_with(root) else path


func _count_methods(overrides: Dictionary) -> int:
	var total := 0
	for path in overrides.keys():
		total += overrides[path].get("methods", {}).size()
	return total


func _read_text(path: String) -> String:
	var file := File.new()
	if file.open(path, File.READ) != OK:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _read_json(path: String) -> Dictionary:
	var text := _read_text(path)
	if text == "":
		return {}
	var parsed := JSON.parse(text)
	if parsed.error != OK or not (parsed.result is Dictionary):
		return {}
	return parsed.result


func _write_json(path: String, data: Dictionary) -> void:
	var file := File.new()
	if file.open(path, File.WRITE) != OK:
		print("FAIL: could not write ", path)
		_fail += 1
		return
	file.store_string(JSON.print(data, "\t") + "\n")
	file.close()


func _check(name: String, passed: bool, detail: String) -> void:
	if passed:
		print("ok: ", name)
	else:
		print("FAIL: ", name)
		print("      ", detail)
		_fail += 1


func _bad(message: String) -> void:
	print("FAIL: ", message)
	_fail += 1
GDSCRIPT

# macOS has no `timeout`, and a parse error can leave the engine idling in the main loop.
HOME="$SANDBOX_HOME" "$GODOT" --no-window --path "$BROTATO_SRC" -s res://tweaks_baseline_check.gd \
	-- --repo "$REPO_ROOT" $UPDATE > "$LOG" 2>&1 &
pid=$!
waited=0
while kill -0 "$pid" 2>/dev/null; do
	if (( waited >= 90 )); then
		kill "$pid" 2>/dev/null || true
		echo "TIMED OUT after ${waited}s" >> "$LOG"
		break
	fi
	sleep 1
	(( waited++ ))
done
wait "$pid" 2>/dev/null || true

echo "== what this mod believes about vanilla =="
grep -aE "^(ok|FAIL|wrote|  |----)|TIMED OUT" "$LOG" || true

if grep -qaE "^FAIL|TIMED OUT" "$LOG"; then
	exit 1
fi
