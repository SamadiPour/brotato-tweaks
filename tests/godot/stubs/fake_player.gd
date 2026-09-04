extends Reference

# Stands in for `PlayerRunData`, for the three fields core/loadout.gd writes.
#
# The real one is a Reference with a long list of plain `var`s; these three are declared the same
# way and with the same names, because `apply_ban_tokens()` finds them with `"name" in object` and
# a rename in either place has to fail a check here rather than in the game.

var uses_ban := false
var remaining_ban_token := 0
var banned_items := []
