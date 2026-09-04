extends Reference

# Pure: turns the manifest's config schema plus the current settings into the rows a settings
# screen draws, and formats one number the way it was set. Names no game class and touches no
# node, so tests/run.sh drives all of it.
#
# Three things live here rather than in the screen, because none of them can be expressed in a
# JSON schema:
#
#   * grouping and order — the schema is an unordered object;
#   * which rows are sub-options of which toggle, which is what lets the screen hide a dial whose
#     feature is off instead of showing eight dead widgets;
#   * how a number reads. "2.0x", "40%" and "11" are all floats, and only one rendering of each is
#     the number the player set.
#
# A key the schema declares and no section claims is still drawn, in a trailing section. So a
# setting added to manifest.json and forgotten here stays reachable; only its placement is lost.
#
# `out_of_range()` is the same schema read for a different question — which saved numbers it no
# longer allows — and it is here because it is the same pure "schema plus settings" shape and
# nothing else in core/ knows what a schema is.

# Order on screen. A key listed here that the schema does not declare is skipped.
#
# A section is a part of the game, not a feature: "Enemies" is everything that changes what you
# fight, whether that is how many of them there are or how hard they hit. One heading per feature
# gave thirteen headings for fifteen tweaks, which is a list with rules drawn through it rather
# than a grouping. Features stay whole and in order inside a section, and the screen sets a
# feature's dials in under the switch that owns them, so the block is still readable without a
# heading of its own.
const SECTIONS := [
	{
		# How many enemies arrive, and what each one is worth fighting.
		"title": "Enemies",
		"entries": [
			"enemies_enabled",
			"enemies_multiplier",
			"enemies_raise_cap",
			"enemies_fast_spawn",
			"enemy_stats_enabled",
			"enemy_health_multiplier",
			"enemy_damage_multiplier",
			"enemy_speed_multiplier",
		],
	},
	{
		# What a wave is made of and how long it runs. Bonus elites and bosses are here rather than
		# with the elite schedule they read like, because they are not a schedule: they are in
		# every wave from wave 1 and the schedule does not reach them.
		"title": "Waves",
		"entries": [
			"horde_every_wave_enabled",
			"wave_duration_enabled",
			"wave_duration_multiplier",
			"elites_enabled",
			"elites_first_wave",
			"elites_horde_chance",
			"bonus_elites_enabled",
			"bonus_elites_count",
			"bonus_bosses_enabled",
			"bonus_bosses_count",
		],
	},
	{
		# What you are offered, what you may keep, and what the shop lets you do about it. The
		# weapon limit is here and not under the run, because it is a rule about what you hold.
		"title": "Items and shop",
		"entries": [
			"unlimited_items_enabled",
			"unlimited_uniques_enabled",
			"bans_enabled",
			"bans_max",
			"bans_weapons",
			"recycle_items_enabled",
			"weapon_limit_enabled",
			"weapon_limit",
		],
	},
	{
		# Kept out of "Items and shop" even though most of it is items: all of it needs the Abyssal
		# Terrors DLC, and a player without the DLC should be able to skip one heading rather than
		# read past dead switches scattered through another section.
		#
		# Not "All Cursed": Recurse sits here because it is a curse tweak, but it is its own switch
		# and works whether or not All Cursed is on, so a header naming one of the two would read as
		# if the other needed it.
		"title": "Curses",
		"entries": [
			"cursed_enabled",
			"cursed_items",
			"cursed_weapons",
			"cursed_enemy_chance",
			"recurse_enabled",
		],
	},
	{
		# Rules about the run itself rather than about a wave in it: what happens when you die, and
		# what the game stops doing for you past wave 20.
		"title": "Run rules",
		"entries": [
			"death_guard_enabled",
			"endless_harvesting_enabled",
			"endless_piggy_bank_enabled",
		],
	},
	{
		# The mod's own switches. Nothing here changes a run.
		"title": "Debug",
		"entries": ["verbose_log"],
	},
]

# Sub-option -> the toggle that switches its feature on. A row with a parent is drawn indented and
# is hidden while that toggle is off.
const PARENTS := {
	"enemies_multiplier": "enemies_enabled",
	"enemies_raise_cap": "enemies_enabled",
	"enemies_fast_spawn": "enemies_enabled",
	"enemy_health_multiplier": "enemy_stats_enabled",
	"enemy_damage_multiplier": "enemy_stats_enabled",
	"enemy_speed_multiplier": "enemy_stats_enabled",
	"wave_duration_multiplier": "wave_duration_enabled",
	"elites_first_wave": "elites_enabled",
	"elites_horde_chance": "elites_enabled",
	"bonus_elites_count": "bonus_elites_enabled",
	"bonus_bosses_count": "bonus_bosses_enabled",
	"cursed_items": "cursed_enabled",
	"cursed_weapons": "cursed_enabled",
	"cursed_enemy_chance": "cursed_enabled",
	"bans_max": "bans_enabled",
	"bans_weapons": "bans_enabled",
	"weapon_limit": "weapon_limit_enabled",
}

# How each number is written next to its slider. A key with no entry is printed as-is.
const FORMATS := {
	"enemies_multiplier": "%.1fx",
	"enemy_health_multiplier": "%.1fx",
	"enemy_damage_multiplier": "%.1fx",
	"enemy_speed_multiplier": "%.1fx",
	"wave_duration_multiplier": "%.2fx",
	"elites_first_wave": "%d",
	"elites_horde_chance": "%d%%",
	"bonus_elites_count": "%d",
	"bonus_bosses_count": "%d",
	"cursed_enemy_chance": "%d%%",
	"bans_max": "%d",
	"weapon_limit": "%d",
}

# Where a schema key no section claims ends up.
const UNCLAIMED_TITLE := "More"


# `properties` is the schema's `properties` object; `settings` is what the player currently has.
# Returns [{title, rows}], each row a dictionary the screen can draw without asking anything else.
static func build(properties: Dictionary, settings: Dictionary) -> Array:
	var sections := []
	var claimed := {}

	for section in SECTIONS:
		var rows := []
		for key in section["entries"]:
			if not properties.has(key):
				continue
			claimed[key] = true
			var row := _row(str(key), properties[key], settings)
			if not row.empty():
				rows.append(row)
		if not rows.empty():
			sections.append({"title": str(section["title"]), "rows": rows})

	var unclaimed := []
	for key in properties.keys():
		if claimed.has(key):
			continue
		var row := _row(str(key), properties[key], settings)
		if not row.empty():
			unclaimed.append(row)
	if not unclaimed.empty():
		sections.append({"title": UNCLAIMED_TITLE, "rows": unclaimed})

	return sections


# Whether a row belongs on screen right now. A row with no parent is always shown; a sub-option is
# shown only while the toggle it belongs to is on.
static func row_visible(row: Dictionary, settings: Dictionary) -> bool:
	var parent := str(row.get("parent", ""))
	if parent == "":
		return true
	return bool(settings.get(parent, false))


# Every number in `settings` that the schema no longer allows, as [{key, value, clamped}] in no
# particular order. Empty when the file agrees with the schema, which is the normal case.
#
# This exists because ModLoader validates the *whole* config on every save: one number left over
# from a version whose range was wider makes `update_config()` reject the file, and then nothing
# the player changes is ever written. `enemy_damage_multiplier` is the case that produced it — it
# was once allowed to be 0, and 0 is now below its minimum.
#
# Only `minimum` and `maximum` are checked. `multipleOf` is the validator's other rule, and a value
# off the step can only have come from a hand-edited file, where rounding it would throw away a
# choice someone made on purpose.
static func out_of_range(properties: Dictionary, settings: Dictionary) -> Array:
	var found := []

	for key in properties.keys():
		var property = properties[key]
		if not (property is Dictionary) or str(property.get("type", "")) != "number":
			continue
		if not settings.has(key):
			continue
		var value = settings[key]
		if not (value is int or value is float):
			continue

		var number := float(value)
		var clamped := clamp(
			number,
			float(property.get("minimum", number)),
			float(property.get("maximum", number))
		)
		if clamped != number:
			found.append({"key": str(key), "value": number, "clamped": clamped})

	return found


static func format_value(key: String, value: float) -> String:
	if not FORMATS.has(key):
		return str(value)
	return str(FORMATS[key]) % value


# {} for anything the screen has no widget for — a string, an enum, a nested object. Skipping it
# here is what keeps the screen from having to know the schema's whole vocabulary.
static func _row(key: String, property, settings: Dictionary) -> Dictionary:
	if not (property is Dictionary):
		return {}

	var type := str(property.get("type", ""))
	if type != "boolean" and type != "number":
		return {}

	var value = settings.get(key, property.get("default", 0))
	var row := {
		"key": key,
		"kind": "bool" if type == "boolean" else "number",
		"title": str(property.get("title", key)),
		"description": str(property.get("description", "")),
		"parent": str(PARENTS.get(key, "")),
	}

	if row.kind == "bool":
		row["value"] = bool(value)
		return row

	row["value"] = float(value)
	row["minimum"] = float(property.get("minimum", 0.0))
	row["maximum"] = float(property.get("maximum", 1.0))
	# `multipleOf` and not `step`: it is what the schema validator ModLoader runs on every save
	# reads, so it is the one number that is certain to agree with what will actually save.
	row["step"] = float(property.get("multipleOf", 1.0))
	row["text"] = format_value(key, row.value)
	return row
