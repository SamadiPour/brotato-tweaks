extends "res://singletons/entity_service.gd"

# Adapter: the enemy health / damage / speed dials.
#
# These three are where every enemy stat is finally resolved — the base value from the enemy's own
# resource, multiplied by the danger level, the co-op count, item effects, the endless factor and
# the player's accessibility sliders. Every enemy asks through them, so a dial on the way out is
# the whole feature.
#
# Vanilla is called first and its result is scaled, rather than the multiplier being folded into
# the factor: those factors are cached per wave in `factor_cache`, so a change made inside would
# not take effect until the next `reset_cache()`. On the return value it applies immediately, and
# nothing the game caches is touched.
#
# When the feature is off these are exact identity wrappers — vanilla already returned a rounded
# int, so rounding it again changes nothing.
#
# See docs/01-architecture.md ("Extension points").

const TweaksLookup = preload("res://mods-unpacked/Brotato-Tweaks/core/tweaks_lookup.gd")


func get_final_enemy_damage(from_value: float, percent_modifier: int = 0) -> int:
	var vanilla := .get_final_enemy_damage(from_value, percent_modifier)
	var tweaks = _tweaks()
	return vanilla if tweaks == null else tweaks.scale_enemy_damage(float(vanilla))


func get_final_enemy_health(from_value: int, percent_modifier: int = 0) -> int:
	var vanilla := .get_final_enemy_health(from_value, percent_modifier)
	var tweaks = _tweaks()
	return vanilla if tweaks == null else tweaks.scale_enemy_health(float(vanilla))


func get_final_enemy_speed(from_value: int, effects_factor: float, percent_modifier: int = 0) -> int:
	var vanilla := .get_final_enemy_speed(from_value, effects_factor, percent_modifier)
	var tweaks = _tweaks()
	return vanilla if tweaks == null else tweaks.scale_enemy_speed(float(vanilla))


func _tweaks():
	return TweaksLookup.find(self)
