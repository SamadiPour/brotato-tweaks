extends Resource

# A shop item in miniature, for the recurse checks. Only the four fields core/curse.gd reads are
# here — the real `ItemParentData` has forty and none of the rest is asked about.
#
# `copy()` rather than `duplicate()`: the DLC's own `curse_item()` duplicates what it is handed, and
# a stub that leaned on Godot's copy semantics would be testing those rather than the mod. What the
# checks need from a copy is only that it is a different object with different numbers on it.

var my_id := "item_stub"
var my_id_hash := 1
var max_nb := -1
var is_cursed := false
var curse_factor := 0.0


func copy():
	var other = get_script().new()
	other.my_id = my_id
	other.my_id_hash = my_id_hash
	other.max_nb = max_nb
	other.is_cursed = is_cursed
	other.curse_factor = curse_factor
	return other
