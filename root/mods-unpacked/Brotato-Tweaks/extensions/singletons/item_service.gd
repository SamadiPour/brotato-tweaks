extends "res://singletons/item_service.gd"

# Adapter: All Cursed at the moment an item is rolled rather than the moment it is taken, and the
# two "no limit" tweaks.
#
# ## All Cursed
#
# `apply_item_effect_modifications()` is the last thing `_get_rand_item_for_wave()` does, and it is
# also what the guaranteed-shop-item path calls, so every item the game *offers* passes through it:
# the four shop slots and every reroll, a crate's item, a treasure map's extra item. It is where
# vanilla itself rolls the natural curse chance — the body is one loop over the enabled DLCs calling
# `dlc_data.update_item_effects(item, player_index)`, and Abyssal Terrors' implementation is a
# chance check around the same `curse_item()` this mod calls.
#
# Cursing here rather than only at pickup is what makes the shop tell the truth. `BaseShop.buy_item`
# hands `item_data` to `RunData.add_item()` and then puts *that same* `item_data` into the gear
# container — so a curse applied inside `add_item()` reaches the run but not the card the player
# just read, and the boosted stats, the curse icon and the `stat_curse` it charges all appear only
# after the purchase. Offered items are cursed before they are ever drawn, so what is on the shop
# card is what is bought.
#
# `singletons/run_data.gd` still curses on the way into the inventory, and that is not redundant:
# starting gear, the character-selection weapon, a consumable's item and anything another mod adds
# never pass through here. An item cursed here reaches that hook already cursed, and
# `core/curse.gd` hands an already cursed item straight back, so it is cursed exactly once.
#
# ## The item limits
#
# `get_limited_items()` is the whole of the game's per-item cap. It counts what the player owns —
# plus, at the two call sites, what is locked in the shop — and returns the ones that are at their
# `max_nb`; `_get_rand_item_for_wave()` drops exactly those from the pool it rolls from, and
# `UpgradesUI._recheck_extra_items()` drops them from a treasure map's extra crate item. Those two
# are its only callers, so leaving an entry out of what it answers is the whole feature, for the
# shop, for crates and for the map alike.
#
# What the answer is *used* for stays vanilla's: nothing here decides that a limited item should be
# offered, only that this one is no longer at its limit. `RunData.get_remaining_max_nb_item()` — the
# same cap read for the duplicating items — is lifted in the RunData adapter for the same reason.
#
# ItemService is autoload eleven and ModLoader is the sixth, so the extension is installed before
# the singleton is instanced.
#
# See docs/01-architecture.md ("Extension points").

const TWEAKS_GROUP := "brotato_tweaks"


func apply_item_effect_modifications(item: ItemParentData, player_index: int) -> ItemParentData:
	var vanilla = .apply_item_effect_modifications(item, player_index)

	var tweaks = _tweaks()
	if tweaks == null:
		return vanilla

	var cursed = tweaks.curse_data(vanilla, player_index, vanilla is WeaponData)
	return vanilla if cursed == null else cursed


# Vanilla decides which items are at their limit; this drops the ones the player asked to have no
# limit. Each entry is `[the uncursed item, how many are held]`, and it is the item's own `max_nb`
# that says whether it is a unique, a limited item or neither — see core/item_limits.gd.
#
# `keys()` is a fresh array in Godot 3, so erasing while walking it is safe.
func get_limited_items(from_items: Array) -> Dictionary:
	var limited: Dictionary = .get_limited_items(from_items)
	if limited.empty():
		return limited

	var tweaks = _tweaks()
	if tweaks == null:
		return limited

	for key in limited.keys():
		var entry = limited[key]
		if not (entry is Array) or entry.empty() or entry[0] == null:
			continue
		if not ("max_nb" in entry[0]):
			continue
		if tweaks.item_limit_lifted(int(entry[0].max_nb)):
			limited.erase(key)

	return limited


func _tweaks():
	if not is_inside_tree():
		return null
	var found := get_tree().get_nodes_in_group(TWEAKS_GROUP)
	if found.empty() or not is_instance_valid(found[0]):
		return null
	return found[0]
