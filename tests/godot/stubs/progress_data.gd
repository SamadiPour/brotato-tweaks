extends Node

# Stands in for the ProgressData autoload. core/curse.gd asks it two questions, and the default
# answers are the ones the mod has to survive: the DLC is not there, so All Cursed does nothing.

var dlc_available := false
var dlc = null


func is_dlc_available_and_active(_dlc_id: String) -> bool:
	return dlc_available


func get_dlc_data(_dlc_id: String):
	return dlc
