extends Reference

# The enemy health / damage / speed dials, as arithmetic.
#
# `EntityService.get_final_enemy_health()`, `get_final_enemy_damage()` and `get_final_enemy_speed()`
# are where the game multiplies a base stat by everything that modifies it — the danger level, the
# co-op player count, item effects, the endless factor, and the player's own accessibility sliders
# (`ProgressData.settings.enemy_scaling`, which is exactly this feature with a different name and
# a Options-menu home). Each returns a rounded int, so a dial on the way out is one multiply.
#
# Going out rather than in, and past the game's own factor cache: those three functions cache the
# combined factor per wave under `EntityService.factor_cache`, so a multiplier folded into the
# factor would be cached with it and only take effect on the next `reset_cache()`. On the return
# value it takes effect immediately, and nothing the game caches is touched.
#
# Floors differ by stat because zero means different things:
#
#   - health floors at 1. A zero-health enemy is a dead enemy at spawn, and the spawn/death path
#     is not built to be entered in that order.
#   - damage floors at 1, because the game does. `Player.get_damage_value()` resolves an armoured
#     hit as `max(1, round(dmg_value * armor_coef))`, so a zero here is a 1 there and "harmless
#     enemies" is not a thing this seam can produce. Flooring at 1 makes the dial say what it does.
#   - speed floors at 0, which is standing still — the same thing vanilla's own
#     `DebugService.nullify_enemy_speed` produces, so the movement behaviours already handle it.
#
# Pure.

const MIN_MULTIPLIER := 0.0
const MAX_MULTIPLIER := 5.0


static func scale(value: float, multiplier: float, minimum: int) -> int:
	var factor := clamp(multiplier, MIN_MULTIPLIER, MAX_MULTIPLIER)
	return int(max(float(minimum), round(value * factor)))
