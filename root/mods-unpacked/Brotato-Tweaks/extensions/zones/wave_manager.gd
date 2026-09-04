extends "res://zones/wave_manager.gd"

# Adapter: bonus elites and bonus bosses.
#
# `WaveManager.init()` is where vanilla finishes assembling the wave — the zone's always-groups,
# the extra loot aliens, the boss group on the last wave, the scheduled elite or horde, and the
# DLC's `groups_in_all_zones`. Appending after it is what makes these *bonus* ones: whatever the
# wave was already going to spawn is untouched and still there.
#
# Two things this seam gives that no other one does, and they are why the feature lives here
# rather than in the `EntitySpawner.init()` seam the other wave tweaks share:
#
#   * `init_elite_group()` and `create_boss_wave_unit_data()` are vanilla's own builders. An
#     elite is not a scene the mod can name — it is an entry in `ItemService.elites` whose
#     `scene` goes into a `WaveUnitData` of type `EntityType.BOSS`, inside a group flagged
#     `is_boss`. Calling vanilla's builders means the mod never encodes any of that.
#   * `elite_group` is the exported `res://zones/common/elite/group_elite.tres` this node was
#     built with — `spawn_edge_of_map`, `is_boss`, `repeating = -1`. The bonus boss group is a
#     duplicate of it, so it behaves exactly like the group vanilla puts an elite in.
#
# `Main._ready()` calls this before `EntitySpawner.init()`, so the enemy multiplier sees these
# groups too — and skips them, because it only scales `EntityType.ENEMY` units and never an
# `is_boss` group. That is the intended relationship: the multiplier is for crowds, this dial is
# for elites, and neither multiplies the other.
#
# One consequence worth knowing, on the last wave only. `main.gd:510` ends the wave early once
# the last boss dies (`get_nb_bosses_and_elites_alive() <= 1`), and that count includes elites.
# So bonus spawns on the boss wave have to be killed before the wave will end early — which is
# the same rule vanilla applies to its own double boss.
#
# See docs/01-architecture.md ("Extension points").

const TWEAKS_GROUP := "brotato_tweaks"

# The mod's own node, kept once found — `init()` runs once per wave, but the lookup walks the tree.
var _tweaks_node = null


func init(p_wave_timer: Timer, zone_data: ZoneData, wave_data: Resource) -> void:
	.init(p_wave_timer, zone_data, wave_data)

	var tweaks = _tweaks()
	if tweaks == null:
		return
	if wave_data == null or not (wave_data.groups_data is Array):
		return

	_tweaks_add_bonus_elites(tweaks, zone_data, wave_data)
	_tweaks_add_bonus_bosses(tweaks, zone_data, wave_data)


# One group holding every bonus elite, the same shape vanilla builds for a scheduled one.
#
# `add_endless_elites` is false. Vanilla passes true so that a run past wave 20 gets an extra
# elite per ten waves on top of the one it scheduled; letting that apply here would multiply this
# dial by the wave number, which is not what a number the player set to 2 should mean.
func _tweaks_add_bonus_elites(tweaks, zone_data: ZoneData, wave_data: Resource) -> void:
	var wanted: int = tweaks.bonus_elite_count()
	if wanted <= 0:
		return

	var picked: Array = tweaks.pick_bonus(ItemService.get_elites_from_zone(zone_data.my_id), wanted)
	if picked.empty():
		return

	var elite_ids := []
	for elite in picked:
		elite_ids.push_back(elite.my_id_hash)

	wave_data.groups_data.push_back(init_elite_group(elite_ids, false))
	tweaks.report_bonus_spawns("elites", picked.size())


# The zone's own bosses — the same ones the last wave would have brought — in a duplicate of the
# elite group, because that is the group vanilla spawns a `BOSS` unit from anywhere other than the
# wave's own boss group. Nothing is written to `RunData.bosses_spawn`: the last wave's boss is
# vanilla's to choose, and these are additions to it.
func _tweaks_add_bonus_bosses(tweaks, zone_data: ZoneData, wave_data: Resource) -> void:
	var wanted: int = tweaks.bonus_boss_count()
	if wanted <= 0:
		return
	if elite_group == null:
		tweaks.disable_feature("bonus_bosses", "WaveManager has no elite_group to build one from")
		return

	var picked: Array = tweaks.pick_bonus(ItemService.get_bosses_from_zone(zone_data.my_id), wanted)
	if picked.empty():
		return

	var group: WaveGroupData = elite_group.duplicate()
	for boss in picked:
		group.wave_units_data.push_back(create_boss_wave_unit_data(boss.my_id))

	wave_data.groups_data.push_back(group)
	tweaks.report_bonus_spawns("bosses", picked.size())


func _tweaks():
	if _tweaks_node != null and is_instance_valid(_tweaks_node):
		return _tweaks_node
	if not is_inside_tree():
		return null
	var found := get_tree().get_nodes_in_group(TWEAKS_GROUP)
	if found.empty() or not is_instance_valid(found[0]):
		return null
	_tweaks_node = found[0]
	return _tweaks_node
