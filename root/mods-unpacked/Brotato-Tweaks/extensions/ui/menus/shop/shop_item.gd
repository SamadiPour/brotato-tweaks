extends "res://ui/menus/shop/shop_item.gd"

# Adapter: "Ban weapons too", and the challenge gate in front of bans.
#
# Vanilla's `manage_ban_button_visibility()` opens with one line that hides the ban button for
# three reasons at once — the ban challenge is not completed, ban mode is off for this run, or the
# thing on the card is a weapon. The last of those is the only restriction on banning weapons that
# exists: everything past that line already works for a `WeaponData`, `ban_item()` pushes
# `my_id_hash` whatever it is, `ItemService` drops that id from the pool it rolls from, and the
# game bans weapons from item boxes this way already (`Main.on_item_box_ban_button_pressed()`).
#
# So this does not replace the method. It calls vanilla, which decides everything, and then — only
# when the ban tweak is on — re-runs the tail vanilla skips: the same text, the same show, the same
# `activate()`. For an item on a save that has the challenge, that tail is what vanilla just did
# and running it again changes nothing. For a weapon, or on a save that has not completed the
# challenge yet, it is the button vanilla hid.
#
# The one restriction kept is the fisherman's bait: the character is built around that item, and
# hiding its ban button is not a gate, it is the game refusing to let you break yourself.
#
# See docs/01-architecture.md ("Extension points").

const TWEAKS_GROUP := "brotato_tweaks"


func manage_ban_button_visibility() -> void:
	.manage_ban_button_visibility()

	var tweaks = _tweaks()
	if tweaks == null or tweaks.ban_allowance() < 0:
		return
	if item_data == null:
		return
	if item_data is WeaponData and not tweaks.bans_cover_weapons():
		return
	if not RunData.is_ban_active_in_current_run():
		return
	if _tweaks_is_protected_bait():
		return

	var remaining_ban_token = RunData.players_data[player_index].remaining_ban_token
	_ban_button.text = Text.text("BAN_SHOP", [str(remaining_ban_token)])
	if remaining_ban_token > 0:
		if not RunData.is_coop_run:
			_ban_button.show()
		_ban_button.activate()
	else:
		_ban_button.disable()
		_ban_button.hide()


# Vanilla's own exception, unchanged: the fisherman may not ban bait.
func _tweaks_is_protected_bait() -> bool:
	if item_data.my_id_hash != Keys.item_bait_hash:
		return false
	if player_index >= RunData.players_data.size():
		return false
	var character = RunData.players_data[player_index].current_character
	return character != null and character.my_id_hash == Keys.character_fisherman_hash


func _tweaks():
	if not is_inside_tree():
		return null
	var found := get_tree().get_nodes_in_group(TWEAKS_GROUP)
	if found.empty() or not is_instance_valid(found[0]):
		return null
	return found[0]
