extends Reference

# Builders for the WaveData / WaveGroupData / WaveUnitData stand-ins.
#
# The three stubs are separate Resource scripts with exported fields because the real ones are,
# and the scaling depends on `Resource.duplicate()` carrying those fields — that is how it avoids
# editing a group several waves share. See stubs/fake_wave_data.gd.

const FakeWaveData := preload("fake_wave_data.gd")
const FakeGroupData := preload("fake_group_data.gd")
const FakeUnitData := preload("fake_unit_data.gd")


static func unit(type: int, min_number: int, max_number: int) -> Resource:
	var u = FakeUnitData.new()
	u.type = type
	u.min_number = min_number
	u.max_number = max_number
	return u


static func group(units: Array, flags := {}) -> Resource:
	var g = FakeGroupData.new()
	# Copied: GDScript folds a constant `[]` literal into a shared instance, so two builder calls
	# in the same script can otherwise hand back the same array.
	g.wave_units_data = units.duplicate()
	g.is_boss = flags.get("is_boss", false)
	g.is_loot = flags.get("is_loot", false)
	g.is_neutral = flags.get("is_neutral", false)
	g.min_wave = flags.get("min_wave", 0)
	g.max_wave = flags.get("max_wave", 9999)
	return g


static func wave(groups: Array, max_enemies := 100, wave_duration := 60) -> Resource:
	var w = FakeWaveData.new()
	w.groups_data = groups.duplicate()
	w.max_enemies = max_enemies
	w.wave_duration = wave_duration
	return w
