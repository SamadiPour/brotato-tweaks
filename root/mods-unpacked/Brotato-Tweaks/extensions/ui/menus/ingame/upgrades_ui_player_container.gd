extends "res://ui/menus/ingame/upgrades_ui_player_container.gd"

# Adapter: the ban allowance, on the one screen that shows it as a number.
#
# This is the panel behind a crate or a consumable — the one that offers "recycle" and "ban" for
# the item it is showing. It is also the only place bans are printed as a fraction:
#
#     MENU_BAN (RunData.BAN_MAX_TOKEN - remaining / RunData.BAN_MAX_TOKEN)
#
# Both halves read the constant, so with an allowance of 20 and none spent the vanilla label says
# "(-12/8)". The count itself is right — it is `remaining_ban_token`, which this mod sets — so only
# the label has to be rewritten, and it is rewritten with the same two numbers the allowance is
# made of. `core/loadout.gd` owns that subtraction so the label and the token count cannot drift.
#
# `_ready()` is here for the other half of the same feature: vanilla hides this ban button until
# the ban challenge is completed, and the tweak lifts that the same way the shop adapter does.
# Nothing is re-implemented in either method — vanilla runs first and decides, and this changes
# only what the tweak is for.
#
# See docs/01-architecture.md ("Extension points").

const TWEAKS_GROUP := "brotato_tweaks"


# No `._ready()`: Godot runs every `_ready()` in the script chain, base first, so vanilla's has
# already hidden or shown the button by the time this runs and calling it again would run it twice.
func _ready() -> void:
	var tweaks = _tweaks()
	if tweaks == null or tweaks.ban_allowance() < 0:
		return
	if not RunData.is_ban_active_in_current_run():
		return

	_ban_button.visible = true
	_icon_ban.modulate = Color(ProgressData.settings.color_negative)
	_progress_ban.modulate = Color(ProgressData.settings.color_negative)


func show_item(item_data: ItemParentData) -> void:
	.show_item(item_data)

	var tweaks = _tweaks()
	if tweaks == null:
		return

	var remaining: int = RunData.players_data[player_index].remaining_ban_token
	var counts: Dictionary = tweaks.ban_label_counts(remaining)
	if not counts.apply:
		return
	if remaining <= 0:
		# Vanilla hides the button entirely in this case, and there is nothing left to label.
		return

	var recycling = floor(ItemService.get_recycling_value(
		RunData.current_wave, item_data.value, player_index, item_data is WeaponData
	))
	_ban_button_label.text = "%s (%d/%d) (+%s)" % [
		tr("MENU_BAN"), int(counts.spent), int(counts.allowance), str(recycling),
	]


func _tweaks():
	if not is_inside_tree():
		return null
	var found := get_tree().get_nodes_in_group(TWEAKS_GROUP)
	if found.empty() or not is_instance_valid(found[0]):
		return null
	return found[0]
