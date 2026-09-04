#!/usr/bin/env bash
# Builds the real title screen against the real decompiled game, lets the mod's adapter mount its
# settings tab, switches to that tab and runs frames.
#
#   tests/run_menu.sh
#   BROTATO_SRC=/path/to/decompiled GODOT=/path/to/godot3 tests/run_menu.sh
#
# This is the only harness that runs the mod's UI where the engine actually lays it out, and it
# exists because of a bug the other two cannot see by construction:
#
#   `set_sections()` used to clear the tab with `for child in get_children(): child.queue_free()`.
#   A ScrollContainer's children are not all the caller's — the engine adds `h_scroll` and
#   `v_scroll` in the constructor and keeps raw pointers to them — so that freed the scrollbars
#   and left the container dereferencing freed memory. The result is a segfault one frame after
#   the tab first becomes visible: no GDScript error, no stack, nothing in modloader.log.
#
# tests/run.sh cannot catch it (it builds the tab under a bare Node that is never laid out) and
# tests/run_extensions.sh cannot (it only compiles). Only a frame does.
#
# The pause menu's copy of the same tab is not covered: its scene needs a run behind it. It mounts
# through the same `ui/options_tab.gd`, against the same `Menus/MenuOptions` path.
#
# As in tests/run_extensions.sh, nothing is left in the decompiled tree and each run gets a
# throwaway HOME, because that project.godot carries the game's own name.

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

CHECK="$BROTATO_SRC/tweaks_menu_check.gd"
LINK="$BROTATO_SRC/mods-unpacked"
SANDBOX_HOME="$(mktemp -d)"
LOG="$(mktemp)"

cleanup() {
	rm -f "$CHECK"
	[[ -L "$LINK" ]] && rm -f "$LINK"
	rm -rf "$SANDBOX_HOME" "$LOG"
	return 0
}
trap cleanup EXIT

if [[ -e "$LINK" && ! -L "$LINK" ]]; then
	echo "$LINK exists and is not a symlink - refusing to touch it" >&2
	exit 2
fi

ln -sfn "$REPO_ROOT/root/mods-unpacked" "$LINK"

cat > "$CHECK" <<'GDSCRIPT'
extends SceneTree

# A crash here is a signal, not a message, so the script says where it got to before every step
# that could take the process down. "survived" is the last line of a good run.

const TAB_NAME := "Tweaks_Container"
const BUTTON_NAME := "Tweaks_but"

var _frame := 0
var _screen = null
var _controller = null
var _tab = null
var _failures := 0


func _iteration(_delta) -> bool:
	_frame += 1
	match _frame:
		2:
			_build()
		8:
			_mounted()
		12:
			_switch()
		40:
			_finish()
	return false


func _build() -> void:
	var scene = load("res://ui/menus/title_screen/title_screen.tscn")
	if scene == null:
		print("FAIL: no title screen scene")
		quit(1)
		return
	_screen = scene.instance()
	# The adapter's own _ready() mounts the tab from here.
	get_root().add_child(_screen)


func _mounted() -> void:
	var options = _screen.get_node_or_null("Menus/MenuOptions")
	if options == null:
		print("FAIL: the title screen has no Menus/MenuOptions")
		quit(1)
		return
	_controller = options.get_node_or_null("Buttons")
	if _controller == null:
		print("FAIL: MenuOptions has no Buttons node")
		quit(1)
		return

	_tab = _controller.tab_container.get_node_or_null(TAB_NAME)
	_check("the mod mounted a tab", _tab != null and is_instance_valid(_tab))
	if _tab == null:
		quit(1)
		return

	var names := []
	for path in _controller.buttons_tab_np:
		names.append(str(_controller.get_node(path).name))
	_check("its button is in buttons_tab_np", names.has(BUTTON_NAME))
	_check("buttons_tab and buttons_tab_np agree",
		_controller.buttons_tab.size() == _controller.buttons_tab_np.size())
	_check("there is a tab child per tab button",
		_controller.tab_container.get_child_count() == _controller.buttons_tab_np.size())
	_check("it did not disturb the vanilla tabs",
		names[0] == "Audio_but" and names[3] == "Accessibility_but")

	# The regression this whole harness is here for.
	_check("the tab still has the scrollbars the engine gave it",
		is_instance_valid(_tab.get_v_scrollbar()) and is_instance_valid(_tab.get_h_scrollbar()))

	var tweaks = _tweaks()
	if tweaks == null:
		print("FAIL: the mod is not mounted")
		quit(1)
		return
	_check("it drew a row for every setting the schema declares",
		_tab._widgets.size() == tweaks.get_schema_properties().size())

	options.show()


func _switch() -> void:
	var target := -1
	for i in _controller.buttons_tab_np.size():
		if str(_controller.get_node(_controller.buttons_tab_np[i]).name) == BUTTON_NAME:
			target = i
	print("step: switching to tab ", target)
	_controller._change_tab(target)
	print("step: the tab is on screen")

	_check("switching selected it", _controller.tab_container.current_tab == target)
	_check("its button is the pressed one", _controller.buttons_tab[target].pressed)

	# A live edit, through the same path a player's click takes.
	var tweaks = _tweaks()
	var entry: Dictionary = _tab._widgets["enemies_multiplier"]
	entry.widget.value = 3.0
	_check("moving a dial reaches the settings",
		is_equal_approx(float(tweaks.get_setting("enemies_multiplier", 0.0)), 3.0))
	_check("moving a dial relabels it", entry.value_label.text == "3.0x")


func _finish() -> void:
	print("step: survived ", _frame, " frames")
	print("---- ", _failures, " check(s) failed")
	if _failures > 0:
		print("CHECK(S) FAILED")
	quit(1 if _failures > 0 else 0)


func _tweaks():
	var found := get_nodes_in_group("brotato_tweaks")
	return found[0] if not found.empty() else null


func _check(name: String, passed: bool) -> void:
	if passed:
		print("ok: ", name)
	else:
		print("FAIL: ", name)
		_failures += 1
GDSCRIPT

# macOS has no `timeout`, and a crash leaves no exit of its own to wait on politely.
HOME="$SANDBOX_HOME" "$GODOT" --no-window --path "$BROTATO_SRC" -s res://tweaks_menu_check.gd \
	> "$LOG" 2>&1 &
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
wait "$pid" 2>/dev/null || status=$?
status="${status:-0}"

echo "== the settings tab, on screen =="
grep -aE "^(ok|FAIL|step|----)|Program crashed|TIMED OUT" "$LOG" || true

if grep -qaE "CHECK\(S\) FAILED|^FAIL|TIMED OUT|Program crashed" "$LOG"; then
	exit 1
fi
if ! grep -qa "survived" "$LOG"; then
	# No verdict and no failure line means the process went down without saying anything, which is
	# what a segfault in the engine's own layout looks like from here.
	echo "the run ended before the tab survived a frame - exit status $status"
	exit 1
fi
