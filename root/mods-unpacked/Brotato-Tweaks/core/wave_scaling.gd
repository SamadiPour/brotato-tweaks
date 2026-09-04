extends Reference

# The enemy multiplier, as a pure transform over one wave's spawn plan.
#
# Nothing here touches a node, a singleton or the tree, so it can be exercised headless with
# hand-written fakes — see tests/godot/core_test.gd.
#
# The plan being transformed is the `WaveData` that `main.gd` handed to both `WaveManager` and
# `EntitySpawner`. It has two levers, and the multiplier has to pull both:
#
#   1. `WaveData.max_enemies` — a performance cap, not a design one. Once more than this many
#      enemies are alive, `EntitySpawner.on_group_spawn_timing_reached()` picks live enemies at
#      random and kills them (`can_drop_loot = false`, so they are erased, not farmed). Spawning
#      three times as many enemies into an unchanged cap gets you the same crowd plus a lot of
#      deleted ones, which is why "bypass the enemy limit" is half of this feature and not a
#      separate setting.
#   2. `WaveGroupData.wave_units_data[n].min_number` / `.max_number` — the count each spawn group
#      rolls between. Scaling these is what actually produces more enemies.
#
# Two rules about *which* groups are scaled, both copied from vanilla's own condition in
# `on_group_spawn_timing_reached()` (`type == ENEMY and not group_data.is_loot`):
#
#   - only units whose `type` is ENEMY. Bosses and elites arrive as BOSS units in `is_boss`
#     groups, and multiplying those is a different feature with a different failure mode.
#   - never a loot group and never a neutral one. Loot aliens are free items and trees are free
#     materials; tripling them would quietly turn an enemy multiplier into an economy mod.
#
# Groups are replaced rather than edited. `ZoneService.get_wave_data()` duplicates the wave and
# its group array, but several groups inside it are *not* duplicates: the conditional groups,
# the horde groups and the DLC's `groups_in_all_zones` are pushed in by reference straight from
# resources that live for the whole session. Editing one in place would compound the multiplier
# on every later wave and survive turning the setting off. So each group this touches is
# duplicated, its units are duplicated, and the copy takes the slot in the array.

const MIN_MULTIPLIER := 1.0
const MAX_MULTIPLIER := 20.0

# A wave shorter than this is not a wave, and the spawn timings inside a group are absolute
# seconds — several vanilla groups do not start until 30 or 40 seconds in.
const MIN_DURATION := 10
const MAX_DURATION := 600


# `enemy_type` is the caller's `EntityType.ENEMY`. It is passed in rather than hard-coded so the
# enum stays the game's to define and the core stays free of vanilla globals.
static func scale(wave_data, multiplier: float, raise_cap: bool, enemy_type: int) -> Dictionary:
	var result := {
		"ok": false,
		"reason": "",
		"groups_scaled": 0,
		"units_scaled": 0,
		"cap_before": 0,
		"cap_after": 0,
	}

	if wave_data == null:
		result.reason = "no wave data"
		return result

	var factor := clamp(multiplier, MIN_MULTIPLIER, MAX_MULTIPLIER)
	if factor <= 1.0:
		result.ok = true
		result.reason = "multiplier is 1"
		return result

	if raise_cap:
		if not ("max_enemies" in wave_data):
			result.reason = "WaveData has no max_enemies"
			return result
		result.cap_before = int(wave_data.max_enemies)
		wave_data.max_enemies = int(round(result.cap_before * factor))
		result.cap_after = int(wave_data.max_enemies)

	if not ("groups_data" in wave_data) or not (wave_data.groups_data is Array):
		result.reason = "WaveData has no groups_data array"
		return result

	var groups: Array = wave_data.groups_data
	for i in groups.size():
		var scaled := _scale_group(groups[i], factor, enemy_type)
		if scaled.empty():
			continue
		groups[i] = scaled.group
		result.groups_scaled += 1
		result.units_scaled += scaled.units

	result.ok = true
	return result


# Wave length. A separate seam from everything else here: `main.gd` reads `wave_duration` at line
# 165, long before `EntitySpawner.init()`, so this one is applied from `ZoneService.get_wave_data()`
# — which hands back a fresh `duplicate()`, so the write is per-wave and thrown away with it.
#
# Groups keep their vanilla `spawn_timing`, which is an absolute number of seconds. In a shortened
# wave the late groups simply never come up; in a lengthened one everything has arrived by the
# original duration and the repeating groups carry the rest. Both are the intended shape of the
# knob — rescaling the timings too would change which enemies a wave is made of, not how long it
# lasts.
static func scale_duration(wave_data, multiplier: float) -> Dictionary:
	var result := {"ok": false, "reason": "", "before": 0, "after": 0}

	if wave_data == null:
		result.reason = "no wave data"
		return result
	if not ("wave_duration" in wave_data):
		result.reason = "WaveData has no wave_duration"
		return result

	result.before = int(wave_data.wave_duration)
	if multiplier <= 0.0 or is_equal_approx(multiplier, 1.0):
		result.ok = true
		result.after = result.before
		return result

	wave_data.wave_duration = int(clamp(round(result.before * multiplier), MIN_DURATION, MAX_DURATION))
	result.after = int(wave_data.wave_duration)
	result.ok = true
	return result


# Appends copies of `groups` to the wave, keeping vanilla's own wave-range filter.
#
# Used for "horde every wave": `ZoneData.horde_groups` is what `WaveManager.init()` pushes in on a
# scheduled horde wave, filtered by `RunData.current_wave >= group.min_wave and <= group.max_wave`.
# The same filter is applied here, because those bounds are the zone author saying which hordes
# make sense when.
#
# Copies, for the same reason groups are replaced rather than edited elsewhere in this file: these
# come straight off the zone resource, which lives for the whole session.
static func inject_groups(wave_data, groups: Array, current_wave: int) -> Dictionary:
	var result := {"ok": false, "reason": "", "injected": 0}

	if wave_data == null:
		result.reason = "no wave data"
		return result
	if not ("groups_data" in wave_data) or not (wave_data.groups_data is Array):
		result.reason = "WaveData has no groups_data array"
		return result

	for group in groups:
		if group == null:
			continue
		if ("min_wave" in group) and current_wave < int(group.min_wave):
			continue
		if ("max_wave" in group) and current_wave > int(group.max_wave):
			continue
		wave_data.groups_data.push_back(group.duplicate())
		result.injected += 1

	result.ok = true
	return result


# {} when this group is left alone, else {group: <the replacement>, units: <how many scaled>}.
static func _scale_group(group, factor: float, enemy_type: int) -> Dictionary:
	if group == null:
		return {}
	if _flag(group, "is_boss") or _flag(group, "is_loot") or _flag(group, "is_neutral"):
		return {}
	if not ("wave_units_data" in group):
		return {}

	var units = group.wave_units_data
	if not (units is Array) or units.empty():
		return {}

	var new_units := []
	var scaled_count := 0

	for unit in units:
		var new_unit = _scale_unit(unit, factor, enemy_type)
		if new_unit == null:
			new_units.append(unit)
		else:
			new_units.append(new_unit)
			scaled_count += 1

	if scaled_count == 0:
		return {}

	var new_group = group.duplicate()
	new_group.wave_units_data = new_units
	return {"group": new_group, "units": scaled_count}


# null when this unit is left alone, else a duplicate carrying the scaled counts.
static func _scale_unit(unit, factor: float, enemy_type: int):
	if unit == null:
		return null
	if not ("type" in unit) or int(unit.type) != enemy_type:
		return null
	if not ("min_number" in unit) or not ("max_number" in unit):
		return null

	var new_unit = unit.duplicate()
	# A group that spawns one enemy still spawns at least one, and max never falls below min —
	# `Utils.randi_range(min, max)` in the spawner assumes that ordering.
	new_unit.min_number = int(max(1.0, round(float(unit.min_number) * factor)))
	new_unit.max_number = int(max(float(new_unit.min_number), round(float(unit.max_number) * factor)))
	return new_unit


static func _flag(obj, property: String) -> bool:
	return (property in obj) and bool(obj.get(property))
