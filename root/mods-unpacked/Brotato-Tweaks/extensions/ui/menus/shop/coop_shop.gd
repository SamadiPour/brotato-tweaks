extends "res://ui/menus/shop/coop_shop.gd"

# Adapter: Recycle items, on the co-op shop.
#
# The same shape as extensions/ui/menus/shop/shop.gd against the other shop screen. Vanilla wraps
# all three of the item popup's buttons here with one line — the player's own container puts its
# focused popup away — and recycling an item is a press on that same popup.
#
# See docs/01-architecture.md ("Extension points").


func _tweaks_recycle_finished(player_index: int) -> void:
	_get_coop_player_container(player_index).on_hide_focused_inventory_popup()
