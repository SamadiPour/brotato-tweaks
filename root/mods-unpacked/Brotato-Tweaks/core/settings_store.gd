extends Node

# Where the settings live, and everything it takes to keep them on disk.
#
# `tweaks.gd` answers the adapters' questions; this answers "what is the value of X", and owns the
# whole of the ModLoader side: which config file is read, why it is not the obvious one, how a save
# is debounced, what happens to a key an older version wrote, and the bridge to Brotato Mod Options.
# None of that is a decision about the game, so none of it belongs next to the tweaks.
#
# Mounted as a child of `Tweaks`, which calls `mount()` once it is in the tree — the timers below
# need a tree, and so does waiting for Mod Options.
#
# Two signals out, and the difference between them is the debounce:
#
#   changed(settings)     a value moved. Emitted at once, on every route, so a screen already open
#                         follows an edit it did not make itself.
#   persisted(settings)   the change reached disk, or arrived from ModLoader already saved. At most
#                         one per debounce window, which is what makes it the right place to log a
#                         summary rather than one line per slider step.
#
# See docs/01-architecture.md.

const MOD_ID := "Brotato-Tweaks"

# ModLoader regenerates the "default" config from the manifest schema on effectively every boot, so
# nothing saved or hand-edited there survives a restart. The mod creates its own named config on
# first run and reads that instead — see _ensure_user_config() and _load_settings().
const USER_CONFIG_NAME := "user"

# Brotato Mod Options draws a settings screen from the schema, but it never writes what the player
# changes back: `ModsConfigInterface.on_setting_changed()` updates its own in-memory copy, emits
# `setting_changed`, and stops there — the write-back is still a `TODO` in its source. So a mod
# that only listens for `ModLoader.current_config_changed` hears nothing from that screen, and every
# edit is lost when the menu closes.
#
# The bridge below listens for its signal instead and does the saving itself. Mod Options is a
# separate, optional mod that loads after this one, so the node is looked up once and then waited
# for; if it is not installed the wait costs one comparison per node added and nothing else.
const MOD_OPTIONS_PATH := "/root/ModLoader/dami-ModOptions/ModsConfigInterface"
const MOD_OPTIONS_NODE := "ModsConfigInterface"

# A slider drag emits a value per step, and each one would otherwise be a file write.
const SAVE_DEBOUNCE_SECONDS := 0.4

# How long to keep watching for Mod Options before deciding it is not installed.
const MOD_OPTIONS_WAIT_SECONDS := 10.0

const Logger := preload("logger.gd")
const SettingsLayout := preload("settings_layout.gd")

signal changed(settings)
signal persisted(settings)

var settings := {}

# The ModConfig the settings were read from, so _ensure_user_config() does not ask again.
var _loaded_config = null

# Mod Options' ModsConfigInterface, once it exists. Null means "not installed, or not loaded yet".
var _mod_options = null

var _save_timer: Timer = null


# Called by `Tweaks` once this node is in the tree. Not `_ready()`, so the order of what follows is
# stated here rather than left to when the parent happened to add the child.
func mount() -> void:
	_load_settings()
	_ensure_user_config()
	_connect_config_signal()
	_start_save_timer()
	_connect_mod_options()


func get_setting(key: String, default = null):
	if settings.has(key) and settings[key] != null:
		return settings[key]
	return default


# Every route a setting can change by ends here: the mod's own tab, and Brotato Mod Options.
# Saving is debounced because a slider drag emits a value per step, and `changed` goes out at once
# so anything already on screen follows a change it did not make itself.
#
# Only keys the schema declared are accepted. Anything else is another mod's business, or a key
# this version does not know — `_fill_missing_keys()` has already put every schema key in here.
func set_setting(key: String, value) -> void:
	if not settings.has(key):
		return
	if settings[key] == value:
		return

	settings[key] = value
	_queue_save()
	emit_signal("changed", settings)


# Back to the schema defaults, saved immediately: this is one deliberate press, not a drag. False
# means nothing was done, so the caller does not announce a reset that did not happen.
func reset_to_defaults() -> bool:
	var defaults = ModLoaderConfig.get_default_config(MOD_ID)
	if defaults == null or not (defaults.data is Dictionary):
		Logger.warning("could not reset - the default config is missing")
		return false

	settings = defaults.data.duplicate(true)
	_persist_settings()
	emit_signal("changed", settings)
	return true


# The schema's `properties` object — what the settings tab draws itself from, so the manifest stays
# the one place a setting is declared. The default config is preferred over the loaded one because
# ModLoader regenerates it from the manifest on every boot, which makes it the newer of the two
# whenever the mod has been updated under an existing `user.json`.
func get_schema_properties() -> Dictionary:
	var schema := _schema()
	var properties = schema.get("properties", {})
	return properties if properties is Dictionary else {}


func schema_description() -> String:
	return str(_schema().get("description", ""))


func _schema() -> Dictionary:
	var config = ModLoaderConfig.get_default_config(MOD_ID)
	if config == null and _loaded_config != null:
		config = _loaded_config
	if config == null or not ("schema" in config) or not (config.schema is Dictionary):
		return {}
	return config.schema


# Saves into the mod's own named config, creating it the first time. Writing into the "default"
# config would look like it worked: ModLoader regenerates that file from the manifest schema on
# the next boot and the setting would be gone.
func _persist_settings() -> void:
	var config = ModLoaderConfig.get_current_config(MOD_ID)
	if config != null and str(config.name) != ModLoaderConfig.DEFAULT_CONFIG_NAME:
		config.data = settings.duplicate(true)
		_update_config(config)
		return

	var existing = ModLoaderConfig.get_configs(MOD_ID)
	if existing.has(USER_CONFIG_NAME):
		var user_config = existing[USER_CONFIG_NAME]
		user_config.data = settings.duplicate(true)
		_update_config(user_config)
		ModLoaderConfig.set_current_config(user_config)
		return

	var created = ModLoaderConfig.create_config(MOD_ID, USER_CONFIG_NAME, settings.duplicate(true))
	if created == null:
		Logger.warning("could not save settings - the '%s' config was rejected" % USER_CONFIG_NAME)
		return
	ModLoaderConfig.set_current_config(created)


# `update_config()` validates against the schema and returns null without saving when a value does
# not fit — a number outside its range, or with more than three decimal places. That is silent
# apart from ModLoader's own log line, and a setting that will not save is exactly the bug this
# whole path exists to fix, so it is said here in the mod's own voice.
func _update_config(config) -> void:
	if ModLoaderConfig.update_config(config) == null:
		Logger.warning("could not save settings - %s.json was rejected by the schema" % USER_CONFIG_NAME)


func _load_settings() -> void:
	# Three sources, in order of how much they can be trusted to be the player's own choice.
	#
	# 1. Whatever the user profile says is current — what Brotato Mod Options writes through.
	#    `get_current_config()` answers entirely from `mod_user_profiles.json`, and a profile
	#    written while the mod was not yet valid carries no entry for it, in which case this is
	#    null no matter what is on disk.
	# 2. The mod's own `user.json`. ModLoader loads every file in the config directory at boot, so
	#    it is in `get_configs()` whether or not the profile remembers it — which is what makes a
	#    hand-edited file work.
	# 3. The schema defaults, so the mod runs with settings rather than with none.
	var config = ModLoaderConfig.get_current_config(MOD_ID)
	if config == null or str(config.name) == ModLoaderConfig.DEFAULT_CONFIG_NAME:
		var existing = ModLoaderConfig.get_configs(MOD_ID)
		if existing.has(USER_CONFIG_NAME):
			config = existing[USER_CONFIG_NAME]

	if config == null:
		config = ModLoaderConfig.get_default_config(MOD_ID)

	if config == null or not (config.data is Dictionary):
		Logger.warning("no config found - every tweak stays off")
		settings = {}
		_loaded_config = null
		return

	settings = config.data.duplicate(true)
	_loaded_config = config
	_fill_missing_keys()


# A `user.json` written by an older version has no entry for a setting added since. `get_setting()`
# would cover that on its own, but Brotato Mod Options builds its widgets straight off the schema
# and reads `config.data[key]` for every property in it, so a missing key is an index error on its
# settings screen rather than a default. The gaps are filled from the schema defaults instead.
#
# The reverse case — a key an older version wrote and the schema no longer declares — is dropped,
# so a removed setting does not sit in the file forever being written back on every save.
# `default.json` is the schema's own shape, regenerated from the manifest on every boot, so it is
# the list of keys that still exist.
#
# A third case, and the one that is silent without this: a value an older version allowed and the
# schema has since narrowed — `enemy_damage_multiplier` was once allowed to be 0. ModLoader
# validates the whole config on every save, so one out-of-range number left in the file makes
# `update_config()` reject *every* later save, and nothing the player changes is kept. Numbers are
# clamped back into range here instead, once, on load.
func _fill_missing_keys() -> void:
	var defaults = ModLoaderConfig.get_default_config(MOD_ID)
	if defaults == null or not (defaults.data is Dictionary):
		return

	var changed := false
	for key in defaults.data.keys():
		if not settings.has(key):
			settings[key] = defaults.data[key]
			changed = true

	for key in settings.keys():
		if not defaults.data.has(key):
			settings.erase(key)
			changed = true

	if _clamp_numbers_to_schema():
		changed = true

	if changed:
		_persist_settings()


# Returns whether anything moved. Which numbers are out of range is SettingsLayout's to decide;
# this applies the answer and says so.
func _clamp_numbers_to_schema() -> bool:
	var adjustments := SettingsLayout.out_of_range(get_schema_properties(), settings)

	for adjustment in adjustments:
		settings[adjustment.key] = adjustment.clamped
		Logger.warning("'%s' was %s, which this version no longer allows - using %s" % [
			str(adjustment.key), str(adjustment.value), str(adjustment.clamped),
		])

	return not adjustments.empty()


# Gives the player a settings file that survives a restart, on the first launch after install.
#
# `default.json` is not one. `ModManifest.load_mod_config_defaults()` regenerates it from the
# manifest schema and saves it on every boot — its guard reads
# `if not current_schema_md5 == cache_schema_md5 or not cache_schema_md5.empty()`, and the second
# clause is true whenever the cache is populated, so the regeneration path is effectively
# unconditional. Anything hand-edited into it is gone on the next launch.
#
# So the mod creates its own named config, seeded with the schema defaults, and makes it current.
# After one launch there is a `user.json` that both Brotato Mod Options and a text editor can
# change and the loader will not overwrite.
func _ensure_user_config() -> void:
	if settings.empty():
		return

	# `_load_settings()` already preferred `user.json` over the default, so anything but the
	# default here means the file exists and is in use.
	var config = _loaded_config
	if config != null and str(config.name) != ModLoaderConfig.DEFAULT_CONFIG_NAME:
		_make_current(config)
		return

	var created = ModLoaderConfig.create_config(MOD_ID, USER_CONFIG_NAME, settings.duplicate(true))
	if created == null:
		Logger.warning("could not create the '%s' config - settings will not survive a restart" % USER_CONFIG_NAME)
		return
	_make_current(created)
	_loaded_config = created
	Logger.info("created configs/%s/%s.json - edit that one, not default.json" % [MOD_ID, USER_CONFIG_NAME])


# Makes the config the profile's current one, so Brotato Mod Options edits this file rather than
# the one the loader regenerates.
#
# `ModLoaderConfig.set_current_config()` looks like a plain assignment into ModLoaderStore, but
# `ModData.current_config` has a setter that writes through to `mod_user_profiles.json` — and that
# setter reads `ModLoaderStore.current_user_profile.name` with no null check, so calling it without
# a profile is an engine error rather than a no-op. Skipping it costs nothing: `_load_settings()`
# finds `user.json` by name whether or not the profile remembers it.
func _make_current(config) -> void:
	if ModLoaderStore.current_user_profile == null:
		return
	ModLoaderConfig.set_current_config(config)


func _connect_config_signal() -> void:
	if ModLoader.has_signal("current_config_changed"):
		ModLoader.connect("current_config_changed", self, "_on_current_config_changed")


# --- Brotato Mod Options ---------------------------------------------------------------

# Mod Options mounts its ModsConfigInterface from its own `mod_main._ready()`. That is a different
# mod, and load order is the player's to change, so the node may or may not be there by the time
# this runs. Either it is found now, or `node_added` finds it the moment it appears.
func _connect_mod_options() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var interface = get_node_or_null(MOD_OPTIONS_PATH)
	if interface != null:
		_bind_mod_options(interface)
		return
	if not tree.is_connected("node_added", self, "_on_node_added"):
		tree.connect("node_added", self, "_on_node_added")

	# `node_added` fires for every node the game ever adds, so the wait is given a deadline: Mod
	# Options mounts its interface from ModLoader's own boot, and anything that has not appeared by
	# the title screen is not going to. Without this a player who does not have it installed keeps a
	# callback on the busiest signal in the engine for the whole session.
	var give_up := Timer.new()
	give_up.name = "ModOptionsWait"
	give_up.one_shot = true
	give_up.wait_time = MOD_OPTIONS_WAIT_SECONDS
	give_up.pause_mode = Node.PAUSE_MODE_PROCESS
	give_up.connect("timeout", self, "_on_mod_options_wait_timeout")
	add_child(give_up)
	give_up.start()


func _on_mod_options_wait_timeout() -> void:
	var tree := get_tree()
	if tree != null and tree.is_connected("node_added", self, "_on_node_added"):
		tree.disconnect("node_added", self, "_on_node_added")


func _on_node_added(node: Node) -> void:
	if node == null or node.name != MOD_OPTIONS_NODE:
		return
	_bind_mod_options(node)


func _bind_mod_options(interface) -> void:
	if _mod_options != null:
		return
	if not interface.has_signal("setting_changed"):
		return
	if interface.connect("setting_changed", self, "_on_mod_options_setting_changed") != OK:
		return

	_mod_options = interface
	var tree := get_tree()
	if tree != null and tree.is_connected("node_added", self, "_on_node_added"):
		tree.disconnect("node_added", self, "_on_node_added")
	Logger.info("Brotato Mod Options found - its edits are saved to %s.json" % USER_CONFIG_NAME)


# One widget on the Mod Options screen changed. It passes the schema key it built the widget from,
# so this is `set_setting()` with the mod id checked first.
func _on_mod_options_setting_changed(setting_name: String, value, mod_name: String) -> void:
	if str(mod_name) != MOD_ID:
		return
	set_setting(setting_name, value)


func _start_save_timer() -> void:
	_save_timer = Timer.new()
	_save_timer.name = "SaveDebounce"
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DEBOUNCE_SECONDS
	# The options screen is reached from the pause menu, where the tree is paused and an inheriting
	# timer would never fire.
	_save_timer.pause_mode = Node.PAUSE_MODE_PROCESS
	_save_timer.connect("timeout", self, "_on_save_timer_timeout")
	add_child(_save_timer)


func _queue_save() -> void:
	if _save_timer == null:
		_persist_settings()
		emit_signal("persisted", settings)
		return
	_save_timer.start(SAVE_DEBOUNCE_SECONDS)


func _on_save_timer_timeout() -> void:
	_persist_settings()
	emit_signal("persisted", settings)


# ModLoader saved a config for this mod from somewhere other than `set_setting()`. It is already on
# disk, so there is nothing to queue — only the new values to take and to pass on.
func _on_current_config_changed(config) -> void:
	if config == null or str(config.mod_id) != MOD_ID:
		return
	settings = config.data.duplicate(true)
	emit_signal("changed", settings)
	emit_signal("persisted", settings)
