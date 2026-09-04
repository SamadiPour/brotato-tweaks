extends Reference

# All Cursed: curse whatever the player picks up.
#
# The curse itself is not reimplemented. `res://dlcs/dlc_1/dlc_1_data.gd` — the Abyssal Terrors
# DLC resource — owns `curse_item(item_data, player_index, turn_randomization_off := false,
# min_modifier := 0.0)`, which duplicates the item, boosts every effect it knows how to boost,
# adds the `stat_curse` the item is worth, sets `is_cursed` and returns the copy. Vanilla calls
# it from the shop, from cursed starting gear and from the debug menu. This mod calls the same
# method, with the same two-argument form the debug menu uses, so a cursed item made here is
# indistinguishable from one the DLC made itself — including the curse it charges you.
#
# Which means the whole feature is one decision: *when* to call it. This mod calls it from two
# seams, because neither one covers the other:
#
#   - `ItemService.apply_item_effect_modifications()`, the last thing every rolled item passes
#     through and where vanilla itself rolls the natural curse chance. This is the shop's four
#     slots, every reroll, and a crate's item — cursed before the card is drawn, so what the
#     player reads is what they buy. `BaseShop.buy_item()` puts its own `item_data` into the gear
#     container rather than whatever `add_item()` stored, so a curse applied any later is a curse
#     the shop never showed.
#   - `RunData.add_item()` / `add_weapon()`, where every route into the inventory converges. That
#     is what is left over: starting gear, the character-selection weapon, a consumable's item, an
#     item another mod hands you.
#
# Nothing is cursed twice — `curse_item()` returns an already cursed item untouched, and the guard
# below saves even that call.
#
# Three things are never cursed:
#
#   - anything already cursed. `curse_item` returns it untouched anyway; this saves the call.
#   - characters. `CharacterSelection` adds the chosen `CharacterData` through `RunData.add_item()`
#     like an ordinary item, and a cursed character is not a thing the game has a concept of.
#   - level-up upgrades. Those reach neither seam — `UpgradesUI` gets them from
#     `ItemService.get_upgrade_data()`, which does not go through the item roll, and
#     `Main.on_upgrade_selected()` calls `RunData.apply_item_effects()` rather than `add_item()`.
#     So they are excluded by construction, not by a check. Worth knowing before someone goes
#     looking for the check.
#
# Without the DLC there is no curse system, and every call here returns its argument unchanged.
#
# Not pure: it reads ProgressData. Everything it reads is guarded, because a game patch that
# renames one of these is a patch this mod has to survive with the feature off, not with a crash.

const DLC_ID := "abyssal_terrors"


# The DLC resource, or null when the curse system is not available.
static func dlc_data():
	if not ProgressData.has_method("is_dlc_available_and_active"):
		return null
	if not ProgressData.is_dlc_available_and_active(DLC_ID):
		return null
	if not ProgressData.has_method("get_dlc_data"):
		return null

	var data = ProgressData.get_dlc_data(DLC_ID)
	if data == null or not data.has_method("curse_item"):
		return null
	return data


static func available() -> bool:
	return dlc_data() != null


# Returns a cursed duplicate, or the argument itself when it cannot or must not be cursed.
# Never returns null: every caller passes the result straight into a typed vanilla parameter.
static func curse(data, player_index: int):
	if data == null:
		return data
	if data is CharacterData:
		return data
	if not ("is_cursed" in data) or data.is_cursed:
		return data

	var dlc = dlc_data()
	if dlc == null:
		return data

	var cursed = dlc.curse_item(data, player_index)
	if cursed == null:
		return data
	return cursed


# --- recursing ------------------------------------------------------------------------------

# Which of an already cursed item and a fresh roll of its original the shop slot should keep.
#
# `curse_item()` opens with `if item_data.is_cursed: return item_data`, so a cursed item can never
# be handed to it twice — which is why a cursed item locked in the shop keeps the numbers it was
# given for the rest of the run, however many times the shop is left. The curse it would have had
# is not a fixed thing: `_get_cursed_item_effect_modifier()` rolls
# `base + per_wave * min(20, wave - 1) + randi_range(-r, r)` per effect, so the same item cursed
# twice is two different items. Re-rolling is worth doing and can land worse than what it replaced.
#
# Nothing is un-cursed and nothing is rolled here. The adapter puts the *original* — `base`, the
# catalogue resource the cursed copy was made from — back through the game's own offer roll, which
# is the only "should this be cursed" decision in the game and already carries All Cursed on top of
# it. `rolled` is what came back. So a re-roll happens exactly as often as a brand new item of the
# same kind would arrive cursed, and there is no second chance to keep in step with the first.
#
# This is then the whole decision: a roll that came back cursed replaces the slot, and a roll that
# missed leaves the curse the slot already had. Missing must not un-curse it — an item cannot be
# offered a curse and lose one it has.
#
# `value` is not touched by the curse, so the shop price of a re-rolled item is the price it had.
#
# Returns `data` unchanged for every reason to do nothing: not cursed, a character, nothing rolled,
# a roll that missed, and — the one that matters — a roll that handed the original straight back,
# because returning `base` itself would put a session-lifetime catalogue resource into a shop slot.
#
# Pure, unlike the rest of this file: the DLC is on the far side of the roll the adapter already
# made, so there is nothing to look up here.
static func recurse(data, base, rolled):
	if data == null or base == null or rolled == null:
		return data
	if data is CharacterData:
		return data
	if not ("is_cursed" in data) or not data.is_cursed:
		return data
	if rolled == data or rolled == base:
		return data
	if not ("is_cursed" in rolled) or not rolled.is_cursed:
		return data
	return rolled


# --- cursed enemies ------------------------------------------------------------------------

# The other thing the DLC curses. `CurseSceneEffectBehavior._on_EntitySpawner_enemy_respawned()`
# rolls a chance off the players' Curse stat for every enemy that spawns, and on a hit calls its
# own `_curse_enemy(enemy, curse)`, which adds the curse effect behaviour and boosts the enemy's
# health, damage and speed. The whole decision is inside that one method, and the method is in the
# DLC pack, which is mounted long after script extensions are installed — so it cannot be extended.
#
# It does not have to be. The roll is driven by a signal this mod's own adapter can listen to as
# well, and the thing it calls on a hit is a method on a node reachable from that signal's
# connection list. So this feature is a second listener that rolls its own chance and calls the
# same method — one more cursed enemy, made the DLC's way, indistinguishable from the DLC's own.
#
# Nothing here re-implements the boost. If the DLC is not active there is no behaviour node to
# find, `behavior` is null, and every call below is a no-op.

# The file the DLC's per-enemy curse behaviour is defined in. Matched on rather than by class,
# because `CurseEnemyEffectBehavior` is a DLC `class_name`: naming it in this file would make the
# file fail to parse for anyone without Abyssal Terrors installed.
const ENEMY_CURSE_SCRIPT := "curse_enemy_effect_behavior.gd"


# Whether this enemy may still be cursed. Three questions, in the order that costs least:
#
#   * `can_be_cursed` is the game's own opt-out, and it is what keeps loot aliens out of this —
#     `looter.tscn` and `evil_mob.tscn` set it false, which is the same exclusion vanilla writes
#     as "not a Boss and not a loot alien". Bosses never reach here at all: `enemy_respawned` is
#     emitted only for `EntityType.ENEMY`.
#   * `dead` — an enemy culled by the wave's own enemy cap can still be handed to a listener.
#   * already cursed — the DLC's own listener runs first, so an enemy it just cursed must not be
#     cursed twice. A second `_curse_enemy()` would stack a second behaviour node and a second
#     health boost onto the same enemy.
static func can_curse_enemy(enemy) -> bool:
	if enemy == null:
		return false
	if not ("can_be_cursed" in enemy) or not enemy.can_be_cursed:
		return false
	if "dead" in enemy and enemy.dead:
		return false
	return not enemy_is_cursed(enemy)


# Whether the DLC's curse behaviour is already on this enemy. Enemies are pooled and reused, so
# this asks the node rather than remembering anything: `Entity.free_entity()` clears the effect
# behaviours and the outlines when an enemy goes back in the pool.
static func enemy_is_cursed(enemy) -> bool:
	if enemy == null or not ("effect_behaviors" in enemy):
		return false
	var behaviors = enemy.effect_behaviors
	if behaviors == null or not behaviors.has_method("get_children"):
		return false

	for behavior in behaviors.get_children():
		var script = behavior.get_script()
		if script != null and str(script.resource_path).ends_with(ENEMY_CURSE_SCRIPT):
			return true
	return false


# Curses one enemy through the DLC's own method. `behavior` is the DLC's CurseSceneEffectBehavior;
# `curse_value` is the players' summed Curse stat, which is what the DLC scales the health boost
# by. Returns whether it happened.
static func curse_enemy(enemy, behavior, curse_value: float) -> bool:
	if behavior == null or not behavior.has_method("_curse_enemy"):
		return false
	if not can_curse_enemy(enemy):
		return false

	behavior._curse_enemy(enemy, curse_value)
	return true
