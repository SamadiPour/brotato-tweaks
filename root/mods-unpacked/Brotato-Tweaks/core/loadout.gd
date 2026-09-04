extends Reference

# Pure: the arithmetic behind the two tweaks that change what a player is allowed to carry into a
# run — how many ban tokens they get, and how many weapons they may hold.
#
# Neither is a rule the game exposes as a number this mod can set once. Bans are a constant
# (`RunData.BAN_MAX_TOKEN`) copied into every player at run start; the weapon limit is an *effect*
# (`Keys.weapon_slot_hash`) that characters, items and level-ups all add to. So both tweaks are
# adapters answering the game's own questions with a number from here, and everything that can be
# decided without naming a game class is decided in this file.
#
# `apply_ban_tokens()` writes into the caller's player data because there is nothing else it could
# do: the game keeps the count on `PlayerRunData` and decrements it as bans are spent. It touches
# three fields, by name, on whatever it is handed — the stub in tests/godot/stubs/fake_player.gd is
# the same shape as the vanilla resource for exactly that reason.


# How many weapons still fit. Never negative: over the limit is "none fit", not "minus two".
static func free_slots(limit: int, held: int) -> int:
	return int(max(0, limit - held))


# How many weapons are over the limit and have to go. The mirror of free_slots().
static func excess(limit: int, held: int) -> int:
	return int(max(0, held - limit))


# What a player's remaining ban tokens should be, given the bans they have already spent. Written
# as "allowance minus spent" rather than as a starting number so it is the same answer whenever it
# is asked — at run start, and again on any later call — and so lowering the allowance mid-run
# cannot hand back a ban that was already used.
static func remaining_bans(allowance: int, spent: int) -> int:
	return int(max(0, allowance - spent))


# The other half of the same sum, for the one screen that shows bans as "spent / allowance"
# (`UpgradesUIPlayerContainer.show_item()`). Kept here so the label and the token count cannot
# disagree.
static func spent_bans(allowance: int, remaining: int) -> int:
	return int(clamp(allowance - remaining, 0, max(0, allowance)))


# Gives every player their ban allowance and turns ban mode on for them, and returns how many
# players it reached. Ban mode is part of it: `RunData.is_ban_active_in_current_run()` reads
# `uses_ban` on player 0, and a run started with the vanilla toggle off shows no ban button at all
# — an allowance nobody can spend.
#
# Anything that is not shaped like a PlayerRunData is skipped rather than being a crash, because
# this runs on a vanilla array whose shape is the game's to change.
static func apply_ban_tokens(players_data: Array, player_count: int, allowance: int) -> int:
	var applied := 0
	var count: int = int(min(player_count, players_data.size()))

	for player_index in count:
		var data = players_data[player_index]
		if data == null:
			continue
		if not ("remaining_ban_token" in data) or not ("banned_items" in data) or not ("uses_ban" in data):
			continue

		var spent: int = data.banned_items.size() if data.banned_items is Array else 0
		data.uses_ban = true
		data.remaining_ban_token = remaining_bans(allowance, spent)
		applied += 1

	return applied
