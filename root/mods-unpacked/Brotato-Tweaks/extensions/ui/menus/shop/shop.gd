extends "res://ui/menus/shop/shop.gd"

# Adapter: Recycle items, on the single-player shop.
#
# Vanilla wraps all three of the item popup's buttons here with the same two lines — drop the dimmer
# that sits behind a focused popup, and let the shop card underneath be selected again. Recycling an
# item is a press on the same popup, so it gets the same two lines, through the hooks
# extensions/ui/menus/shop/base_shop.gd calls either side of the recycle.
#
# Both run whether or not the recycle went through, which is what vanilla's own wrappers do: they
# hide the dimmer before a base call that can return without doing anything.
#
# See docs/01-architecture.md ("Extension points").


func _tweaks_recycle_started(_player_index: int) -> void:
	_block_background.hide()


func _tweaks_recycle_finished(player_index: int) -> void:
	if _focused_shop_item[player_index] != null:
		_focused_shop_item[player_index]._can_be_selected()
