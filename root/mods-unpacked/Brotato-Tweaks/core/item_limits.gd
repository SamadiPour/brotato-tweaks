extends Reference

# Pure: whether the game's own per-item cap should be ignored for one item.
#
# `ItemData.max_nb` is the whole of that cap, and one integer says four different things:
#
#   -1   no cap at all, which is most of the catalogue
#    0   never offered — the item exists but `init_unlocked_pool()` keeps it out of every pool
#    1   unique: one per run, and the shop card reads "Unique"
#   >1   limited: that many per run, and the card reads "Limited (1/2)"
#
# The cap is enforced in exactly one place, `ItemService.get_limited_items()`, which counts what a
# player owns (plus what is locked in the shop) and hands back the ones that are at their number;
# `_get_rand_item_for_wave()` then drops those from the pool it rolls from. So lifting the cap is
# not a new rule — it is leaving that answer out.
#
# Two switches rather than one, because they are two different runs. Three Wheelbarrows is a
# harvesting build the game already lets you build most of; three of a unique is a build the game
# has never had to be balanced for. Anyone who wants the first does not necessarily want the second.
#
# 0 is deliberately not liftable. An item the game never offers is not an item you are being
# rationed — it is a character's own item, or one that only arrives from an effect, and putting it
# in the shop pool would be a different feature with a different failure mode.

const NO_CAP := -1
const NEVER_OFFERED := 0
const UNIQUE := 1


# `max_nb` is the item's own cap. `lift_limited` and `lift_unique` are the two tweaks.
static func lifted(max_nb: int, lift_limited: bool, lift_unique: bool) -> bool:
	if max_nb <= NEVER_OFFERED:
		return false
	if max_nb == UNIQUE:
		return lift_unique
	return lift_limited
