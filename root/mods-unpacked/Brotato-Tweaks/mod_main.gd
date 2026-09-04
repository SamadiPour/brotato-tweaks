extends Node

# Entry point. Two jobs, in this order:
#   _init()  -> install the script extensions, before the game has built any of its scenes
#   _ready() -> mount the Tweaks node the extensions ask their questions of
#
# One extension per seam, and each is installed only if its file is there, so a missing or broken
# adapter costs its own feature and nothing else. See docs/01-architecture.md.

const MOD_ID := "Brotato-Tweaks"

# Paths are relative to the mod directory and mirror the vanilla tree exactly. The order here is not
# load-bearing: three of these do inherit from a fourth — vanilla's `Shop` and `CoopShop` both extend
# `BaseShop` — and ModLoader sorts every queued extension by its inheritance chain before it installs
# any of them.
const SCRIPT_EXTENSIONS := [
	"extensions/global/entity_spawner.gd",
	"extensions/main.gd",
	"extensions/singletons/entity_service.gd",
	"extensions/singletons/item_service.gd",
	"extensions/singletons/run_data.gd",
	"extensions/singletons/zone_service.gd",
	"extensions/ui/menus/ingame/pause_menu.gd",
	"extensions/ui/menus/ingame/retry_wave.gd",
	"extensions/ui/menus/ingame/upgrades_ui_player_container.gd",
	"extensions/ui/menus/run/difficulty_selection/difficulty_selection.gd",
	"extensions/ui/menus/shop/base_shop.gd",
	"extensions/ui/menus/shop/coop_shop.gd",
	"extensions/ui/menus/shop/item_popup.gd",
	"extensions/ui/menus/shop/shop.gd",
	"extensions/ui/menus/shop/shop_item.gd",
	"extensions/ui/menus/title_screen/title_screen.gd",
	"extensions/zones/wave_manager.gd",
]

var mod_dir := ""


func _init() -> void:
	mod_dir = ModLoaderMod.get_unpacked_dir() + MOD_ID + "/"
	for relative_path in SCRIPT_EXTENSIONS:
		var path: String = mod_dir + relative_path
		if _file_exists(path):
			ModLoaderMod.install_script_extension(path)


func _ready() -> void:
	var tweaks = load(mod_dir + "tweaks.gd").new()
	tweaks.name = "Tweaks"
	add_child(tweaks)


func _file_exists(path: String) -> bool:
	var file := File.new()
	return file.file_exists(path)
