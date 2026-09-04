extends "res://singletons/run_data.gd"

# Adapter: All Cursed (second half), the elite schedule, the ban allowance, the item limits, the
# weapon limit and the endless harvesting decay — six tweaks, because RunData is where the game
# keeps all six answers.
#
# ## All Cursed
#
# `add_item()` and `add_weapon()` are where every route into a player's inventory converges — the
# shop, a crate, a consumable, starting gear, the character itself, another mod. Curse the
# argument on the way past and everything the player owns is cursed, with no second code path to
# keep in step. What to curse and what to leave alone is core/curse.gd's problem.
#
# `singletons/item_service.gd` curses earlier, when an item is *offered*, because a shop card has
# to show what it is selling. Everything it covers arrives here already cursed and `core/curse.gd`
# hands it straight back, so this hook is what is left: starting gear, the character-selection
# weapon, a consumable's item, another mod's.
#
# Both hooks hand the vanilla method a value and then get out of the way: the vanilla call is made
# exactly once, with all of its arguments, and `add_weapon()`'s return value is passed straight
# back to the caller, which uses it (`BaseShop.buy_weapon` keeps the returned instance).
#
# ## The ban allowance
#
# `RunData.BAN_MAX_TOKEN` is a constant, and a constant cannot be a setting. What it is *for* is
# not constant, though: it is copied into `PlayerRunData.remaining_ban_token` at the two moments a
# run begins — `reset()` and the difficulty screen — and decremented from there as bans are spent.
# Both moments are overridden, and each writes the allowance the player asked for instead. See
# `extensions/ui/menus/run/difficulty_selection/difficulty_selection.gd` for the second one.
#
# ## The weapon limit
#
# How many weapons fit is not a constant either — it is `Keys.weapon_slot_hash`, a player *effect*
# that the character sets, items add to and level-ups raise. Overwriting it would be a fight with
# every one of those, so it is answered rather than written: the three vanilla reads that ask "how
# many weapons fit" are overridden to answer with the limit, and the effect underneath is left
# exactly as the game left it. Turn the tweak off mid-run and the vanilla number is back, intact.
#
# `weapon_slot_upgrades` is capped with it, and that is not cosmetic: `ItemService.get_upgrades()`
# forces a weapon-slot upgrade card whenever the current slot count is below it, so a limit under
# that target would make every level-up offer the same dead upgrade forever.
#
# ## The endless harvesting decay
#
# `remove_stat()` is the seam because it is the only line that performs the decay, and because
# skipping a removal is cleaner than undoing one — see the note above the override.
#
# This is an extension of an autoload's script. ModLoader is the sixth autoload in
# project.godot and RunData the fifteenth, so the extension is installed before the singleton is
# instanced. If that order ever changes, this file stops applying and nothing else breaks.
#
# See docs/01-architecture.md ("Extension points").

const TWEAKS_GROUP := "brotato_tweaks"

# `get_player_effect()` is one of the busiest methods in the game — several calls per enemy per
# frame — so the Tweaks node is looked up once and kept. The group lookup behind `_tweaks()` walks
# the scene tree, which is nothing on a wave boundary and far too much per frame.
var _tweaks_node = null


func add_item(item: ItemData, player_index: int, is_selection: bool = false) -> void:
	.add_item(_tweaks_curse(item, player_index, false), player_index, is_selection)


func add_weapon(weapon: WeaponData, player_index: int, is_selection: bool = false) -> WeaponData:
	return .add_weapon(_tweaks_curse(weapon, player_index, true), player_index, is_selection)


# Elite and horde scheduling. Vanilla decides *which* elites and *how many*; only the two
# arguments are rewritten, and only on the run-start call. `main.gd`'s endless top-up passes an
# absolute wave and must reach vanilla untouched — core/elite_schedule.gd is where that is
# decided, and why.
func init_elites_spawn(base_wave: int = 10, horde_chance: float = 0.4) -> void:
	var tweaks = _tweaks()
	if tweaks == null:
		.init_elites_spawn(base_wave, horde_chance)
		return

	var args: Dictionary = tweaks.elite_schedule_args(base_wave, horde_chance)
	.init_elites_spawn(int(args.base_wave), float(args.horde_chance))


# --- the ban allowance ---------------------------------------------------------------------

# Vanilla's `reset()` hands every player `BAN_MAX_TOKEN` and copies the ban-mode toggle in. This
# runs straight after and replaces both with what the player set, so a run restarted from the
# end-run screen — which reaches `reset(true)` and never the difficulty screen — starts with the
# same allowance as a fresh one.
func reset(restart: bool = false) -> void:
	.reset(restart)

	var tweaks = _tweaks()
	if tweaks != null:
		tweaks.apply_ban_tokens(players_data, get_player_count())


# The banned list behind the pause menu's "banned items" tab, and behind the end-run screen's ban
# count. Vanilla resolves each banned id against the item catalogue only, so a banned weapon —
# which vanilla can already produce from an item box, and which "Ban weapons too" adds to the shop
# — is silently missing from both. The ids it could not resolve are looked up in the weapon
# catalogue here and appended.
func get_player_banned_items(player_index: int) -> Array:
	var banned := .get_player_banned_items(player_index)

	var tweaks = _tweaks()
	if tweaks == null or not tweaks.bans_cover_weapons():
		return banned
	if player_index == DUMMY_PLAYER_INDEX or player_index >= players_data.size():
		return banned

	for item_id in players_data[player_index].banned_items:
		var id_hash: int = Keys.generate_hash(item_id) if item_id is String else int(item_id)
		if ItemService.is_item_id(id_hash):
			continue
		var weapon = ItemService.get_element(ItemService.weapons, id_hash)
		if weapon != null:
			banned.append(weapon)

	return banned


# --- the endless harvesting decay ------------------------------------------------------------

# Past `nb_of_waves`, `main.gd::_on_HarvestingTimer_timeout()` takes
# `ceil(harvesting * ENDLESS_HARVESTING_DECREASE / 100)` off the Harvesting stat at the end of
# every wave, and that one line is the whole decay. `ENDLESS_HARVESTING_DECREASE` is a constant
# and the branch it sits in cannot be reached any other way, so the removal itself is the seam.
#
# Skipped rather than added back afterwards. `FloatingTextManager` listens to `stat_removed` *and*
# `stat_added`, so undoing the decay would print "-12 harvesting" and "+12 harvesting" over the
# player, one after the other, every wave.
#
# Narrow enough to be safe as a blanket rule: the harvesting stat is removed nowhere else in
# vanilla. The only other caller of this method that can name an arbitrary stat is
# `Utils.convert_stats()`, and the two conversions the game ships convert ranged damage — which is
# temporary, so it goes to `TempStats.remove_stat()` — and materials, which goes through
# `remove_gold()`. The wave check is still made first, so nothing outside endless is affected
# either way.
#
# The key comparison comes before the group lookup so an ordinary `remove_stat()` costs one
# integer compare.
func remove_stat(stat_hsh: int, value: int, player_index: int) -> void:
	if stat_hsh == Keys.stat_harvesting_hash and current_wave > nb_of_waves:
		var tweaks = _tweaks()
		if tweaks != null and tweaks.keep_harvesting():
			tweaks.report_harvesting_kept(value)
			return

	.remove_stat(stat_hsh, value, player_index)


# --- the item limits -------------------------------------------------------------------------

# The other half of the two "no limit" tweaks. `ItemService.get_limited_items()` is what stops a
# capped item being *offered* again; this is the same cap read for the other question the game asks
# of it — how many copies a duplicating item may still make — and lifting one without the other
# would leave a Duplicator refusing to clone an item the shop is happily selling you a third of.
#
# `Utils.LARGE_NUMBER` rather than a number of this mod's own: it is exactly what vanilla answers
# for an item that has no cap at all, so every caller is on a path it already had.
func get_remaining_max_nb_item(item_data: ItemData, player_index: int) -> int:
	if item_data != null:
		var tweaks = _tweaks()
		if tweaks != null and tweaks.item_limit_lifted(item_data.max_nb):
			return Utils.LARGE_NUMBER

	return .get_remaining_max_nb_item(item_data, player_index)


# --- the weapon limit ----------------------------------------------------------------------

# Two effects, and only two. `weapon_slot` is what every screen prints as "(2/6)" and what
# `ItemService.get_upgrades()` compares against; `weapon_slot_upgrades` is the target a character
# that gains slots on level-up is climbing towards, capped so it can never sit above the limit.
# Every other key is handed back exactly as vanilla answered it, after two integer comparisons.
func get_player_effect(key: int, player_index: int):
	var vanilla = .get_player_effect(key, player_index)
	if key != Keys.weapon_slot_hash and key != Keys.weapon_slot_upgrades_hash:
		return vanilla

	var limit := _tweaks_weapon_limit()
	if limit < 0:
		return vanilla
	if key == Keys.weapon_slot_hash:
		return limit
	return int(min(int(vanilla), limit))


# Vanilla reads the effect dictionary directly here rather than going through
# `get_player_effect()`, so the override above does not reach it.
func get_free_weapon_slots(player_index: int) -> int:
	var limit := _tweaks_weapon_limit()
	if limit < 0:
		return .get_free_weapon_slots(player_index)

	var tweaks = _tweaks()
	return tweaks.free_weapon_slots(get_player_weapons_ref(player_index).size())


# The shop's "does another weapon fit" question, and the same direct dictionary read. This one is
# not answered from the limit but asked *with* it: the vanilla rules that go with a weapon slot —
# no duplicates for characters that forbid them, the melee and ranged sub-limits — are worth
# keeping, and they are a dozen lines that would have to be copied to reimplement one number. So
# the effect is set to the limit for the length of the vanilla call and put back afterwards.
func has_weapon_slot_available(shop_weapon: WeaponData, player_index: int) -> bool:
	var limit := _tweaks_weapon_limit()
	if limit < 0:
		return .has_weapon_slot_available(shop_weapon, player_index)

	var effects := get_player_effects(player_index)
	if not effects.has(Keys.weapon_slot_hash):
		return .has_weapon_slot_available(shop_weapon, player_index)

	var previous = effects[Keys.weapon_slot_hash]
	effects[Keys.weapon_slot_hash] = limit
	var available := .has_weapon_slot_available(shop_weapon, player_index)
	effects[Keys.weapon_slot_hash] = previous
	return available


# The one moment a run can begin over the limit. The weapon the player chose on the selection
# screen is added first, by `WeaponSelection._on_selections_completed()`; this is what adds the
# ones the character brings of its own. Anything past the limit is dropped from the back, so the
# player's own pick is the one that survives a limit of 1.
#
# `remove_weapon_by_index()` rather than `remove_weapon()`: the latter matches by weapon rather
# than by position and would drop the first equivalent one, which with two of the same weapon is
# not the one that put the loadout over.
func add_starting_items_and_weapons() -> void:
	.add_starting_items_and_weapons()

	var tweaks = _tweaks()
	if tweaks == null:
		return

	for player_index in players_data.size():
		var weapons := get_player_weapons_ref(player_index)
		var overflow: int = tweaks.weapon_overflow(weapons.size())
		for _i in overflow:
			if weapons.empty():
				break
			var _tracked = remove_weapon_by_index(weapons.size() - 1, player_index)


# -1 when the tweak is off or the mod is not mounted yet, which is the same answer: leave vanilla
# alone.
func _tweaks_weapon_limit() -> int:
	var tweaks = _tweaks()
	if tweaks == null:
		return -1
	return tweaks.weapon_limit()


# Never returns null, and returns its argument unchanged whenever the mod is not mounted yet,
# the feature is off, or the curse system is unavailable.
func _tweaks_curse(data, player_index: int, is_weapon: bool):
	var tweaks = _tweaks()
	if tweaks == null:
		return data
	var result = tweaks.curse_data(data, player_index, is_weapon)
	return data if result == null else result


func _tweaks():
	if _tweaks_node != null and is_instance_valid(_tweaks_node):
		return _tweaks_node
	if not is_inside_tree():
		return null
	var found := get_tree().get_nodes_in_group(TWEAKS_GROUP)
	if found.empty() or not is_instance_valid(found[0]):
		return null
	_tweaks_node = found[0]
	return _tweaks_node
