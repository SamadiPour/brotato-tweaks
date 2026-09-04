extends "res://ui/menus/title_screen/title_screen.gd"

# Adapter: the settings tab, reached from the title screen's Options.
#
# `_ready()` is defined without a base call, as everywhere else: Godot calls every `_ready()` in
# the script chain, base first, so `MenuOptions` and the `UIBetterTabContainer` inside it have
# already built themselves by the time this runs. That ordering is the whole reason the tab can be
# appended rather than declared.
#
# The work is in `ui/options_tab.gd`, which the pause menu's adapter calls the same way. It is
# reached with `load()` and not `preload()`, because an adapter is compiled outside the game by
# tests/run_extensions.sh, where `res://mods-unpacked` is not mounted.
#
# See docs/01-architecture.md ("The settings tab").

const TWEAKS_MOUNT := "res://mods-unpacked/Brotato-Tweaks/ui/options_tab.gd"
const TWEAKS_OPTIONS_PATH := "Menus/MenuOptions"


func _ready() -> void:
	var mount = load(TWEAKS_MOUNT)
	if mount == null:
		return
	mount.new().attach(self, TWEAKS_OPTIONS_PATH)
