extends Reference

# The other half of the enemy multiplier: how fast the spawn queue is allowed to empty.
#
# Multiplying a wave's spawn plan (core/wave_scaling.gd) decides how many enemies are *queued*.
# It does not decide how many arrive, because vanilla drains that queue on a fixed budget —
# `EntitySpawner._physics_process()`:
#
#     cur_spawn_delay += 1
#     if cur_spawn_delay >= SPAWN_DELAY:          # SPAWN_DELAY = 3
#         var nb_to_spawn = 1
#         if queue_to_spawn.size() >= QUEUE_LIMIT:   # QUEUE_LIMIT = 100
#             nb_to_spawn = int(clamp((queue_to_spawn.size() - QUEUE_LIMIT) / 10.0, 1, 2))
#         for i in nb_to_spawn:
#             spawn(queue_to_spawn)              # pops exactly one
#         cur_spawn_delay = 0
#
# One entity per `spawn()` call, at most two calls, once every three physics frames. At Godot 3's
# default 60 physics ticks that is a hard ceiling of **40 enemies a second**, and it does not move
# when `max_enemies` or the multiplier does.
#
# Which is why "lift the enemy cap" can look like it does nothing at a high multiplier. On an
# endless wave the plan already queues faster than 40/s before any multiplier is applied; at 10x
# it queues several hundred a second, the queue grows for the whole wave, and the number alive is
# 40/s times how long an enemy survives — a number that never approaches the lifted cap. The cap
# is real and it is raised; it simply stops being the thing in the way.
#
# So this module answers one question, once per spawn tick: how many *extra* pops to add on top of
# vanilla's, so the drain keeps pace with a plan that was multiplied. `VANILLA_PER_TICK` is
# subtracted because vanilla has already run by the time the adapter asks.
#
# Pure — no node, no singleton, no game class. The queue is passed in as a size.

# What vanilla's own budget is worth, at the point this is asked. The adapter runs after
# `._physics_process()`, and the branch that matters is always the loaded one: a queue big enough
# to need help is a queue past `QUEUE_LIMIT`, where vanilla's `nb_to_spawn` is 2.
const VANILLA_PER_TICK := 2

# The multiplier bounds, kept the same as core/wave_scaling.gd's so the two halves of the feature
# agree about what a dial of 10 means.
const MIN_MULTIPLIER := 1.0
const MAX_MULTIPLIER := 20.0

# A ceiling on one tick's worth, so a hand-edited config cannot ask the spawner to instance a
# thousand enemies inside a single frame. At the top of the range this is 20 spawn ticks a second
# times 40 = 800 enemies a second, which is already far past what any machine will draw.
const MAX_PER_TICK := 40


# What one spawn tick is worth in total, queue permitting. `VANILLA_PER_TICK` whenever the tweak
# has nothing to add, so this is always the honest number to print next to the lifted cap.
static func budget_per_tick(multiplier: float, enabled: bool) -> int:
	if not enabled:
		return VANILLA_PER_TICK

	var factor := clamp(multiplier, MIN_MULTIPLIER, MAX_MULTIPLIER)
	if factor <= 1.0:
		return VANILLA_PER_TICK

	return int(min(round(VANILLA_PER_TICK * factor), float(MAX_PER_TICK)))


# How many additional entities may be popped from the enemy queue this tick — the budget above,
# less the share vanilla has already spent by the time the adapter asks.
#
# 0 whenever there is nothing to gain: the feature is off, the dial is at 1, or the queue is empty
# — in which case the adapter does not touch the queue at all and the cost of this being on is one
# comparison per spawn tick.
static func extra_per_tick(queue_size: int, multiplier: float, enabled: bool) -> int:
	if queue_size <= 0:
		return 0

	var extra := budget_per_tick(multiplier, enabled) - VANILLA_PER_TICK

	# Never more than the queue holds: `EntitySpawner.spawn()` returns early on an empty array, so
	# asking for more would be harmless but would still be a lie in the verbose log.
	return int(clamp(min(extra, queue_size), 0, MAX_PER_TICK))
