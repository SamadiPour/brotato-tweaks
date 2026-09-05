extends "res://ui/menus/run/difficulty_selection/difficulty_selection.gd"

# Adapter: the ban allowance, second of the two places vanilla sets it.
#
# `_on_element_pressed()` is the difficulty card the player clicks to start the run, and the last
# thing it does before changing scene is hand every player `RunData.BAN_MAX_TOKEN` tokens and the
# ban-mode toggle. That write happens after `RunData.reset()` has already run, so the allowance
# set there is overwritten by the constant unless this one runs too.
#
# Vanilla's own guard is the seam: `difficulty_selected` is false on the way in and true on the way
# out, and only on the call that actually starts a run. Reading it either side of the vanilla call
# is what distinguishes "the run just started" from a second click, a special element, or a
# cancelled selection — without copying a line of the decision.
#
# `change_scene()` is queued rather than immediate, and `RunData` is an autoload either way, so
# writing to player data after the vanilla call is writing to the run that is about to begin.
#
# See docs/01-architecture.md ("Extension points").

const TweaksLookup = preload("res://mods-unpacked/Brotato-Tweaks/core/tweaks_lookup.gd")


func _on_element_pressed(element: InventoryElement, inventory_player_index: int) -> void:
	var was_selected := difficulty_selected

	._on_element_pressed(element, inventory_player_index)

	if was_selected or not difficulty_selected:
		return

	var tweaks = _tweaks()
	if tweaks == null:
		return
	tweaks.apply_ban_tokens(RunData.players_data, RunData.get_player_count())


func _tweaks():
	return TweaksLookup.find(self)
