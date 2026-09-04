extends "res://ui/menus/ingame/pause_menu.gd"

# Adapter: the settings tab, reached from the pause menu's Options.
#
# The same mount as the title screen's adapter, against the same `Menus/MenuOptions` path — the
# pause menu instances the very same scene. This one is why the tab exists rather than a page of
# its own: every tweak reads its setting at the moment it acts, so the wave a player is between is
# exactly when they want to move a dial.
#
# See extensions/ui/menus/title_screen/title_screen.gd for why `_ready()` has no base call and why
# the mount is loaded rather than preloaded.

const TWEAKS_MOUNT := "res://mods-unpacked/Brotato-Tweaks/ui/options_tab.gd"
const TWEAKS_OPTIONS_PATH := "Menus/MenuOptions"


func _ready() -> void:
	var mount = load(TWEAKS_MOUNT)
	if mount == null:
		return
	mount.new().attach(self, TWEAKS_OPTIONS_PATH)
