extends "res://global/entity_spawner.gd"

# Adapter: the enemy multiplier, and the enemy half of All Cursed.
#
# `init()` is the one moment where the whole wave is decided and nothing has spawned yet.
# `Main._ready()` calls `WaveManager.init()` first — which is where vanilla finishes assembling
# `groups_data`, pushing in the zone's always-groups, the extra loot aliens, the elites, the
# horde and the DLC's own groups — and `EntitySpawner.init()` afterwards, in the same frame.
# By the time this runs the plan is complete, and `WaveManager._physics_process()` has not yet
# had a frame in which to emit a single spawn.
#
# Both objects hold the *same* `WaveData` instance, so rewriting it here is what the wave manager
# reads from a frame later. The rewriting itself is core/wave_scaling.gd's problem, including
# which groups may be touched and why each one is replaced rather than edited.
#
# Vanilla runs first and unconditionally: `init()` spawns the players and wires their weapons up,
# and none of that may be skipped or reordered.
#
# See docs/01-architecture.md ("Extension points").

const TweaksLookup = preload("res://mods-unpacked/Brotato-Tweaks/core/tweaks_lookup.gd")
const TWEAKS_FEATURE := "enemy_multiplier"

# The DLC's CurseSceneEffectBehavior, found once per wave off this node's own signal connections.
# See _tweaks_curse_behavior().
var _tweaks_curse_source = null

# The mod's own node, kept once found — see _tweaks().
var _tweaks_node = null


func init(
		zone_min_pos: Vector2,
		zone_max_pos: Vector2,
		current_wave_data: WaveData,
		wave_timer: Timer
	) -> void:

	.init(zone_min_pos, zone_max_pos, current_wave_data, wave_timer)

	_tweaks_curse_source = null
	if not is_connected("enemy_respawned", self, "_tweaks_on_enemy_respawned"):
		var _error = connect("enemy_respawned", self, "_tweaks_on_enemy_respawned")

	var tweaks = _tweaks()
	if tweaks == null:
		return

	# Hordes first, so the multiplier below applies to them like any other enemy group. Two
	# switches, one predictable rule.
	tweaks.inject_hordes(current_wave_data, _tweaks_horde_groups(), RunData.current_wave)

	# `EntityType.ENEMY` is passed through rather than read inside the mod so the enum stays the
	# game's to define. It is the same value vanilla tests against in
	# `on_group_spawn_timing_reached()`.
	tweaks.scale_wave(current_wave_data, EntityType.ENEMY)


# Adapter: the spawn queue's drain rate — the enemy multiplier's other half.
#
# Vanilla's `_physics_process()` releases at most two queued entities every third physics frame,
# and `spawn()` pops exactly one per call. That is 40 enemies a second at Godot 3's default
# physics rate, no matter what `max_enemies` or the multiplier say, so past about 4x the queue
# only grows and the lifted cap stops being what limits the crowd. core/spawn_rate.gd has the
# arithmetic and the vanilla source it was read from.
#
# Wrapping rather than replacing: vanilla runs first and untouched, and this adds pops after it.
# Nothing vanilla decides — the delay counter, its own budget, the four other queues — is
# reimplemented here, so another mod extending the same method still gets the behaviour it wrote
# against.
#
# `cur_spawn_delay` is how the tick is recognised. Vanilla sets it back to 0 in the branch that
# spawns and nowhere else, so reading 0 after the super call means that branch just ran; on the
# two frames in three where it did not, this costs one integer comparison. The `_cleaning_up`
# guard is vanilla's own and has to be repeated, because that path returns before the counter is
# touched and would otherwise leave a stale 0 to spawn into a room being torn down.
func _physics_process(delta: float) -> void:
	._physics_process(delta)

	if _cleaning_up or cur_spawn_delay != 0 or queue_to_spawn.empty():
		return

	var tweaks = _tweaks()
	if tweaks == null:
		return

	for _i in tweaks.enemy_spawn_extra(queue_to_spawn.size()):
		spawn(queue_to_spawn)


# The zone's own horde groups — what `WaveManager.init()` pushes in on a scheduled horde wave.
# Empty on a wave that is already a horde: doubling the one wave the game meant to be a horde is
# not what "horde every wave" asks for.
func _tweaks_horde_groups() -> Array:
	if RunData.is_elite_wave(EliteType.HORDE):
		return []
	if not ZoneService.has_method("get_zone_data"):
		return []

	var zone = ZoneService.get_zone_data(RunData.current_zone)
	if zone == null or not ("horde_groups" in zone) or not (zone.horde_groups is Array):
		return []
	return zone.horde_groups


# All Cursed, the enemy half.
#
# `enemy_respawned` is emitted from `spawn_entity()` for `EntityType.ENEMY` only — never for a
# boss — and it is the same signal the DLC rolls its own curse chance on. Listening rather than
# overriding `spawn_entity()` keeps this off the hottest method in the spawner and puts it exactly
# where vanilla makes the same decision.
#
# Order matters and is not luck: `Main._ready()` mounts the DLC's scene effect behaviours (whose
# `_ready()` connects them) before it calls `EntitySpawner.init()`, so the DLC's listener always
# runs first and an enemy it just cursed reaches this one already cursed.
# The chance is asked for first, and it is the whole cost of this being connected while the tweak
# is off: one cached node lookup and one dictionary read per spawn, and none of the work below.
func _tweaks_on_enemy_respawned(enemy) -> void:
	var tweaks = _tweaks()
	if tweaks == null or tweaks.cursed_enemy_chance() <= 0.0:
		return
	tweaks.curse_enemy(enemy, _tweaks_curse_behavior(), _tweaks_curse_value())


# The DLC's CurseSceneEffectBehavior, or null when Abyssal Terrors is not active.
#
# It is found through this node's own connection list rather than by node path: it is a child of a
# node in `main.tscn` this mod would otherwise have to know the shape of, and the one thing that is
# certain about it is that it is connected to this signal. Anything else connected here — vanilla's
# `Main._on_EntitySpawner_enemy_respawned`, this file's own listener — has no `_curse_enemy`.
func _tweaks_curse_behavior():
	if _tweaks_curse_source != null and is_instance_valid(_tweaks_curse_source):
		return _tweaks_curse_source

	for connection in get_signal_connection_list("enemy_respawned"):
		var target = connection.get("target")
		if target == null or not is_instance_valid(target):
			continue
		if target.has_method("_curse_enemy"):
			_tweaks_curse_source = target
			return target
	return null


# The players' summed Curse stat, which is what the DLC scales a cursed enemy's health boost by.
# Read the same way `CurseSceneEffectBehavior` reads it, so a curse made here is worth the same as
# one the DLC made itself.
func _tweaks_curse_value() -> float:
	var total := 0.0
	for player_index in RunData.get_player_count():
		total += max(0.0, Utils.get_max_capped_stat(Keys.stat_curse_hash, player_index))
	return total


# Kept once found: `_tweaks_on_enemy_respawned()` asks per enemy spawn, and a group lookup walks
# the tree.
func _tweaks():
	_tweaks_node = TweaksLookup.cached(self, _tweaks_node)
	return _tweaks_node
