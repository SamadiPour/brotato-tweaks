extends Reference

# Finding the mod's own node — the one thing all thirteen adapters have to do before they can ask
# anything.
#
# `Tweaks` is reached through the "brotato_tweaks" group rather than a node path, so it does not
# matter where the loader mounts `mod_main` (docs/01-architecture.md, rule 6). Nothing found means
# the mod is not mounted yet, and every caller reads that as "do nothing and let vanilla stand".
#
# Two shapes, because the adapters genuinely need two:
#
#     func _tweaks():
#         return TweaksLookup.find(self)
#
#     func _tweaks():                                       # hot paths, and after leaving the tree
#         _tweaks_node = TweaksLookup.cached(self, _tweaks_node)
#         return _tweaks_node
#
# Static, so no adapter instances anything to ask.

const GROUP := "brotato_tweaks"


# The mod's node, or null. `is_inside_tree()` is what makes `get_tree()` safe to call on the next
# line, and it is false for exactly the case this has to survive: an adapter running before the mod
# is mounted, or after its own node has been taken out of the tree.
static func find(node):
	if node == null or not node.is_inside_tree():
		return null
	var found: Array = node.get_tree().get_nodes_in_group(GROUP)
	if found.empty() or not is_instance_valid(found[0]):
		return null
	return found[0]


# The same answer, reusing one already found while it is still valid. Returns what the caller should
# store, because a static function cannot write to the caller's field.
#
# Two reasons an adapter wants this, and they are not the same reason. `singletons/run_data.gd` and
# `global/entity_spawner.gd` ask on a hot path, where walking the tree per call is far too much.
# `ui/menus/shop/base_shop.gd` asks from `_on_tree_exited()`, where the node has already left the
# tree, `get_tree()` is null and `find()` cannot answer at all — so it looks the node up while the
# screen is being built and keeps it for the one call that comes after.
static func cached(node, current):
	if current != null and is_instance_valid(current):
		return current
	return find(node)
