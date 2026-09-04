extends Node

# Headless checks for the pure cores. None of them touches a node, a singleton or the tree, so all
# of them can be driven with the fakes in stubs/fake_wave.gd.
#
# The vanilla side — that a hooked method still has that name, that signature and that node under
# it — is tests/run_extensions.sh's job, which compiles the adapters against real game source.

const WaveScaling := preload("res://mods-unpacked/Brotato-Tweaks/core/wave_scaling.gd")
const EnemyStats := preload("res://mods-unpacked/Brotato-Tweaks/core/enemy_stats.gd")
const EliteSchedule := preload("res://mods-unpacked/Brotato-Tweaks/core/elite_schedule.gd")
const BonusSpawns := preload("res://mods-unpacked/Brotato-Tweaks/core/bonus_spawns.gd")
const SpawnRate := preload("res://mods-unpacked/Brotato-Tweaks/core/spawn_rate.gd")
const Loadout := preload("res://mods-unpacked/Brotato-Tweaks/core/loadout.gd")
const Recycling := preload("res://mods-unpacked/Brotato-Tweaks/core/recycling.gd")
const ItemLimits := preload("res://mods-unpacked/Brotato-Tweaks/core/item_limits.gd")
const SettingsLayout := preload("res://mods-unpacked/Brotato-Tweaks/core/settings_layout.gd")
const Curse := preload("res://mods-unpacked/Brotato-Tweaks/core/curse.gd")
const Fake := preload("res://stubs/fake_wave.gd")
const FakePlayer := preload("res://stubs/fake_player.gd")

# A stand-in for the manifest's `config_schema.properties`, small enough to reason about and
# deliberately not a copy of the real one: it carries a type the screen has no widget for, and a
# key no section in the layout claims.
const SCHEMA := {
	"enemies_enabled": {"type": "boolean", "title": "Enemy multiplier", "default": false},
	"enemies_multiplier": {
		"type": "number", "title": "Amount", "description": "How many times vanilla.",
		"default": 2, "minimum": 1, "maximum": 10, "multipleOf": 0.5,
	},
	"death_guard_enabled": {"type": "boolean", "title": "Death Guard", "default": false},
	"palette": {"type": "string", "default": "#ffffff"},
	"invented_later": {"type": "boolean", "title": "Invented later", "default": true},
}

const ENEMY := 1
const NEUTRAL := 2
const BOSS := 4

var _failures := 0


func _ready() -> void:
	_wave_scaling_checks()
	_spawn_rate_checks()
	_wave_duration_checks()
	_horde_injection_checks()
	_enemy_stat_checks()
	_elite_schedule_checks()
	_bonus_spawn_checks()
	_weapon_limit_checks()
	_ban_allowance_checks()
	_recycling_checks()
	_item_limit_checks()
	_cursed_enemy_checks()
	_recurse_checks()
	_settings_layout_checks()
	_settings_tab_checks()

	print("---- ", _failures, " check(s) failed")
	if _failures > 0:
		print("CHECK(S) FAILED")
	get_tree().quit(1 if _failures > 0 else 0)


# --- the enemy multiplier ------------------------------------------------------------

func _wave_scaling_checks() -> void:
	var wave = Fake.wave([Fake.group([Fake.unit(ENEMY, 2, 4)])], 100)
	var report := WaveScaling.scale(wave, 3.0, true, ENEMY)
	_check("scales enemy counts", report.ok
		and wave.groups_data[0].wave_units_data[0].min_number == 6
		and wave.groups_data[0].wave_units_data[0].max_number == 12)
	_check("lifts the enemy cap", wave.max_enemies == 300
		and report.cap_before == 100 and report.cap_after == 300)
	_check("reports what it touched", report.groups_scaled == 1 and report.units_scaled == 1)

	# A multiplier of 1 is a no-op that still succeeds: the feature can be on with the dial down.
	var untouched = Fake.wave([Fake.group([Fake.unit(ENEMY, 2, 4)])], 100)
	var flat := WaveScaling.scale(untouched, 1.0, true, ENEMY)
	_check("a multiplier of 1 changes nothing", flat.ok
		and untouched.max_enemies == 100
		and untouched.groups_data[0].wave_units_data[0].min_number == 2)

	# The cap is a separate switch: someone who wants more spawns but keeps vanilla's safety
	# valve gets exactly that.
	var capped = Fake.wave([Fake.group([Fake.unit(ENEMY, 2, 4)])], 100)
	WaveScaling.scale(capped, 3.0, false, ENEMY)
	_check("the cap can be left alone", capped.max_enemies == 100
		and capped.groups_data[0].wave_units_data[0].min_number == 6)

	# Loot aliens are free items and trees are free materials. Multiplying either would turn an
	# enemy multiplier into an economy mod, and bosses and elites are a different feature.
	var loot_group = Fake.group([Fake.unit(ENEMY, 1, 1)], {"is_loot": true})
	var tree_group = Fake.group([Fake.unit(NEUTRAL, 1, 1)], {"is_neutral": true})
	var boss_group = Fake.group([Fake.unit(BOSS, 1, 1)], {"is_boss": true})
	var mixed = Fake.wave([loot_group, tree_group, boss_group], 100)
	var mixed_report := WaveScaling.scale(mixed, 4.0, true, ENEMY)
	_check("leaves loot, trees and bosses alone", mixed_report.groups_scaled == 0
		and mixed.groups_data[0] == loot_group
		and mixed.groups_data[1] == tree_group
		and mixed.groups_data[2] == boss_group)

	# A group of ordinary enemies can still carry a non-enemy unit; only the enemies move.
	var pair = Fake.group([Fake.unit(ENEMY, 1, 2), Fake.unit(NEUTRAL, 5, 5)])
	var pair_wave = Fake.wave([pair], 100)
	WaveScaling.scale(pair_wave, 2.0, true, ENEMY)
	var scaled_pair = pair_wave.groups_data[0]
	_check("scales only the enemy units in a group",
		scaled_pair.wave_units_data[0].min_number == 2
		and scaled_pair.wave_units_data[1].min_number == 5)

	# The one that matters. ZoneService duplicates the wave, but the conditional, horde and DLC
	# groups inside it are pushed in by reference from resources that live for the session.
	# Editing one in place would compound on every later wave and outlive the setting.
	var shared = Fake.group([Fake.unit(ENEMY, 2, 2)])
	var first = Fake.wave([shared], 100)
	WaveScaling.scale(first, 5.0, true, ENEMY)
	_check("never edits a shared group in place",
		shared.wave_units_data[0].min_number == 2
		and first.groups_data[0] != shared
		and first.groups_data[0].wave_units_data[0].min_number == 10)

	# A group that spawns one enemy still spawns one, and max never drops below min: the spawner
	# calls Utils.randi_range(min, max) and assumes that ordering.
	var tiny = Fake.wave([Fake.group([Fake.unit(ENEMY, 1, 1)])], 100)
	WaveScaling.scale(tiny, 1.4, true, ENEMY)
	var tiny_unit = tiny.groups_data[0].wave_units_data[0]
	_check("keeps min >= 1 and max >= min", tiny_unit.min_number >= 1
		and tiny_unit.max_number >= tiny_unit.min_number)

	# Absurd multipliers are clamped rather than honoured, and a wave shaped nothing like the
	# game's reports why instead of throwing.
	var clamped = Fake.wave([Fake.group([Fake.unit(ENEMY, 1, 1)])], 100)
	WaveScaling.scale(clamped, 9999.0, true, ENEMY)
	_check("clamps the multiplier", clamped.max_enemies == 2000)

	var no_wave := WaveScaling.scale(null, 3.0, true, ENEMY)
	_check("survives a missing wave", not no_wave.ok and no_wave.reason != "")

	var bare := WaveScaling.scale(Resource.new(), 3.0, true, ENEMY)
	_check("survives a wave it does not recognise", not bare.ok and bare.reason != "")


# --- the spawn queue's drain rate ----------------------------------------------------

func _spawn_rate_checks() -> void:
	# Vanilla's two pops a tick are already done by the time the adapter asks, so a 3x dial is
	# six a tick and the answer is the four it is short.
	_check("asks for the multiplier's share, less vanilla's",
		SpawnRate.extra_per_tick(500, 3.0, true) == 4)

	# The budget the verbose log prints. Vanilla's own is the answer whenever the tweak adds
	# nothing, so the line never claims a speed-up that is not happening.
	_check("reports the whole tick's budget", SpawnRate.budget_per_tick(3.0, true) == 6)
	_check("reports vanilla's budget when off",
		SpawnRate.budget_per_tick(10.0, false) == SpawnRate.VANILLA_PER_TICK
		and SpawnRate.budget_per_tick(1.0, true) == SpawnRate.VANILLA_PER_TICK)

	# Every reason to do nothing, and each one has to answer 0 rather than a small number: the
	# adapter skips the queue entirely on a 0.
	_check("does nothing while the tweak is off", SpawnRate.extra_per_tick(500, 10.0, false) == 0)
	_check("does nothing at a multiplier of 1", SpawnRate.extra_per_tick(500, 1.0, true) == 0)
	_check("does nothing with an empty queue", SpawnRate.extra_per_tick(0, 10.0, true) == 0)

	# Never more than the queue holds. `EntitySpawner.spawn()` would return early on an empty
	# array, but a count that overstates what was released is still the wrong number.
	_check("never pops more than the queue holds",
		SpawnRate.extra_per_tick(3, 10.0, true) == 3)

	# One tick may not become a frame that instances a thousand enemies, however the config got
	# its number.
	_check("clamps an absurd multiplier",
		SpawnRate.extra_per_tick(10000, 9999.0, true)
		== SpawnRate.MAX_PER_TICK - SpawnRate.VANILLA_PER_TICK)

	# The bounds are the ones core/wave_scaling.gd clamps to. Two halves of one dial that
	# disagreed about what 10 means would be worse than either half alone.
	_check("agrees with the wave scaler about the dial's range",
		SpawnRate.MIN_MULTIPLIER == WaveScaling.MIN_MULTIPLIER
		and SpawnRate.MAX_MULTIPLIER == WaveScaling.MAX_MULTIPLIER)


# --- wave length ---------------------------------------------------------------------

func _wave_duration_checks() -> void:
	var longer = Fake.wave([], 100)
	longer.wave_duration = 60
	var report := WaveScaling.scale_duration(longer, 2.0)
	_check("lengthens a wave", report.ok and longer.wave_duration == 120
		and report.before == 60 and report.after == 120)

	var shorter = Fake.wave([], 100)
	shorter.wave_duration = 60
	WaveScaling.scale_duration(shorter, 0.5)
	_check("shortens a wave", shorter.wave_duration == 30)

	# A wave shorter than the mod's floor is not a wave: several vanilla groups do not start
	# until 30 or 40 seconds in, and the timings are absolute seconds.
	var tiny = Fake.wave([], 100)
	tiny.wave_duration = 20
	WaveScaling.scale_duration(tiny, 0.25)
	_check("never goes below the duration floor", tiny.wave_duration == WaveScaling.MIN_DURATION)

	var same = Fake.wave([], 100)
	same.wave_duration = 60
	var flat := WaveScaling.scale_duration(same, 1.0)
	_check("a multiplier of 1 changes nothing", flat.ok and same.wave_duration == 60)

	var bare := WaveScaling.scale_duration(Resource.new(), 2.0)
	_check("survives a wave with no duration", not bare.ok and bare.reason != "")


# --- horde every wave ----------------------------------------------------------------

func _horde_injection_checks() -> void:
	var horde = Fake.group([Fake.unit(ENEMY, 3, 5)])
	var wave = Fake.wave([Fake.group([Fake.unit(ENEMY, 1, 1)])], 100)
	var report := WaveScaling.inject_groups(wave, [horde], 5)
	_check("adds the horde to the wave", report.ok and report.injected == 1
		and wave.groups_data.size() == 2)

	# Same reason groups are replaced rather than edited: horde groups come straight off the zone
	# resource, which lives for the whole session. The copy has to carry its units — a stub whose
	# fields were not exported dropped them, and only this assertion said so.
	var copy = wave.groups_data[1]
	_check("injects a copy, not the zone's own group", copy != horde)
	_check("the copy keeps its units", copy.wave_units_data.size() == 1
		and copy.wave_units_data[0].min_number == 3)

	# The zone author's own bounds say which hordes make sense when, and vanilla honours them.
	var early = Fake.group([Fake.unit(ENEMY, 1, 1)], {"min_wave": 10})
	var late = Fake.group([Fake.unit(ENEMY, 1, 1)], {"max_wave": 3})
	var filtered = Fake.wave([], 100)
	var filtered_report := WaveScaling.inject_groups(filtered, [early, late], 5)
	_check("honours each group's wave range",
		filtered_report.injected == 0 and filtered.groups_data.empty())

	# Injected hordes are ordinary enemy groups, so the multiplier has to reach them too — the
	# adapter injects before it scales, and this is that contract.
	var combined = Fake.wave([], 100)
	WaveScaling.inject_groups(combined, [Fake.group([Fake.unit(ENEMY, 2, 2)])], 5)
	WaveScaling.scale(combined, 3.0, true, ENEMY)
	_check("an injected horde is multiplied too",
		combined.groups_data[0].wave_units_data[0].min_number == 6)


# --- enemy stat dials ----------------------------------------------------------------

func _enemy_stat_checks() -> void:
	_check("scales a stat", EnemyStats.scale(100.0, 2.5, 1) == 250)
	_check("a multiplier of 1 is identity", EnemyStats.scale(37.0, 1.0, 1) == 37)

	# A zero-health enemy is a dead enemy at spawn, and the spawn path is not built for that.
	_check("health floors at 1", EnemyStats.scale(5.0, 0.0, 1) == 1)

	# Player.get_damage_value() resolves an armoured hit as max(1, ...), so 0 damage is not a thing
	# this seam can produce and the dial floors where the game does.
	_check("damage floors at 1", EnemyStats.scale(20.0, 0.0, 1) == 1)

	# Standing-still enemies are a mode someone will want, and vanilla's own nullify_enemy_speed
	# debug flag already produces exactly that.
	_check("speed may reach 0", EnemyStats.scale(300.0, 0.0, 0) == 0)

	_check("clamps an absurd multiplier",
		EnemyStats.scale(10.0, 9999.0, 1) == int(10.0 * EnemyStats.MAX_MULTIPLIER))
	_check("clamps a negative multiplier", EnemyStats.scale(10.0, -3.0, 1) == 1)


# --- elite schedule ------------------------------------------------------------------

func _elite_schedule_checks() -> void:
	# The vanilla schedule puts the first elite at base_wave + 1, so asking for wave 4 means
	# passing 3.
	var run_start := EliteSchedule.override_args(10, 0.4, 4, 100.0)
	_check("rewrites the run-start call",
		run_start.apply and run_start.base_wave == 3 and is_equal_approx(run_start.horde_chance, 1.0))

	# The one that matters. main.gd's endless top-up passes an absolute wave computed from where
	# the run is now; overriding it would schedule elites at a wave already in the past, and they
	# would never spawn.
	var endless := EliteSchedule.override_args(37, 0.0, 4, 100.0)
	_check("leaves the endless top-up alone",
		not endless.apply and endless.base_wave == 37 and is_equal_approx(endless.horde_chance, 0.0))

	# A call that matches only one default is not the run-start call either.
	var half := EliteSchedule.override_args(10, 0.0, 4, 50.0)
	_check("needs both vanilla defaults to match", not half.apply)

	var clamped := EliteSchedule.override_args(10, 0.4, 9999, 400.0)
	_check("clamps the wave and the chance",
		clamped.base_wave == EliteSchedule.MAX_FIRST_WAVE - 1
		and is_equal_approx(clamped.horde_chance, 1.0))


# --- bonus elites and bosses -----------------------------------------------------------

func _bonus_spawn_checks() -> void:
	_check("clamps the dial to the range the schema allows",
		BonusSpawns.count(1.0) == 1
		and BonusSpawns.count(7.4) == 7
		and BonusSpawns.count(0.0) == BonusSpawns.MIN_COUNT
		and BonusSpawns.count(9999.0) == BonusSpawns.MAX_COUNT)

	# A zone has fewer elites than the dial's maximum, so the pool has to be reusable. The rule is
	# vanilla's generalised: every distinct one before any repeat.
	var pool := ["a", "b", "c"]
	var few := BonusSpawns.pick(pool, 2)
	_check("picks as many as were asked for", few.size() == 2 and few[0] != few[1])

	var many := BonusSpawns.pick(pool, 7)
	var counts := {}
	for id in many:
		counts[id] = int(counts.get(id, 0)) + 1
	_check("empties the pool before repeating anything", many.size() == 7
		and counts.size() == 3
		and int(counts["a"]) >= 2 and int(counts["b"]) >= 2 and int(counts["c"]) >= 2)

	_check("never edits the pool it was handed", pool.size() == 3)

	# A zone with no elites of its own is answered honestly rather than with another zone's.
	_check("an empty pool picks nothing", BonusSpawns.pick([], 5).empty())
	_check("a count of zero picks nothing", BonusSpawns.pick(pool, 0).empty())


# --- the settings screen's layout ------------------------------------------------------

func _settings_layout_checks() -> void:
	var sections := SettingsLayout.build(SCHEMA, {})
	_check("groups the schema into sections", sections.size() == 3
		and sections[0].title == "Enemies"
		and sections[1].title == "Run rules")

	_check("keeps the layout's order inside a section", sections[0].rows.size() == 2
		and sections[0].rows[0].key == "enemies_enabled"
		and sections[0].rows[1].key == "enemies_multiplier")

	# The property this whole file exists to protect: a setting added to the manifest and forgotten
	# in the layout is still reachable. Only its placement is lost.
	var last: Dictionary = sections[2]
	_check("a key no section claims is still drawn",
		last.title == SettingsLayout.UNCLAIMED_TITLE
		and last.rows.size() == 1
		and last.rows[0].key == "invented_later")

	# `palette` is a string, and the screen has no widget for one.
	var drawn := 0
	for section in sections:
		drawn += section.rows.size()
	_check("skips a type the screen cannot draw", drawn == 4)

	var slider: Dictionary = sections[0].rows[1]
	_check("a number row carries its range", slider.kind == "number"
		and is_equal_approx(slider.minimum, 1.0)
		and is_equal_approx(slider.maximum, 10.0)
		and is_equal_approx(slider.step, 0.5))
	_check("a row falls back to the schema default", is_equal_approx(slider.value, 2.0))
	_check("a row carries its title and description",
		slider.title == "Amount" and slider.description == "How many times vanilla.")

	var chosen := SettingsLayout.build(SCHEMA, {"enemies_multiplier": 4})
	_check("the player's own value wins over the default",
		is_equal_approx(chosen[0].rows[1].value, 4.0))

	# A sub-option is drawn only while the feature it belongs to is on.
	_check("a sub-option knows its parent", slider.parent == "enemies_enabled")
	_check("a toggle has no parent", sections[0].rows[0].parent == "")
	_check("a sub-option is hidden while its feature is off",
		not SettingsLayout.row_visible(slider, {"enemies_enabled": false}))
	_check("a sub-option is shown once its feature is on",
		SettingsLayout.row_visible(slider, {"enemies_enabled": true}))
	_check("a toggle is always shown",
		SettingsLayout.row_visible(sections[0].rows[0], {}))

	# The reason this is not left to Mod Options, which prints every float as a percentage of 1.
	_check("a multiplier reads as one", SettingsLayout.format_value("enemies_multiplier", 2.0) == "2.0x")
	_check("a percentage reads as one", SettingsLayout.format_value("elites_horde_chance", 40.0) == "40%")
	_check("a wave number reads as one", SettingsLayout.format_value("elites_first_wave", 11.0) == "11")
	_check("an unformatted key is printed as-is",
		SettingsLayout.format_value("invented_later", 3.0) == str(3.0))

	# A saved value the schema has since narrowed. ModLoader validates the whole config on every
	# save, so one of these left in the file makes every later save fail silently.
	var too_low := _only_adjustment({"enemies_multiplier": 0})
	_check("a value below the minimum is reported",
		too_low.get("key", "") == "enemies_multiplier"
		and is_equal_approx(too_low.get("value", -1.0), 0.0)
		and is_equal_approx(too_low.get("clamped", -1.0), 1.0))

	var too_high := _only_adjustment({"enemies_multiplier": 40})
	_check("a value above the maximum is reported",
		too_high.get("key", "") == "enemies_multiplier"
		and is_equal_approx(too_high.get("value", -1.0), 40.0)
		and is_equal_approx(too_high.get("clamped", -1.0), 10.0))

	_check("a value inside the range is left alone",
		SettingsLayout.out_of_range(SCHEMA, {"enemies_multiplier": 4}).empty())
	_check("a value on the edge of the range is left alone",
		SettingsLayout.out_of_range(SCHEMA, {"enemies_multiplier": 10}).empty())
	# `multipleOf` is the validator's other rule, deliberately not enforced: an off-step value came
	# from a hand-edited file, and rounding it would throw away a choice someone made on purpose.
	_check("an off-step value is left alone",
		SettingsLayout.out_of_range(SCHEMA, {"enemies_multiplier": 4.3}).empty())
	_check("a boolean is not treated as a number",
		SettingsLayout.out_of_range(SCHEMA, {"enemies_enabled": true}).empty())
	_check("a key the schema does not declare is ignored",
		SettingsLayout.out_of_range(SCHEMA, {"gone_in_a_later_version": -99}).empty())


func _only_adjustment(settings: Dictionary) -> Dictionary:
	var found := SettingsLayout.out_of_range(SCHEMA, settings)
	return found[0] if found.size() == 1 else {}


# --- the weapon limit ----------------------------------------------------------------------

func _weapon_limit_checks() -> void:
	_check("free slots is the limit minus what is held", Loadout.free_slots(6, 2) == 4)
	_check("free slots never reads as negative", Loadout.free_slots(1, 3) == 0)

	# The run-start case the tweak exists for: a limit of 1 under a character that brings two.
	_check("what is over the limit is what has to be dropped", Loadout.excess(1, 3) == 2)
	_check("a loadout inside the limit drops nothing", Loadout.excess(6, 2) == 0)
	_check("a loadout exactly at the limit drops nothing", Loadout.excess(6, 6) == 0)


# --- the ban allowance ----------------------------------------------------------------------

func _ban_allowance_checks() -> void:
	var players := [FakePlayer.new(), FakePlayer.new()]
	players[1].banned_items = [11, 22]

	var applied := Loadout.apply_ban_tokens(players, 2, 20)
	_check("every player in the run gets the allowance",
		applied == 2 and players[0].remaining_ban_token == 20)
	_check("bans already spent are not handed back", players[1].remaining_ban_token == 18)
	_check("ban mode is turned on with the allowance", players[0].uses_ban and players[1].uses_ban)

	# `players_data` is four entries long whether or not four people are playing.
	var one_playing := [FakePlayer.new(), FakePlayer.new()]
	_check("players who are not in the run are left alone",
		Loadout.apply_ban_tokens(one_playing, 1, 8) == 1
		and one_playing[1].remaining_ban_token == 0
		and not one_playing[1].uses_ban)

	# Lowering the allowance below what has already been spent, mid-run.
	var spender := [FakePlayer.new()]
	spender[0].banned_items = [1, 2, 3, 4]
	var _applied_to_spender := Loadout.apply_ban_tokens(spender, 1, 2)
	_check("an allowance under what is spent is no tokens, not negative",
		spender[0].remaining_ban_token == 0)

	_check("the label's two halves are the same sum", Loadout.spent_bans(20, 18) == 2)
	_check("the label never reads as negative", Loadout.spent_bans(2, 8) == 0)

	# The vanilla array is the game's to change shape of.
	_check("anything not shaped like player data is skipped, not a crash",
		Loadout.apply_ban_tokens([null, Reference.new()], 2, 8) == 0)


# --- recycling items ------------------------------------------------------------------------

# `Keys.hash_to_string` in miniature. The hashes are the game's; only the mapping matters here.
const ID_NAMES := {
	11: "item_baby_elephant",
	22: "item_bait",
	33: "item_builder_turret",
}


func _recycling_checks() -> void:
	_check("nothing changing the price is a factor of 1",
		Recycling.price_factor([], "item_baby_elephant", ID_NAMES) == 1.0)

	_check("the matching pair's factor is the answer",
		Recycling.price_factor([[11, 0.5]], "item_baby_elephant", ID_NAMES) == 0.5)

	_check("a pair naming another item leaves this one alone",
		Recycling.price_factor([[22, 0.5]], "item_baby_elephant", ID_NAMES) == 1.0)

	# Vanilla's own comparison is a substring test on the names, which is what makes one pair cover
	# every tier of an item whose ids share a prefix.
	_check("a name that is a prefix of the id matches it",
		Recycling.price_factor([[33, 2.0]], "item_builder_turret_2", ID_NAMES) == 2.0)

	_check("the first matching pair wins, like vanilla's own break",
		Recycling.price_factor([[11, 0.5], [11, 3.0]], "item_baby_elephant", ID_NAMES) == 0.5)

	# The effect is the game's array to change the shape of, and an unknown hash is a version of the
	# game this mod does not know rather than something to fail on.
	_check("a malformed or unknown pair is skipped, not a crash",
		Recycling.price_factor([null, [11], [999, 0.5], [11, 0.25]], "item_baby_elephant", ID_NAMES)
		== 0.25)


# --- the item limits ---------------------------------------------------------------------------

func _item_limit_checks() -> void:
	# The two switches are independent, and each one only answers for its own kind of item.
	_check("a unique is lifted by the unique switch only",
		ItemLimits.lifted(1, false, true)
		and not ItemLimits.lifted(1, true, false))
	_check("a limited item is lifted by the limited switch only",
		ItemLimits.lifted(3, true, false)
		and not ItemLimits.lifted(3, false, true))
	_check("both switches on lifts both",
		ItemLimits.lifted(1, true, true) and ItemLimits.lifted(2, true, true))
	_check("both switches off lifts nothing",
		not ItemLimits.lifted(1, false, false) and not ItemLimits.lifted(5, false, false))

	# -1 is most of the catalogue and has no limit to lift; 0 is an item the game never offers, and
	# putting one in a shop pool would be a different feature.
	_check("an item with no cap is not this feature",
		not ItemLimits.lifted(ItemLimits.NO_CAP, true, true))
	_check("an item the game never offers stays that way",
		not ItemLimits.lifted(ItemLimits.NEVER_OFFERED, true, true))

	# `max_nb` comes off a game resource, so a value neither this version nor the schema knows about
	# is answered rather than crashed on.
	_check("a cap below -1 is treated as no cap", not ItemLimits.lifted(-7, true, true))


# --- cursed enemies --------------------------------------------------------------------------

# Stands in for the DLC's CurseSceneEffectBehavior — the node found off the spawner's connection
# list, and the one method this mod calls on it.
class FakeCurseSource:
	var cursed := []

	func _curse_enemy(enemy, curse_value: float) -> void:
		cursed.append([enemy, curse_value])


func _cursed_enemy_checks() -> void:
	var FakeEnemy = load("res://stubs/fake_enemy.gd")
	var CurseBehavior = load("res://stubs/curse_enemy_effect_behavior.gd")

	var enemy = FakeEnemy.new()
	var source = FakeCurseSource.new()

	_check("an ordinary enemy can be cursed", Curse.can_curse_enemy(enemy))
	_check("cursing an enemy goes through the DLC's own method",
		Curse.curse_enemy(enemy, source, 40.0)
		and source.cursed.size() == 1
		and is_equal_approx(source.cursed[0][1], 40.0))

	# The DLC's own listener runs first, so this is the ordinary case, not an edge one.
	enemy.effect_behaviors.add_child(CurseBehavior.new())
	_check("an enemy the DLC already cursed is recognised", Curse.enemy_is_cursed(enemy))
	_check("and is not cursed a second time",
		not Curse.curse_enemy(enemy, source, 40.0) and source.cursed.size() == 1)

	var opted_out = FakeEnemy.new()
	opted_out.can_be_cursed = false
	_check("an enemy the game excludes is never cursed", not Curse.can_curse_enemy(opted_out))

	var already_dead = FakeEnemy.new()
	already_dead.dead = true
	_check("an enemy already dead is not cursed", not Curse.can_curse_enemy(already_dead))

	var without_dlc = FakeEnemy.new()
	_check("without the DLC there is nothing to curse with",
		not Curse.curse_enemy(without_dlc, null, 0.0))
	_check("nothing at all is not an enemy", not Curse.can_curse_enemy(null))

	enemy.free()
	opted_out.free()
	already_dead.free()
	without_dlc.free()


# --- recursing ---------------------------------------------------------------------------------

# The offer roll in miniature. The real one is
# `ItemService.apply_item_effect_modifications()` — the game's natural curse chance with this mod's
# All Cursed on top — and it either hands back a cursed copy or hands back what it was given. Each
# hit produces a different `curse_factor`, which is the whole point of re-rolling.
class FakeOfferRoll:
	extends Reference

	var hits := 0

	func roll(item_data, hit: bool):
		if not hit or item_data.is_cursed:
			return item_data
		hits += 1
		var copy = item_data.copy()
		copy.is_cursed = true
		copy.curse_factor = float(hits)
		return copy


func _recurse_checks() -> void:
	var FakeItem = load("res://stubs/fake_item.gd")
	var offer = FakeOfferRoll.new()

	var base = FakeItem.new()
	var cursed = offer.roll(base, true)

	var recursed = Curse.recurse(cursed, base, offer.roll(base, true))
	_check("a roll that came back cursed replaces the slot",
		recursed != cursed and recursed != base and recursed.is_cursed)
	_check("the re-roll is a different roll, not a copy of the old one",
		not is_equal_approx(recursed.curse_factor, cursed.curse_factor))
	_check("the original is left uncursed for the next re-roll",
		not base.is_cursed and is_equal_approx(base.curse_factor, 0.0))

	# The half that makes this safe to run at the game's own rate rather than a chance of the mod's:
	# a miss is common, and it must not cost the slot the curse it already had.
	_check("a roll that missed leaves the curse the slot had",
		Curse.recurse(cursed, base, offer.roll(base, false)) == cursed)

	# The item that was already going to be cursed by the roll that offered it, and the character,
	# which is added through the same seams as an item and is never cursed.
	_check("an uncursed item is not this feature",
		Curse.recurse(base, base, offer.roll(base, true)) == base)
	_check("a character is never re-rolled",
		Curse.recurse(CharacterData.new(), base, offer.roll(base, true)) is CharacterData)

	# An id this version of the game has no catalogue entry for, and a roll that answered nothing.
	_check("no original leaves the slot alone", Curse.recurse(cursed, null, cursed) == cursed)
	_check("nothing rolled leaves the slot alone", Curse.recurse(cursed, base, null) == cursed)
	_check("nothing at all is not an item", Curse.recurse(null, base, cursed) == null)

	# The guard that keeps a session-lifetime catalogue resource out of a shop slot. The roll hands
	# its argument straight back on a miss, and the shop would then hold the resource that every
	# later roll of that item duplicates from.
	_check("a roll that handed the original back is refused",
		Curse.recurse(cursed, base, base) == cursed)


# --- the settings tab ---------------------------------------------------------------------
#
# The one part of the mod that is nodes rather than arithmetic, so it is driven rather than
# reasoned about: the tab is built into this scene against the stub at
# `res://ui/menus/global/slider_option.tscn` and then read back.
#
# What it catches is the wiring that would otherwise fail silently: a widget that was never
# reached, a value label still showing vanilla's percentage, and a settings write echoing back out
# as another change. The Options menu around it — the tab strip, the button, gamepad focus — is
# tests/run_menu.sh's job, which lays the tab out on a real title screen.

var _tab_changes := []


func _settings_tab_checks() -> void:
	var TweaksTab = load("res://mods-unpacked/Brotato-Tweaks/ui/tweaks_tab.gd")
	var tab = TweaksTab.new()
	add_child(tab)
	tab.connect("setting_changed", self, "_on_tab_setting_changed")

	var settings := {
		"enemies_enabled": false,
		"enemies_multiplier": 2,
		"death_guard_enabled": true,
		"invented_later": true,
	}
	var sections := SettingsLayout.build(SCHEMA, settings)

	_check("the tab builds itself from the sections", tab.set_sections(sections, "intro"))
	_check("every row it can draw has a widget", tab._widgets.size() == 4)

	var dial: Dictionary = tab._widgets["enemies_multiplier"]
	_check("a number row reached the slider inside the option",
		is_instance_valid(dial.widget) and is_equal_approx(dial.widget.value, 2.0))
	_check("a number row carries the schema's range into the slider",
		is_equal_approx(dial.widget.min_value, 1.0)
		and is_equal_approx(dial.widget.max_value, 10.0)
		and is_equal_approx(dial.widget.step, 0.5))

	# Vanilla's own handler would have written "200%" here.
	_check("the value reads as the mod set it, not as a percentage", dial.value_label.text == "2.0x")
	_check("a toggle carries the player's value into the widget",
		tab._widgets["death_guard_enabled"].widget.pressed)

	tab.apply_settings(settings)
	_check("a sub-option starts hidden while its feature is off", not dial.row.visible)

	# The loop this has to not have: `apply_settings()` is called from the very signal these
	# widgets emit, so a widget that reports the value it was just given never settles.
	_tab_changes.clear()
	settings["enemies_enabled"] = true
	settings["enemies_multiplier"] = 4
	tab.apply_settings(settings)
	_check("a sub-option appears once its feature is on", dial.row.visible)
	_check("being told a value moves the widget", is_equal_approx(dial.widget.value, 4.0))
	_check("being told a value relabels it", dial.value_label.text == "4.0x")
	_check("being told a value reports nothing back", _tab_changes.empty())

	# And the move that does have to be reported: the player's own.
	dial.widget.value = 5.0
	_check("moving a slider reports the key and the value", _tab_changes.size() == 1
		and _tab_changes[0][0] == "enemies_multiplier"
		and is_equal_approx(_tab_changes[0][1], 5.0))
	_check("moving a slider relabels it", dial.value_label.text == "5.0x")

	# The toggle was switched on by the `apply_settings()` above, silently. Switching it back off is
	# both halves of the check: that a press reports, and that the silent write landed.
	_tab_changes.clear()
	tab._widgets["enemies_enabled"].widget.pressed = false
	_check("pressing a toggle reports it", _tab_changes.size() == 1
		and _tab_changes[0][0] == "enemies_enabled"
		and _tab_changes[0][1] == false)

	remove_child(tab)
	tab.queue_free()


func _on_tab_setting_changed(key: String, value) -> void:
	_tab_changes.append([key, value])


func _check(name: String, passed: bool) -> void:
	if passed:
		print("ok: ", name)
	else:
		print("FAIL: ", name)
		_failures += 1
