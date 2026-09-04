extends SceneTree

# Builds a Brotato run state without playing it, and writes it in the shape the game reads back
# as "Continue run". Driven by tools/make_run_save.sh; run it from there, not by hand.
#
#   godot3 --no-window --path <decompiled> -s res://make_run_save.gd \
#       --build=/abs/lag_build.json --out=/abs/run_v3_0.json
#
# Why a headless engine rather than a JSON template: every item, weapon and effect in a run save is
# written by the game's own `serialize()`, and those payloads are large, nested and version-
# specific (a weapon carries its stats resource, its sets and its effect list; an item carries its
# appearances). Building the run through `RunData.add_character()`, `add_weapon()` and `add_item()`
# means the same code that would have run in a real shop produces the file, so the stat totals in
# `players_data.effects` match the items listed beside them - which a hand-written template gets
# wrong the moment a stack size changes.
#
# Every singleton is reached through get_node() and every game class through load(), never by
# name. A `-s` script is compiled before the autoloads are up, so naming `RunData` or `Keys` here
# would drag half the game's class graph into that early compile and fail it as a cyclic
# reference. Nothing below runs until _idle(), by which point the autoloads are ready.
#
# What this deliberately does NOT do: touch the progress save. Only run_v3_<profile>.json is
# written, so unlocks, challenges and statistics are untouched, and deleting the run file (or
# ending the run in game) puts everything back.


const LOADER_V3 := "res://singletons/progress_data_loader_v3.gd"

var _ran := false


func _idle(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true

	var args := _cmdline_options()
	if args.has("verify"):
		quit(_verify(args.get("verify", "")))
	else:
		quit(_generate(args))
	return true


# Reads a finished run save back through the game's own loader and resumes RunData from it, which
# is the whole path the title screen takes when you press Continue run. A save that survives this
# is one the game will open; a save that does not would have been a crash on launch.
func _verify(path: String) -> int:
	var file = _read_json(path)
	if file == null:
		return 2
	if not file.has("current_run_state"):
		printerr(path, " has no current_run_state")
		return 1

	var progress_data := root.get_node("ProgressData")
	var run_data := root.get_node("RunData")

	var stand_in := Node.new()
	stand_in.name = "LagLab"
	root.add_child(stand_in)
	current_scene = stand_in

	var loader = load(LOADER_V3).new("", 0)
	var state: Dictionary = loader.deserialize_run_state(file.current_run_state)
	if not state.get("has_run_state", false):
		printerr("the loader rejected it - the game would show no Continue run")
		return 1

	progress_data.reset_and_save_run_state(state)
	if not progress_data.check_dlc_valid_for_saved_run_state():
		printerr("the DLC check rejected it - the game would drop the run on launch")
		return 1

	run_data.continue_current_run_in_shop()

	var player = run_data.players_data[0]
	print("loads as   : ", player.current_character.my_id,
		", wave ", run_data.current_wave,
		", ", player.weapons.size(), " weapons, ", player.items.size(), " items")
	if player.weapons.size() == 0 or player.items.size() == 0:
		printerr("the loadout came back empty")
		return 1

	return 0


func _generate(args: Dictionary) -> int:
	var build_path: String = args.get("build", "")
	var out_path: String = args.get("out", "")

	if build_path == "" or out_path == "":
		printerr("usage: -s make_run_save.gd --build=<in.json> --out=<out.json>")
		return 2

	var build = _read_json(build_path)
	if build == null:
		return 2

	var keys := root.get_node("Keys")
	var item_service := root.get_node("ItemService")
	var progress_data := root.get_node("ProgressData")
	var run_data := root.get_node("RunData")

	# RunData.reset() ends up in ProgressData.get_active_dlc_ids(), which reads
	# get_tree().current_scene.name. Headless there is no current scene at all, so stand one up
	# first. The name matters: "GutRunner" is the game's own signal for "no DLCs, no unlocks".
	var stand_in := Node.new()
	stand_in.name = "LagLab"
	root.add_child(stand_in)
	current_scene = stand_in

	run_data.reset()

	var character_id: String = build.get("character", "")
	var character = item_service.get_element_safe(item_service.characters, character_id)
	if character == null:
		printerr("unknown character: ", character_id)
		return 1
	run_data.add_character(character, 0)

	# Danger level is not just a label: its effects are applied to the player at run start and are
	# part of what the wave scales against.
	run_data.current_difficulty = int(build.get("difficulty", 0))
	var difficulty = item_service.get_element(
		item_service.difficulties, keys.empty_hash, run_data.current_difficulty
	)
	if difficulty != null:
		for effect in difficulty.effects:
			effect.apply(0)

	var weapon_count := 0
	for entry in build.get("weapons", []):
		var weapon_id: String = entry.get("id", "")
		var weapon = item_service.get_element_safe(item_service.weapons, weapon_id)
		if weapon == null:
			printerr("unknown weapon: ", weapon_id)
			return 1
		for _i in int(entry.get("count", 1)):
			var _added = run_data.add_weapon(weapon, 0)
			weapon_count += 1

	var item_count := 0
	for entry in build.get("items", []):
		var item_id: String = entry.get("id", "")
		var item = item_service.get_element_safe(item_service.items, item_id)
		if item == null:
			printerr("unknown item: ", item_id)
			return 1
		var count := int(entry.get("count", 1))
		if item.max_nb > 0 and count > item.max_nb:
			printerr("%s is capped at %d, the build asks for %d" % [item_id, item.max_nb, count])
			return 1
		for _i in count:
			run_data.add_item(item, 0)
			item_count += 1

	run_data.current_zone = int(build.get("zone", 0))
	run_data.nb_of_waves = int(build.get("nb_of_waves", 20))
	run_data.current_wave = int(build.get("wave", 1))
	run_data.is_endless_run = bool(build.get("endless", true))
	run_data.enabled_dlcs = build.get("enabled_dlcs", [])

	var scaling = build.get("enemy_scaling", {})
	run_data.current_run_accessibility_settings = {
		"health": float(scaling.get("health", 1.0)),
		"damage": float(scaling.get("damage", 1.0)),
		"speed": float(scaling.get("speed", 1.0)),
	}

	var player = run_data.players_data[0]
	player.gold = int(build.get("gold", 0))
	player.current_level = int(build.get("level", 0))
	player.current_xp = 0.0
	# Full health, computed rather than assumed: max HP is the sum of everything added above, and
	# the game clamps nothing on load.
	player.current_health = run_data.get_player_max_health(0)

	# The four-slot arrays are the shop's, and BaseShop indexes them by player without checking
	# their size when it resumes from a saved state. An empty shop is correct here - the run is
	# saved as if the player had just walked into it and bought nothing.
	var state: Dictionary = progress_data.get_run_state(
		[[], [], [], []], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]
	)

	var loader = load(LOADER_V3).new("", int(build.get("profile_id", 0)))
	var serialized: Dictionary = loader.serialize_run_state(state)
	if not serialized.get("has_run_state", false):
		printerr("the state serialised as empty - nothing would load")
		return 1

	if not _write_json(out_path, {"current_run_state": serialized}):
		return 1

	print("character   : ", character_id)
	print("weapons     : ", weapon_count)
	print("items       : ", item_count, " (plus the character, which the game stores as one)")
	print("wave        : ", run_data.current_wave, "  zone ", run_data.current_zone,
		"  danger ", run_data.current_difficulty, "  endless ", run_data.is_endless_run)
	print("max hp      : ", player.current_health)
	print("bounces     : ", run_data.get_player_effect(keys.bounce_hash, 0))
	print("fruit drops : ", run_data.get_player_effect(keys.enemy_fruit_drops_hash, 0), "% per enemy")
	print("luck        : ", run_data.get_player_effect(keys.stat_luck_hash, 0))
	print("attack speed: ", run_data.get_player_effect(keys.stat_attack_speed_hash, 0))
	print("engineering : ", run_data.get_player_effect(keys.stat_engineering_hash, 0))
	print("structures  : ", run_data.get_player_effect(keys.structures_hash, 0).size())
	print("enemy dmg   : x", run_data.current_run_accessibility_settings.damage)
	print("wrote       : ", out_path)

	return 0


func _cmdline_options() -> Dictionary:
	var options := {}
	for arg in OS.get_cmdline_args():
		if not arg.begins_with("--") or not "=" in arg:
			continue
		var split = arg.substr(2, arg.length() - 2).split("=", true, 1)
		options[split[0]] = split[1]
	return options


func _read_json(path: String):
	var file := File.new()
	if file.open(path, File.READ) != OK:
		printerr("cannot read ", path)
		return null
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse(text)
	if parsed.error != OK:
		printerr("%s is not valid JSON: line %d, %s" % [path, parsed.error_line, parsed.error_string])
		return null
	if not parsed.result is Dictionary:
		printerr(path, " is not a JSON object")
		return null
	return parsed.result


func _write_json(path: String, data: Dictionary) -> bool:
	var file := File.new()
	if file.open(path, File.WRITE) != OK:
		printerr("cannot write ", path)
		return false
	file.store_string(JSON.print(data))
	file.close()
	return true
