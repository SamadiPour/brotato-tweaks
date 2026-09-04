extends Resource

# Stands in for WaveGroupData (res://zones/wave_group_data.gd). See stubs/fake_wave_data.gd for
# why these are exported.

export (Array, Resource) var wave_units_data
export (bool) var is_neutral = false
export (bool) var is_boss = false
export (bool) var is_horde = false
export (bool) var is_loot = false
export (int) var min_wave = 0
export (int) var max_wave = 9999
