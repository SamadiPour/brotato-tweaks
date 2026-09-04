extends Reference

# Bonus elites and bonus bosses, as a pure "how many, and which ones" decision.
#
# This is the counterpart to core/elite_schedule.gd and deliberately not the same feature.
# `elite_schedule.gd` moves vanilla's own timetable around: a run still gets one or three elites,
# on waves the game rolls, some of them hordes. This one is not a schedule and not a roll — it
# adds a fixed number of elites (or bosses) to *every* wave, on top of whatever that wave was
# already going to spawn, from wave 1. The two can be on at once and do not interact: vanilla's
# scheduled elite still arrives on its own wave, with these on top of it.
#
# Only two things need deciding, and neither of them touches a game class:
#
#   1. how many — a clamp, so a hand-edited config cannot ask for a hundred bosses;
#   2. which ones — picked out of the pool the zone offers.
#
# The picking rule is vanilla's, generalised. `RunData.init_elites_spawn()` erases each elite it
# picks from `possible_elites`, so a run never gets the same elite twice while others are left.
# That only has to work up to three. Here the count goes to ten and a zone has fewer elites than
# that, so the pool is emptied before it is refilled: every distinct member appears once before
# any of them appears twice, and the order is random both times.
#
# Pure — no node, no singleton, no game class. `pool` is whatever the caller has (elite or boss
# item resources); this only reorders and repeats what it is handed.

const MIN_COUNT := 1
const MAX_COUNT := 10


# What the dial is worth, as a whole number of spawns. Anything outside the range the schema
# allows is clamped rather than refused: the only way to get here with one is a hand-edited
# config, and a wave with ten bonus bosses is already the extreme end of the feature.
static func count(wanted: float) -> int:
	return int(clamp(round(wanted), MIN_COUNT, MAX_COUNT))


# `wanted` picks out of `pool`, every distinct member before any repeat, in random order. Empty
# when there is nothing to pick from, which is the honest answer for a zone with no elites of its
# own rather than a reason to fall back to another zone's.
static func pick(pool: Array, wanted: int) -> Array:
	var picked := []
	if pool.empty() or wanted <= 0:
		return picked

	var bag := []
	while picked.size() < wanted:
		if bag.empty():
			bag = pool.duplicate()
			bag.shuffle()
		picked.append(bag.pop_back())

	return picked
