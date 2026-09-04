extends Reference

# Pure: the one number the shop needs before it can price a recycle, and the one piece of vanilla's
# recycle path that is arithmetic rather than UI.
#
# `specific_items_price` is a player effect — an array of `[item id hash, factor]` pairs, filled by
# the items that make one particular item cheaper or dearer. Vanilla multiplies the item's own
# `value` by the first factor whose id appears in the item's id, and its comparison is a substring
# test on the *names*, not on the hashes:
#
#     if Keys.hash_to_string[pair[0]] in item_data.my_id:
#
# so a pair naming "item_baby_elephant" matches that item alone, and a pair naming a prefix several
# items share matches all of them. That is copied exactly, because the shop card and the payout have
# to agree with each other and with what vanilla does for a weapon.
#
# `id_names` is `Keys.hash_to_string`, passed in so this file names no game singleton and
# tests/run.sh can drive it. 1.0 is "no item is changing this item's price", which is the normal
# case and what an empty effect means.


static func price_factor(specific_items_price: Array, item_id: String, id_names: Dictionary) -> float:
	for pair in specific_items_price:
		if not (pair is Array) or pair.size() < 2:
			continue
		if not id_names.has(pair[0]):
			continue
		var id_name := str(id_names[pair[0]])
		if id_name != "" and id_name in item_id:
			return float(pair[1])
	return 1.0
