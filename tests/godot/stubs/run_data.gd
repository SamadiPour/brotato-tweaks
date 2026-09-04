extends Node

# Stands in for the RunData autoload. Only one field of it is ever read — `retries`, the run's own
# retry count, which the Death Guard adapter shows on the wave-failed screen. The adapters are not
# compiled here (see parse_check.gd), so nothing in this harness reads it today; the autoload stays
# because the mod's cores are loaded against a project that has to look like the game's.

var retries := 0
