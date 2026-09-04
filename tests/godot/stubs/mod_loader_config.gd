class_name ModLoaderConfig
extends Object

# A `class_name` static class in the game, not an autoload — see stubs/mod_loader_log.gd.
# Every call answers "nothing configured", which is the case the mod has to survive: no
# config, no saved build, no guidance, no errors.

const DEFAULT_CONFIG_NAME := "default"

static func get_current_config(_id: String): return null
static func get_default_config(_id: String): return null
static func get_configs(_id: String) -> Dictionary: return {}
static func create_config(_id: String, _name: String, _data: Dictionary): return null
static func set_current_config(_c) -> void: pass
static func update_config(_c) -> void: pass
