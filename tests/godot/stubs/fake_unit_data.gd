extends Resource

# Stands in for WaveUnitData (res://zones/wave_unit_data.gd). `type` matches the game's
# EntityType enum: PLAYER, ENEMY, NEUTRAL, STRUCTURE, BOSS, PET.

export (int) var type = 1
export (int) var min_number = 1
export (int) var max_number = 1
