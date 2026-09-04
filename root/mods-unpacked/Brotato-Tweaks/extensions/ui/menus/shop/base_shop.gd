extends "res://ui/menus/shop/base_shop.gd"

# Adapter: Recycle items — the shop half — and Recurse.
#
# ## Recycle items
#
# Vanilla recycles a weapon you own, in `_on_item_discard_button_pressed()` here, and an item you are
# being *offered*, in `Main.on_item_box_discard_button_pressed()`. An item you already have has no
# path at all. This is that third case, and it is a new method rather than an override because the
# vanilla one is typed `WeaponData` and GDScript will not let a subclass widen a parameter — see
# extensions/ui/menus/shop/item_popup.gd, which is what calls this.
#
# The body is vanilla's weapon recycle line for line, with four deliberate differences:
#
#   * `RunData.remove_item()` rather than `remove_weapon()`, and the items half of the gear container
#     rather than the weapons half.
#   * One press recycles one copy. `Inventory.remove_element()` walks a stacked element's number down
#     by one and frees the element only on the last of them, and `RunData.remove_item()` erases the
#     first match and stops — so three of an item takes three presses, which is what a stack of
#     identical weapons already does in vanilla.
#   * `is_weapon` is false everywhere the recycling value is priced.
#   * `RunData.add_recycled()` is *not* called. It is challenge progress and it is written to the
#     save file, and this mod writes nothing there. Vanilla's own item-box recycle does not call it
#     either, so an item recycle counting toward the recycling challenge would be new behaviour and
#     not a missing case.
#
# The two hooks at the bottom are what the two shop screens wrap this with; vanilla wraps its own
# recycle with exactly the same lines on each. They are empty here and overridden there rather than
# called through `.tweaks_recycle_item()`, so each screen's adapter still compiles on its own against
# pristine vanilla, which is what tests/run_extensions.sh does.
#
# ## Recurse
#
# `_on_tree_exited()` is the shop closing, and it is where vanilla rolls the Fish Hook: every locked
# slot that is *not* cursed gets a chance to be, and the ones that already are get nothing, because
# `curse_item()` cannot curse the same item twice. That is what makes a locked cursed item a dead
# end — the numbers it was given on the roll that cursed it are the numbers it keeps, for as long as
# it stays locked.
#
# So this is a pass over exactly the slots vanilla skips, run before vanilla's own so that an item
# it curses on this visit is not re-rolled the moment it is made. It leaves vanilla's pass looking
# at the same shop it would have: a slot that was cursed is still cursed afterwards, so nothing
# moves between vanilla's two branches and its pity counter is neither read nor written here.
#
# The re-roll has no chance of its own. It is the item's original put back through
# `ItemService.apply_item_effect_modifications()` — the one call every offered item passes through,
# where the game rolls its natural curse chance and where this mod's own extension applies All
# Cursed. So a cursed locked item is re-cursed exactly as often as a new item of the same kind would
# arrive cursed. `core/curse.gd` then decides which of the two the slot keeps; a roll that missed
# leaves the curse the slot already had, because an item cannot lose a curse by being offered one.
#
# See docs/01-architecture.md ("Extension points").

const TWEAKS_GROUP := "brotato_tweaks"

# `_on_tree_exited()` runs after the node has left the tree, where `get_tree()` is null and the
# group lookup this mod finds `Tweaks` with cannot be made at all. So it is found while the screen
# is being built and kept for the one call that needs it after.
var _tweaks_node = null


# No base call. Godot runs every `_ready()` in a script chain, base first, so vanilla's has already
# built the screen by the time this line runs and calling `._ready()` here would build it twice.
func _ready() -> void:
	var _found = _tweaks()


# Ours first, vanilla's after: see the note above. Vanilla's is the teardown here, so it goes last
# in any case.
func _on_tree_exited() -> void:
	_tweaks_recurse_locked_items()
	._on_tree_exited()


func _tweaks_recurse_locked_items() -> void:
	var tweaks = _tweaks()
	if tweaks == null or not tweaks.recurse_locked_items():
		return

	for player_index in range(RunData.get_player_count()):
		if player_index >= RunData.locked_shop_items.size():
			continue

		for entry in RunData.locked_shop_items[player_index]:
			if not (entry is Array) or entry.empty():
				continue

			var data = entry[0]
			if data == null or not ("is_cursed" in data) or not data.is_cursed:
				continue

			var base = _tweaks_uncursed(data)
			if base == null:
				continue

			# The offer roll, unchanged and unreimplemented: `apply_item_effect_modifications()` is
			# the one place the game decides whether an item it is offering arrives cursed, and this
			# mod's own extension of it is where All Cursed sits. So a locked item is re-cursed at
			# exactly the rate a new one of the same kind would be, and there is no chance here.
			var recursed = tweaks.recurse_locked(
				data, base, ItemService.apply_item_effect_modifications(base, player_index)
			)
			if recursed == null or recursed == data:
				continue

			entry[0] = recursed
			tweaks.report_recursed(str(data.my_id))


# The catalogue resource a cursed copy was made from. Null for anything this version of the game
# does not have an entry for, which the caller reads as "leave it alone".
func _tweaks_uncursed(data):
	if data == null or not ("my_id_hash" in data):
		return null
	var pool: Array = ItemService.weapons if data is WeaponData else ItemService.items
	return ItemService.get_element(pool, data.my_id_hash)


func tweaks_recycle_item(item_data, player_index: int) -> void:
	_tweaks_recycle_started(player_index)
	_tweaks_recycle(item_data, player_index)
	_tweaks_recycle_finished(player_index)


func _tweaks_recycle(item_data, player_index: int) -> void:
	var tweaks = _tweaks()
	if tweaks == null or not tweaks.recycle_items():
		return
	if item_data == null or not (item_data is ItemData) or item_data is CharacterData:
		return
	# The popup can only be showing something the player owns, but paying out for an item that is not
	# in the inventory would be free materials, so it is checked rather than assumed. The element and
	# `RunData` hold the same resource, so this is a reference test and not a comparison.
	if not RunData.get_player_items_ref(player_index).has(item_data):
		return

	_popup_manager.reset_focus(player_index)

	var items_container = _get_gear_container(player_index).items_container
	items_container._elements.remove_element(item_data, 1, true)

	RunData.remove_item(item_data, player_index)

	var factor: float = tweaks.recycle_price_factor(
		RunData.get_player_effect(Keys.specific_items_price_hash, player_index),
		item_data.my_id,
		Keys.hash_to_string
	)
	var value: int = ItemService.get_recycling_value(
		RunData.current_wave, int(item_data.value * factor), player_index, false
	)
	RunData.add_gold(value, player_index)
	RunData.update_recycling_tracking_value(item_data, player_index)

	# Vanilla's coupon bookkeeping, unchanged apart from `is_weapon`: the coupon tracks what the items
	# price stat cost you, and a recycle priced by that stat is part of the same sum.
	if RunData.get_nb_item(Keys.item_coupon_hash, player_index) > 0:
		var base_value: int = ItemService.get_recycling_value(
			RunData.current_wave, item_data.value, player_index, false, false
		)
		var actual_value: int = ItemService.get_recycling_value(
			RunData.current_wave, item_data.value, player_index, false
		)
		RunData.add_tracked_value(player_index, Keys.item_coupon_hash, -(base_value - actual_value))

	# `remove_item()` puts an item's replacement into the inventory, and no single-element edit can
	# show that. Redrawing the panel is what vanilla does for the same reason in `fill_shop_items()`.
	if item_data.replaced_by:
		_get_gear_container(player_index).set_items_data(RunData.get_player_items(player_index))

	_update_stats(player_index)
	_get_shop_items_container(player_index).reload_shop_items()

	var reroll_button = _get_reroll_button(player_index)
	reroll_button.set_color_from_currency(RunData.get_player_gold(player_index))

	SoundManager.play(Utils.get_rand_element(recycle_sounds), 0, 0.1, true)

	tweaks.report_item_recycled(item_data.my_id, value)


# Overridden by the two shop screens. Nothing to do on the base, which is never in the tree itself.
func _tweaks_recycle_started(_player_index: int) -> void:
	pass


func _tweaks_recycle_finished(_player_index: int) -> void:
	pass


func _tweaks():
	if _tweaks_node != null and is_instance_valid(_tweaks_node):
		return _tweaks_node
	if not is_inside_tree():
		return null
	var found := get_tree().get_nodes_in_group(TWEAKS_GROUP)
	if found.empty() or not is_instance_valid(found[0]):
		return null
	_tweaks_node = found[0]
	return _tweaks_node
