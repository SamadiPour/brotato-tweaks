extends Reference

# When elites and hordes are scheduled.
#
# `RunData.init_elites_spawn(base_wave := 10, horde_chance := 0.4)` picks the waves the run's
# elites arrive on — one at `base_wave + 1..2`, and at difficulty 4 and above two more at
# `base_wave + 4..5` and `base_wave + 7..8` — and rolls each as an elite or a horde. Everything
# about that is worth keeping; the only interesting inputs are its two arguments.
#
# **The catch, and the whole reason this module exists.** It has three callers, and they are not
# the same call:
#
#     run_data.gd:541                init_elites_spawn()                      # run start
#     difficulty_selection.gd:99     init_elites_spawn()                      # pre-run preview
#     main.gd:974                    init_elites_spawn(current_wave + 10, 0.0)  # endless top-up
#
# The endless one passes an *absolute* wave computed from where the run currently is. Overriding
# its `base_wave` with a fixed number would schedule endless elites at a wave already in the past,
# and they would simply never spawn — a bug that only shows up an hour into a run.
#
# So the override applies only to a call that used both vanilla defaults. That is precisely the
# "schedule this run's elites" call and never the endless top-up. The defaults are duplicated here
# from the vanilla signature, which makes them the one thing in this file that a game patch could
# silently invalidate: if they change, the override stops applying and elites go back to normal —
# the safe direction to fail in.
#
# Pure.

const VANILLA_BASE_WAVE := 10
const VANILLA_HORDE_CHANCE := 0.4

const MIN_FIRST_WAVE := 1
const MAX_FIRST_WAVE := 50


# `first_wave` is where the player wants the first elite; `horde_percent` is 0-100.
# Returns {apply, base_wave, horde_chance} — `apply` false means: pass the caller's own arguments
# through untouched.
static func override_args(base_wave: int, horde_chance: float, first_wave: int, horde_percent: float) -> Dictionary:
	var pass_through := {"apply": false, "base_wave": base_wave, "horde_chance": horde_chance}

	if base_wave != VANILLA_BASE_WAVE or not is_equal_approx(horde_chance, VANILLA_HORDE_CHANCE):
		return pass_through

	# The vanilla schedule puts the first elite at `base_wave + 1`, so the number the player picks
	# is one more than the argument that produces it.
	var wanted := int(clamp(first_wave, MIN_FIRST_WAVE, MAX_FIRST_WAVE))
	return {
		"apply": true,
		"base_wave": wanted - 1,
		"horde_chance": clamp(horde_percent / 100.0, 0.0, 1.0),
	}
