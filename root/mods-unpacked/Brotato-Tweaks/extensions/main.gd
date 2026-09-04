extends "res://main.gd"

# Adapter: the Piggy Bank, past wave 20.
#
# `gain_pct_gold_start_wave` is paid out in one place, inside `_on_EntitySpawner_players_spawned()`:
#
#     var pct_val = RunData.get_player_effect(Keys.gain_pct_gold_start_wave_hash, i)
#     var apply_pct_gold_wave = (pct_val > 0 and RunData.current_wave <= RunData.nb_of_waves) or pct_val < 0
#
#     if pct_val < 0 and RunData.current_wave > RunData.nb_of_waves:
#         pct_val = - 100.0
#
#     if apply_pct_gold_wave:
#         var val = RunData.get_player_gold(i) * (pct_val / 100.0)
#         RunData.add_gold(val, i)
#         if pct_val > 0:
#             RunData.add_tracked_value(i, Keys.item_piggy_bank_hash, val)
#
# A positive rate — the Piggy Bank's +20%, and only ever that item — is paid up to
# `nb_of_waves` and then never again. A negative one is the Entrepreneur, who loses materials at
# the start of a wave, and vanilla keeps applying that in endless at a forced -100%.
#
# The condition is a comparison inside a hundred-line method, so there is nothing to wrap tighter
# than the method itself. The adapter calls vanilla, and then, only past `nb_of_waves` and only
# for a rate vanilla skipped, does what vanilla would have done with it: the same two lines,
# reading the same effect, in the same order. Vanilla's own branch and this one are mutually
# exclusive — one runs at or below `nb_of_waves` and the other only above it — so a wave is never
# paid twice.
#
# `_on_EntitySpawner_players_spawned()` is connected by name from `main.gd::_ready()`
# (`_entity_spawner.connect("players_spawned", self, "_on_EntitySpawner_players_spawned")`), so an
# override on the extension is what the signal reaches. It contains no `yield`, so the base call
# has finished by the time this continues.
#
# The vanilla script carries `class_name Main`, which is why this file binds by path and never
# declares one of its own.
#
# See docs/01-architecture.md ("Extension points").

# Every local here is annotated rather than inferred. `res://main.gd` is the script this file is
# replacing, so while the loader is installing the extension the parser cannot resolve the base
# class it is being asked to infer return types through, and a `:=` becomes "the variable type
# can't be inferred" in the loader's own log.
const TWEAKS_GROUP := "brotato_tweaks"


func _on_EntitySpawner_players_spawned(players: Array) -> void:
	._on_EntitySpawner_players_spawned(players)

	# Vanilla already paid every rate at or below the last wave, including this one.
	if RunData.current_wave <= RunData.nb_of_waves:
		return

	var tweaks = _tweaks()
	if tweaks == null or not tweaks.keep_piggy_bank():
		return

	for player_index in players.size():
		var pct: float = float(RunData.get_player_effect(Keys.gain_pct_gold_start_wave_hash, player_index))
		# A rate of zero is nobody's Piggy Bank, and a negative one is the Entrepreneur, whom
		# vanilla has already charged in the call above.
		if pct <= 0.0:
			continue

		var value: float = RunData.get_player_gold(player_index) * (pct / 100.0)
		RunData.add_gold(value, player_index)
		RunData.add_tracked_value(player_index, Keys.item_piggy_bank_hash, value)
		tweaks.report_piggy_bank(player_index, int(value))


func _tweaks():
	if not is_inside_tree():
		return null
	var found: Array = get_tree().get_nodes_in_group(TWEAKS_GROUP)
	if found.empty() or not is_instance_valid(found[0]):
		return null
	return found[0]
