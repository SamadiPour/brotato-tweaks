extends "res://singletons/zone_service.gd"

# Adapter: wave length.
#
# `get_wave_data()` is the only seam for this. `Main._ready()` reads `wave_duration` off the result
# at line 165 to set the wave timer, and that happens long before `EntitySpawner.init()` — where
# the other wave-shaping tweak lives — so a change made there would arrive a frame too late.
#
# Vanilla hands back a `duplicate()` of the wave (and, in endless, a freshly assembled one), so
# writing to it is per-wave and thrown away when the wave ends. Nothing in the zone resource is
# touched.
#
# See docs/01-architecture.md ("Extension points").

const TWEAKS_GROUP := "brotato_tweaks"


func get_wave_data(my_id: int, index: int) -> Resource:
	var wave := .get_wave_data(my_id, index)
	var tweaks = _tweaks()
	if tweaks != null:
		tweaks.scale_wave_duration(wave)
	return wave


func _tweaks():
	if not is_inside_tree():
		return null
	var found := get_tree().get_nodes_in_group(TWEAKS_GROUP)
	if found.empty() or not is_instance_valid(found[0]):
		return null
	return found[0]
