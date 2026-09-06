class_name ModLoaderConfig
extends Object

# A `class_name` static class in the game, not an autoload — see stubs/mod_loader_log.gd.
#
# Left alone, every call answers "nothing configured", which is the case the mod has to survive: no
# config, no saved build, no guidance, no errors. That is what every check outside the settings
# store gets, and `reset()` puts it back.
#
# The settings-store checks drive it instead, because what that module does is decide *which* of
# three sources is the player's own choice and *which* file a save may go to. Neither question has
# an answer a stub that always says null can be wrong about. So the state below stands in for a
# loader that has a default config, a `user.json`, a profile that remembers one, and a schema
# validator that can refuse a save.
#
# The state lives on a `const` Dictionary because a `class_name` static class has nowhere else to
# put it: GDScript 3 has no static variables, and `const` on a Dictionary is a constant *reference*
# to a dictionary that is itself mutable.
#
# Mutable from in here only. `ModLoaderConfig.STATE.current = x` in another script compiles to a
# *set* of `STATE` on the class and fails at runtime with "Invalid set index 'STATE'", which is a
# script error rather than a failed check — it aborts the function it is in and leaves the checks
# after it unrun while everything before them still says ok. Hence the seeders and readers below:
# a caller never touches STATE directly.

const FakeModConfig := preload("fake_mod_config.gd")

const DEFAULT_CONFIG_NAME := "default"

const STATE := {
	# What the three getters answer.
	"current": null,
	"default": null,
	"configs": {},

	# The two ways the real loader refuses. `create_config()` returns null for a name it will not
	# take; `update_config()` returns null when a value does not fit the schema — which is the
	# failure the store's clamping exists to keep out of the file in the first place.
	"create_rejects": false,
	"update_rejects": false,

	# What the store did, in order, for the checks that care that a save went to `user.json`, and
	# that a profile that does not exist was not written to.
	"created": [],
	"updated": [],
	"made_current": [],
}


# --- what the checks drive it with ----------------------------------------------------------

static func reset() -> void:
	STATE.current = null
	STATE.default = null
	STATE.configs = {}
	STATE.create_rejects = false
	STATE.update_rejects = false
	forget_history()


# Builds one the way the loader hands them out, so a check can seed a source without knowing the
# stub's shape.
static func make_config(config_name: String, mod_id: String, data: Dictionary, schema := {}):
	var config = FakeModConfig.new()
	config.name = config_name
	config.mod_id = mod_id
	config.data = data.duplicate(true)
	config.schema = schema
	return config


# `default.json` — the one ModLoader regenerates from the manifest on every boot.
static func seed_default(config) -> void:
	STATE.default = config


# A config file on disk, found by name whether or not the profile remembers it.
static func seed_config(config) -> void:
	STATE.configs[str(config.name)] = config


# What the user profile says is current.
static func seed_current(config) -> void:
	STATE.current = config


static func default_config():
	return STATE.default


static func set_update_rejects(rejects: bool) -> void:
	STATE.update_rejects = rejects


static func set_create_rejects(rejects: bool) -> void:
	STATE.create_rejects = rejects


# --- what the checks read back --------------------------------------------------------------

static func created() -> Array:
	return STATE.created


static func updated() -> Array:
	return STATE.updated


static func made_current() -> Array:
	return STATE.made_current


static func forget_history() -> void:
	STATE.created = []
	STATE.updated = []
	STATE.made_current = []


# --- the loader's own surface ---------------------------------------------------------------

static func get_current_config(_id: String):
	return STATE.current


static func get_default_config(_id: String):
	return STATE.default


static func get_configs(_id: String) -> Dictionary:
	return STATE.configs


static func set_current_config(config) -> void:
	STATE.made_current.append(config)
	STATE.current = config


# Registers the new config as well as returning it: the real one writes the file, and every later
# `get_configs()` finds it.
static func create_config(mod_id: String, config_name: String, data: Dictionary):
	STATE.created.append(config_name)
	if STATE.create_rejects:
		return null
	var config = make_config(config_name, mod_id, data)
	STATE.configs[config_name] = config
	return config


static func update_config(config):
	STATE.updated.append(config)
	if STATE.update_rejects:
		return null
	return config
