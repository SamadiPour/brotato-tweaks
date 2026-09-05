extends "res://ui/menus/shop/item_popup.gd"

# Adapter: Recycle items — the button half.
#
# This popup is what appears beside a weapon or an item in the shop's gear panel. Vanilla gives it
# Combine / Recycle / Cancel for a weapon and nothing at all for an item, in one line:
#
#     return buttons_enabled and item_data is WeaponData and (not RunData.is_coop_run or focused)
#
# So an item you already own is the one thing in the run you cannot get rid of. With the tweak on,
# an owned item gets the same popup, with Recycle and Cancel on it.
#
# Two methods vanilla can no longer be asked to run for an item, and one it can:
#
#   * `should_show_buttons()` is *widened*, not replaced — vanilla decides first, and this adds the
#     item case on top of whatever it said.
#   * `_update_button_visibilities()` is vanilla's own body minus one line, because that line is
#     `RunData.can_combine(_item_data, ...)`, which is typed `WeaponData` and cannot be handed an
#     item. Combining is not a thing an item does, so the button is hidden instead.
#   * `_on_DiscardButton_pressed()` routes an item to the shop by hand. `item_discard_button_pressed`
#     lands on `BaseShop._on_item_discard_button_pressed(weapon_data: WeaponData, …)`, and GDScript
#     refuses an override that widens a parameter — "The function signature doesn't match the
#     parent" is a parse error, not a warning. See below for how the shop is reached instead.
#
# See docs/01-architecture.md ("Extension points").

const TweaksLookup = preload("res://mods-unpacked/Brotato-Tweaks/core/tweaks_lookup.gd")


func should_show_buttons(item_data: ItemParentData, focused: bool) -> bool:
	if .should_show_buttons(item_data, focused):
		return true
	if not _tweaks_recycles(item_data):
		return false
	# The rest of vanilla's own condition, unchanged: in co-op every player has a popup of their
	# own, and only the one being driven may show buttons.
	return not RunData.is_coop_run or focused


func _update_button_visibilities() -> void:
	if not _tweaks_recycles(_item_data):
		._update_button_visibilities()
		return

	var buttons := [_combine_button, _discard_button, _cancel_button]
	if not should_show_buttons(_item_data, _focused):
		for button in buttons:
			button.hide()
			button.focus_mode = FOCUS_NONE
		return

	for button in buttons:
		button.show()
		button.focus_mode = FOCUS_ALL if _focused else FOCUS_NONE

	_combine_button.hide()
	_combine_button.focus_mode = FOCUS_NONE

	_discard_button.text = "%s (+%d)" % [tr("MENU_RECYCLE"), _tweaks_recycling_value()]


func _on_DiscardButton_pressed() -> void:
	if not _tweaks_recycles(_item_data):
		._on_DiscardButton_pressed()
		return

	# The shop is found off this popup's own connection list, the same way the DLC's curse behaviour
	# is found in extensions/global/entity_spawner.gd. The one thing connected to
	# `item_discard_button_pressed` is the shop that built this popup, it was connected with the
	# player index as its bind, and only this mod's own `BaseShop` extension has the method asked
	# for here — so nothing else can answer by accident.
	var item = _item_data
	_focused = false

	for connection in get_signal_connection_list("item_discard_button_pressed"):
		var target = connection.get("target")
		if target == null or not is_instance_valid(target):
			continue
		if not target.has_method("tweaks_recycle_item"):
			continue

		var index: int = player_index
		var binds = connection.get("binds")
		if binds is Array and not binds.empty() and binds[0] is int:
			index = binds[0]

		target.tweaks_recycle_item(item, index)
		return


# What the Recycle button is worth, priced exactly the way vanilla prices a weapon's: the item's own
# value through the `specific_items_price` factor first, then through `ItemService`, with `is_weapon`
# false. The shop pays out through the same two steps, so the label and the payout cannot drift.
func _tweaks_recycling_value() -> int:
	var tweaks = _tweaks()
	if tweaks == null:
		return 0

	var factor: float = tweaks.recycle_price_factor(
		RunData.get_player_effect(Keys.specific_items_price_hash, player_index),
		_item_data.my_id,
		Keys.hash_to_string
	)
	return ItemService.get_recycling_value(
		RunData.current_wave, int(_item_data.value * factor), player_index, false
	)


# Whether this popup is showing something the tweak covers: an item the player already owns, on a
# screen whose buttons are live.
#
# A weapon is vanilla's own recycle and is left entirely to it. A `CharacterData` is an `ItemData`
# too and sits in the same inventory — recycling the character would strip the run of everything the
# character gives it — so it is excluded here rather than guarded for later.
#
# `_is_inventory_element` is set by the same call that sets `_item_data`, so the two never disagree.
# It is what keeps the button off a shop card in co-op, where a focused card is displayed through
# this same popup.
func _tweaks_recycles(item_data) -> bool:
	if not buttons_enabled:
		return false
	if item_data == null or not (item_data is ItemData) or item_data is CharacterData:
		return false
	if not _is_inventory_element:
		return false

	var tweaks = _tweaks()
	return tweaks != null and tweaks.recycle_items()


func _tweaks():
	return TweaksLookup.find(self)
