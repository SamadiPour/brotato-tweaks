extends Node

# The mod's own runtime node. Owns the settings and answers every question the adapters ask;
# nothing in extensions/ decides anything for itself.
#
# Adapters find it through the "brotato_tweaks" group rather than a node path, so it does not
# matter where the loader mounts mod_main:
#
#     var found = get_tree().get_nodes_in_group("brotato_tweaks")
#
# See docs/01-architecture.md.

const GROUP := "brotato_tweaks"

const Logger := preload("core/logger.gd")
const SettingsStore := preload("core/settings_store.gd")
const WaveScaling := preload("core/wave_scaling.gd")
const Curse := preload("core/curse.gd")
const EnemyStats := preload("core/enemy_stats.gd")
const EliteSchedule := preload("core/elite_schedule.gd")
const BonusSpawns := preload("core/bonus_spawns.gd")
const SpawnRate := preload("core/spawn_rate.gd")
const Loadout := preload("core/loadout.gd")
const Recycling := preload("core/recycling.gd")
const ItemLimits := preload("core/item_limits.gd")

const FEATURE_ENEMIES := "enemy_multiplier"
const FEATURE_DEATH_GUARD := "death_guard"
const FEATURE_CURSE := "all_cursed"
const FEATURE_RECURSE := "recurse"
const FEATURE_UNLIMITED_ITEMS := "unlimited_items"
const FEATURE_UNLIMITED_UNIQUES := "unlimited_uniques"
const FEATURE_ENEMY_STATS := "enemy_stats"
const FEATURE_ELITES := "elite_schedule"
const FEATURE_BONUS_ELITES := "bonus_elites"
const FEATURE_BONUS_BOSSES := "bonus_bosses"
const FEATURE_WAVE_LENGTH := "wave_length"
const FEATURE_HORDES := "horde_every_wave"
const FEATURE_BANS := "bans"
const FEATURE_RECYCLE_ITEMS := "recycle_items"
const FEATURE_WEAPON_LIMIT := "weapon_limit"
const FEATURE_ENDLESS_HARVESTING := "endless_harvesting"
const FEATURE_ENDLESS_PIGGY_BANK := "endless_piggy_bank"

# Feature -> the setting that switches it on.
const FEATURE_SETTINGS := {
	FEATURE_ENEMIES: "enemies_enabled",
	FEATURE_DEATH_GUARD: "death_guard_enabled",
	FEATURE_CURSE: "cursed_enabled",
	FEATURE_RECURSE: "recurse_enabled",
	FEATURE_UNLIMITED_ITEMS: "unlimited_items_enabled",
	FEATURE_UNLIMITED_UNIQUES: "unlimited_uniques_enabled",
	FEATURE_ENEMY_STATS: "enemy_stats_enabled",
	FEATURE_ELITES: "elites_enabled",
	FEATURE_BONUS_ELITES: "bonus_elites_enabled",
	FEATURE_BONUS_BOSSES: "bonus_bosses_enabled",
	FEATURE_WAVE_LENGTH: "wave_duration_enabled",
	FEATURE_HORDES: "horde_every_wave_enabled",
	FEATURE_BANS: "bans_enabled",
	FEATURE_RECYCLE_ITEMS: "recycle_items_enabled",
	FEATURE_WEAPON_LIMIT: "weapon_limit_enabled",
	FEATURE_ENDLESS_HARVESTING: "endless_harvesting_enabled",
	FEATURE_ENDLESS_PIGGY_BANK: "endless_piggy_bank_enabled",
}

# "off", for the two features whose answer is a number the game already has one of. An adapter
# that gets this leaves the vanilla value alone rather than substituting a default of its own.
const NOT_SET := -1

signal settings_changed(settings)

# Feature -> why it switched itself off. A feature that finds the vanilla shape it needs is gone
# gives up permanently and says so once, and the others carry on. Nothing here ever takes the game
# down with it.
var disabled_features := {}

var _curse_availability_reported := false

# Where the settings actually live, and the whole of the ModLoader side of them — see
# core/settings_store.gd. Mounted as a child so its timers have a tree to run in.
var _store = null


func _ready() -> void:
	add_to_group(GROUP)

	_store = SettingsStore.new()
	_store.name = "SettingsStore"
	add_child(_store)
	_store.connect("changed", self, "_on_settings_changed")
	_store.connect("persisted", self, "_on_settings_persisted")
	_store.mount()

	Logger.info("mounted - " + _enabled_summary())


# A value moved, by whatever route. Passed straight on, so a screen already open follows an edit it
# did not make itself.
func _on_settings_changed(settings) -> void:
	emit_signal("settings_changed", settings)


# The change reached disk. At most one of these per debounce window, which is why the summary is
# logged here rather than on every step of a slider drag.
func _on_settings_persisted(_settings) -> void:
	Logger.info("settings changed - " + _enabled_summary())


# --- what the adapters ask -----------------------------------------------------------

func feature_enabled(feature: String) -> bool:
	if disabled_features.has(feature):
		return false
	if not FEATURE_SETTINGS.has(feature):
		return false
	return bool(get_setting(FEATURE_SETTINGS[feature], false))


func disable_feature(feature: String, reason: String) -> void:
	if disabled_features.has(feature):
		return
	disabled_features[feature] = reason
	Logger.warning("'%s' switched itself off: %s. The rest of the mod is unaffected." % [feature, reason])


# Enemy multiplier. Rewrites one wave's spawn plan in place; see core/wave_scaling.gd for what
# "in place" is allowed to mean here. `enemy_type` is the caller's `EntityType.ENEMY`.
func scale_wave(wave_data, enemy_type: int) -> void:
	if not feature_enabled(FEATURE_ENEMIES):
		return

	var report := WaveScaling.scale(
		wave_data,
		float(get_setting("enemies_multiplier", 2.0)),
		bool(get_setting("enemies_raise_cap", true)),
		enemy_type
	)

	if not report.ok:
		disable_feature(FEATURE_ENEMIES, report.reason)
		return

	# The spawn budget is printed with the cap because the two are read together: a lifted cap the
	# queue cannot fill fast enough is the one failure of this feature that looks like nothing
	# happening. Vanilla's own budget is 2, which is 40 enemies a second.
	if verbose():
		var budget := SpawnRate.budget_per_tick(
			float(get_setting("enemies_multiplier", 2.0)),
			bool(get_setting("enemies_fast_spawn", true))
		)
		Logger.info("enemy multiplier: %d groups, %d unit types, cap %d -> %d, %d spawns/tick" % [
			report.groups_scaled, report.units_scaled, report.cap_before, report.cap_after, budget,
		])


# The enemy multiplier's other half. Vanilla releases at most two queued entities every third
# physics frame — 40 a second — so a plan multiplied past about 4x queues faster than it can ever
# arrive, and the lifted cap is never the thing in the way. This says how many extra to release,
# on top of the two vanilla already did, in the tick the adapter is asking from.
#
# 0 when the tweak is off, when the dial is at 1, or when the queue is empty, so a wave with
# nothing to do costs two dictionary reads per spawn tick. See core/spawn_rate.gd.
func enemy_spawn_extra(queue_size: int) -> int:
	if not feature_enabled(FEATURE_ENEMIES):
		return 0
	return SpawnRate.extra_per_tick(
		queue_size,
		float(get_setting("enemies_multiplier", 2.0)),
		bool(get_setting("enemies_fast_spawn", true))
	)


# Horde every wave. Runs before scale_wave() so the injected hordes are multiplied along with
# everything else — one predictable rule rather than two switches that disagree.
func inject_hordes(wave_data, horde_groups: Array, current_wave: int) -> void:
	if not feature_enabled(FEATURE_HORDES):
		return
	if horde_groups.empty():
		return

	var report := WaveScaling.inject_groups(wave_data, horde_groups, current_wave)
	if not report.ok:
		disable_feature(FEATURE_HORDES, report.reason)
		return
	if verbose():
		Logger.info("horde every wave: %d groups added" % report.injected)


# Wave length. A different seam from the two above — see core/wave_scaling.gd.
func scale_wave_duration(wave_data) -> void:
	if not feature_enabled(FEATURE_WAVE_LENGTH):
		return

	var report := WaveScaling.scale_duration(wave_data, float(get_setting("wave_duration_multiplier", 1.0)))
	if not report.ok:
		disable_feature(FEATURE_WAVE_LENGTH, report.reason)
		return
	if verbose() and report.before != report.after:
		Logger.info("wave length: %ds -> %ds" % [report.before, report.after])


# Enemy stat dials. Called on the way out of EntityService, once per enemy stat lookup, so they
# stay cheap: a clamp and a multiply, no lookups of their own.
func scale_enemy_health(value: float) -> int:
	return _scale_enemy_stat(value, "enemy_health_multiplier", 1)


func scale_enemy_damage(value: float) -> int:
	return _scale_enemy_stat(value, "enemy_damage_multiplier", 1)


func scale_enemy_speed(value: float) -> int:
	return _scale_enemy_stat(value, "enemy_speed_multiplier", 0)


func _scale_enemy_stat(value: float, key: String, minimum: int) -> int:
	if not feature_enabled(FEATURE_ENEMY_STATS):
		return int(round(value))
	return EnemyStats.scale(value, float(get_setting(key, 1.0)), minimum)


# Elite and horde scheduling. Returns the arguments `RunData.init_elites_spawn()` should be called
# with: the caller's own, unless this is the run-start call — see core/elite_schedule.gd for why
# that distinction is the whole feature.
func elite_schedule_args(base_wave: int, horde_chance: float) -> Dictionary:
	if not feature_enabled(FEATURE_ELITES):
		return {"apply": false, "base_wave": base_wave, "horde_chance": horde_chance}

	var args := EliteSchedule.override_args(
		base_wave,
		horde_chance,
		int(get_setting("elites_first_wave", 11)),
		float(get_setting("elites_horde_chance", 40))
	)
	if args.apply and verbose():
		Logger.info("elites: first at wave %d, horde chance %d%%" % [
			int(args.base_wave) + 1, int(round(float(args.horde_chance) * 100.0)),
		])
	return args


# Bonus elites and bonus bosses — a fixed number added to every wave, on top of whatever that wave
# already spawns, from wave 1. Not vanilla's schedule and not a chance: `elite_schedule_args()`
# above moves the game's own timetable, and these two are independent of it and of each other.
#
# 0 means the tweak is off, and it is asked first so a wave with both off costs two dictionary
# reads and no catalogue lookup at all.
func bonus_elite_count() -> int:
	if not feature_enabled(FEATURE_BONUS_ELITES):
		return 0
	return BonusSpawns.count(float(get_setting("bonus_elites_count", 1)))


func bonus_boss_count() -> int:
	if not feature_enabled(FEATURE_BONUS_BOSSES):
		return 0
	return BonusSpawns.count(float(get_setting("bonus_bosses_count", 1)))


# Which ones, out of what the zone offers. `pool` is the zone's elites or its bosses; the answer
# is `count` of them, every distinct one before any repeat. Empty pool, empty answer — see
# core/bonus_spawns.gd.
func pick_bonus(pool: Array, count: int) -> Array:
	return BonusSpawns.pick(pool, count)


# Said once per wave, and only with the verbose log on: the adapter has already added them by the
# time it calls this, so there is nothing here to get wrong.
func report_bonus_spawns(what: String, count: int) -> void:
	if verbose():
		Logger.info("bonus %s: %d added to this wave" % [what, count])


# All Cursed. Called from two seams — when an item is offered (ItemService) and when one enters an
# inventory (RunData) — because neither covers the other: the shop must show what it is selling, and
# starting gear never passes through the shop. Cursing twice is not a risk; core/curse.gd hands an
# already cursed item straight back. Always returns something safe to hand to the vanilla method
# that asked.
func curse_data(data, player_index: int, is_weapon: bool):
	if not feature_enabled(FEATURE_CURSE):
		return data
	if not bool(get_setting("cursed_weapons" if is_weapon else "cursed_items", true)):
		return data
	_report_curse_availability()
	return Curse.curse(data, player_index)


# "All Cursed is on but nothing is cursed" has exactly one cause worth reporting, and this says it
# once per session. It cannot be checked in _ready(): the mod is mounted from ModLoader, which is
# the sixth autoload, and ProgressData is the tenth — and even once it exists, the DLC pack is not
# mounted until `ProgressData.load_dlc_pcks()`. By the first pickup, both are true or neither is.
# 0 when the tweak is off, or on with the dial down. Asked once per enemy spawn before anything
# else is looked up, so it is one dictionary read and nothing more when there is nothing to do.
func cursed_enemy_chance() -> float:
	if not feature_enabled(FEATURE_CURSE):
		return 0.0
	return float(get_setting("cursed_enemy_chance", 0))


# All Cursed, the enemy half. Called once per enemy spawn, straight after the DLC's own listener
# has had its roll, so an enemy it already cursed arrives here cursed and core/curse.gd hands it
# back untouched. `behavior` is the DLC's CurseSceneEffectBehavior, or null when the DLC is not
# active — in which case nothing here can or should happen.
#
# The chance is rolled on top of vanilla's, not instead of it: with the dial at 0 this is the
# vanilla rate, and with it at 100 every enemy that may be cursed is.
func curse_enemy(enemy, behavior, curse_value: float) -> void:
	var chance := cursed_enemy_chance()
	if chance <= 0.0:
		return
	if rand_range(0.0, 100.0) >= chance:
		return

	if Curse.curse_enemy(enemy, behavior, curse_value) and verbose():
		Logger.info("all cursed: cursed an enemy on spawn")


# --- recursing -------------------------------------------------------------------------

# Recurse. Asked once as the shop closes, before anything is looked up, so a shop closing with this
# off costs one dictionary read.
#
# There is deliberately no chance of its own. A re-roll is the game's own offer roll, made again on
# the item's original, so a locked cursed item is re-cursed exactly as often as a new one of the
# same kind would arrive cursed — All Cursed included, which makes it every time. A second number
# here would be a second thing to keep in step with the first.
func recurse_locked_items() -> bool:
	return feature_enabled(FEATURE_RECURSE)


# One cursed locked shop item, re-rolled or left alone. `base` is the uncursed catalogue resource
# the adapter looked it up from, and `rolled` is what the offer roll made of it — see core/curse.gd.
# Never returns null: the answer goes straight back into the shop slot it came from.
func recurse_locked(data, base, rolled):
	if not feature_enabled(FEATURE_RECURSE):
		return data
	var recursed = Curse.recurse(data, base, rolled)
	return data if recursed == null else recursed


# Said by the adapter once the slot holds the new copy, so there is nothing here to get out of step.
func report_recursed(item_id: String) -> void:
	if verbose():
		Logger.info("recurse: re-rolled the curse on %s" % item_id)


# --- item limits -----------------------------------------------------------------------

# The two "no limit" tweaks, asked with the item's own `max_nb`. See core/item_limits.gd: -1 has no
# limit already, 0 is an item the game never offers, 1 is a unique and anything higher is a limited
# item. False for every one of those the player has not asked to lift, which is what makes the
# adapters hand vanilla's own answer straight back.
func item_limit_lifted(max_nb: int) -> bool:
	return ItemLimits.lifted(
		max_nb,
		feature_enabled(FEATURE_UNLIMITED_ITEMS),
		feature_enabled(FEATURE_UNLIMITED_UNIQUES)
	)


# Bans. -1 means the tweak is off and the game's own `RunData.BAN_MAX_TOKEN` stands.
func ban_allowance() -> int:
	if not feature_enabled(FEATURE_BANS):
		return NOT_SET
	return int(get_setting("bans_max", 8))


# Hands every player their allowance, at the two moments vanilla sets the same field: the run
# reset and the difficulty screen that starts the run. Ban mode is turned on with it — see
# core/loadout.gd for why an allowance without it would be unspendable.
func apply_ban_tokens(players_data: Array, player_count: int) -> void:
	var allowance := ban_allowance()
	if allowance == NOT_SET:
		return

	var applied := Loadout.apply_ban_tokens(players_data, player_count, allowance)
	if applied > 0 and verbose():
		Logger.info("bans: %d token(s) for %d player(s)" % [allowance, applied])


# Whether the shop's ban button should appear on weapons too. Vanilla puts it on items only.
func bans_cover_weapons() -> bool:
	if not feature_enabled(FEATURE_BANS):
		return false
	return bool(get_setting("bans_weapons", false))


# The one screen that shows bans as "spent / allowance" reads `RunData.BAN_MAX_TOKEN` for both
# halves, which is the wrong number as soon as the allowance is this mod's. Returns what the label
# should say, or `apply: false` to leave vanilla's text alone.
func ban_label_counts(remaining: int) -> Dictionary:
	var allowance := ban_allowance()
	if allowance == NOT_SET:
		return {"apply": false, "spent": 0, "allowance": 0}
	return {"apply": true, "spent": Loadout.spent_bans(allowance, remaining), "allowance": allowance}


# Recycle items. Vanilla puts a Recycle button on a weapon you own and on an item you are being
# offered, and nowhere on an item you already have. On, the shop's item panel offers it too. One
# press is one copy, so an item you hold three of takes three presses — the adapters do not have to
# know that, because it is what the game's own inventory element and `RunData.remove_item()` already
# do for a stack.
func recycle_items() -> bool:
	return feature_enabled(FEATURE_RECYCLE_ITEMS)


# The `specific_items_price` factor vanilla folds into an item's value before it prices a recycle.
# Asked twice per recycle — once for the button's label, once for the payout — so that the two are
# the same number by construction. `id_names` is `Keys.hash_to_string`; see core/recycling.gd.
func recycle_price_factor(specific_items_price: Array, item_id: String, id_names: Dictionary) -> float:
	return Recycling.price_factor(specific_items_price, item_id, id_names)


# Said by the adapter once the item is gone and the materials are paid, so there is nothing here to
# get out of step.
func report_item_recycled(item_id: String, value: int) -> void:
	if verbose():
		Logger.info("recycle items: %s recycled for %d material(s)" % [item_id, value])


# Weapon limit. -1 means the tweak is off and the vanilla weapon slot effect stands.
func weapon_limit() -> int:
	if not feature_enabled(FEATURE_WEAPON_LIMIT):
		return NOT_SET
	return int(get_setting("weapon_limit", 6))


# How many weapons still fit, given how many are held. -1 when the tweak is off.
func free_weapon_slots(held: int) -> int:
	var limit := weapon_limit()
	if limit == NOT_SET:
		return NOT_SET
	return Loadout.free_slots(limit, held)


# How many weapons are over the limit and have to be dropped. 0 when the tweak is off, and 0 in
# the ordinary case where a run starts inside the limit. Non-zero at run start when a character's
# own starting weapons take it past a limit the player set below them.
func weapon_overflow(held: int) -> int:
	var limit := weapon_limit()
	if limit == NOT_SET:
		return 0
	return Loadout.excess(limit, held)


# --- past wave 20 --------------------------------------------------------------------

# Two vanilla rules that only exist past `RunData.nb_of_waves`, and one switch each. Whether the
# run is actually past that wave is the adapter's to check — it is RunData's own field, and both
# adapters are already holding it.
#
# Harvesting decay. Vanilla removes 20% of the Harvesting stat at the end of every endless wave.
# On, that removal does not happen and the stat stays where the run left it. Deliberately not the
# other half: vanilla's harvesting *growth* is the branch this one replaces, and turning that back
# on as well would be a second feature with a second failure mode.
func keep_harvesting() -> bool:
	return feature_enabled(FEATURE_ENDLESS_HARVESTING)


# Said by the adapter after it has skipped the removal, so there is nothing here to get wrong.
func report_harvesting_kept(value: int) -> void:
	if verbose():
		Logger.info("endless harvesting: kept the %d this wave would have taken" % value)


# The Piggy Bank, past wave 20. Vanilla pays out `gain_pct_gold_start_wave` at the start of every
# wave up to `nb_of_waves` and then stops; on, the payout carries on at the same rate. Only a
# positive rate is affected — a negative one is a character that loses materials at the start of a
# wave, which vanilla already applies in endless and this leaves alone.
func keep_piggy_bank() -> bool:
	return feature_enabled(FEATURE_ENDLESS_PIGGY_BANK)


func report_piggy_bank(player_index: int, value: int) -> void:
	if verbose():
		Logger.info("endless piggy bank: %d material(s) to player %d" % [value, player_index + 1])


func _report_curse_availability() -> void:
	if _curse_availability_reported:
		return
	_curse_availability_reported = true
	if Curse.available():
		Logger.info("all cursed: the Abyssal Terrors curse is available")
	else:
		Logger.warning("all cursed is on, but Abyssal Terrors is not active - nothing will be cursed")


func verbose() -> bool:
	return bool(get_setting("verbose_log", false))


# --- settings ------------------------------------------------------------------------

# Everything below is `core/settings_store.gd` answering, and the delegation is the point: the
# adapters and the settings screen ask `Tweaks` for a value, and where that value is kept, how it is
# saved and which ModLoader config it came out of is none of their business.
#
# `set_setting()` is still the single write path — the mod's own tab and Brotato Mod Options both
# end here — and the store is what enforces that only keys the schema declared are accepted.

func get_setting(key: String, default = null):
	return _store.get_setting(key, default) if _store != null else default


# The whole settings dictionary, for the settings screen, which draws every row from it at once.
func get_settings() -> Dictionary:
	return _store.settings if _store != null else {}


func set_setting(key: String, value) -> void:
	if _store != null:
		_store.set_setting(key, value)


func reset_to_defaults() -> void:
	if _store != null and _store.reset_to_defaults():
		Logger.info("settings reset to defaults - " + _enabled_summary())


func get_schema_properties() -> Dictionary:
	return _store.get_schema_properties() if _store != null else {}


func schema_description() -> String:
	return _store.schema_description() if _store != null else ""


func _enabled_summary() -> String:
	var on := []
	if feature_enabled(FEATURE_ENEMIES):
		on.append("enemies x%s" % str(get_setting("enemies_multiplier", 2.0)))
	if feature_enabled(FEATURE_ENEMY_STATS):
		on.append("enemy hp x%s, dmg x%s, spd x%s" % [
			str(get_setting("enemy_health_multiplier", 1.0)),
			str(get_setting("enemy_damage_multiplier", 1.0)),
			str(get_setting("enemy_speed_multiplier", 1.0)),
		])
	if feature_enabled(FEATURE_HORDES):
		on.append("horde every wave")
	if feature_enabled(FEATURE_ELITES):
		on.append("elites from wave %s" % str(get_setting("elites_first_wave", 11)))
	if feature_enabled(FEATURE_BONUS_ELITES):
		on.append("+%d elite(s) every wave" % bonus_elite_count())
	if feature_enabled(FEATURE_BONUS_BOSSES):
		on.append("+%d boss(es) every wave" % bonus_boss_count())
	if feature_enabled(FEATURE_WAVE_LENGTH):
		on.append("wave length x%s" % str(get_setting("wave_duration_multiplier", 1.0)))
	if feature_enabled(FEATURE_DEATH_GUARD):
		on.append("death guard")
	# Deliberately not "…, DLC present": this runs from _ready(), where ProgressData may not be
	# instanced yet and the DLC pack is certainly not mounted. _report_curse_availability() says
	# so at the first pickup instead.
	if feature_enabled(FEATURE_CURSE):
		var cursed := "all cursed"
		if float(get_setting("cursed_enemy_chance", 0)) > 0.0:
			cursed += " (enemies %s%%)" % str(get_setting("cursed_enemy_chance", 0))
		on.append(cursed)
	if feature_enabled(FEATURE_RECURSE):
		on.append("recurse locked items")
	if feature_enabled(FEATURE_UNLIMITED_ITEMS):
		on.append("no limit on limited items")
	if feature_enabled(FEATURE_UNLIMITED_UNIQUES):
		on.append("no limit on unique items")
	if feature_enabled(FEATURE_BANS):
		on.append("%s bans" % str(ban_allowance()))
	if feature_enabled(FEATURE_RECYCLE_ITEMS):
		on.append("recycle items")
	if feature_enabled(FEATURE_WEAPON_LIMIT):
		on.append("%s weapon(s) max" % str(weapon_limit()))
	if feature_enabled(FEATURE_ENDLESS_HARVESTING):
		on.append("no harvesting decay past wave 20")
	if feature_enabled(FEATURE_ENDLESS_PIGGY_BANK):
		on.append("piggy bank past wave 20")
	if on.empty():
		return "every tweak is off"
	return "on: " + PoolStringArray(on).join(", ")
