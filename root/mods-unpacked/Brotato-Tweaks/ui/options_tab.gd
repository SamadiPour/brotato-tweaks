extends Reference

# Puts the mod's settings screen into the game's Options menu, as a fifth tab beside Audio, Visual,
# Gameplay and Accessibility. Both adapters that reach an Options menu — the title screen's and the
# pause menu's — are three lines each and call `attach()`; everything they would otherwise both
# have to say correctly is here once.
#
# The seam is `res://ui/hud/ui_better_tab_container.gd`, the `Buttons` node inside `MenuOptions`:
#
#     export (Array, NodePath) var buttons_tab_np
#     onready var tab_container: TabContainer = get_node(tab_container_np)
#     var buttons_tab: Array
#     func _change_tab(actual_tab: int)
#
# A tab is a button in the strip, its NodePath in `buttons_tab_np`, the button itself in
# `buttons_tab`, and a child of `tab_container` at the same index. Add all four and the tab is a
# real one: shoulder buttons cycle to it, the button group makes it exclusive, and the game's own
# theme and focus sounds come with it.
#
# Three things this does that Brotato Mod Options' version of the same trick does not:
#
#   * the new tab's index is `buttons_tab_np.size()` rather than a count of the strip's children,
#     so it is right whatever else has already added a tab;
#   * the button is duplicated *without* its signals, so it opens this tab rather than the one it
#     was copied from;
#   * the tab's own layout is copied off the tab already there, so a patch that restyles the
#     Options menu restyles this with it.
#
# Nothing here is undone on failure past the point of no return, because there is none: the tab and
# its button are added last, together, and any check that fails before then leaves the Options menu
# exactly as vanilla built it.
#
# See docs/01-architecture.md ("The settings tab").

const Layout := preload("../core/settings_layout.gd")

const GROUP := "brotato_tweaks"
const FEATURE := "settings_tab"

const TAB_SCRIPT := "res://mods-unpacked/Brotato-Tweaks/ui/tweaks_tab.gd"
const TAB_ICON := "res://ui/menus/global/mods_icon.png"

const CONTROLLER_NAME := "Buttons"
const BUTTON_NAME := "Tweaks_but"
const TAB_NAME := "Tweaks_Container"
const BUTTON_TEXT := "Tweaks"

const COPIED_PROPERTIES := [
	"anchor_right",
	"anchor_bottom",
	"margin_top",
	"size_flags_horizontal",
	"size_flags_vertical",
	"follow_focus",
	"scroll_horizontal_enabled",
	"focus_neighbour_top",
	"focus_neighbour_bottom",
	"focus_next",
	"focus_previous",
]


# `page` is the screen that owns an Options menu; `options_path` is where it keeps it. Silent when
# the mod is not mounted or the tab has already given up — one failure disables it for the session,
# so a broken title screen does not try the same thing again from the pause menu.
func attach(page: Node, options_path: String) -> void:
	if page == null or not is_instance_valid(page) or not page.is_inside_tree():
		return

	var tweaks = _tweaks(page)
	if tweaks == null:
		return
	if tweaks.disabled_features.has(FEATURE):
		return

	var reason := _mount(page.get_node_or_null(options_path), tweaks)
	if reason != "":
		tweaks.disable_feature(FEATURE, reason)


# "" means mounted, or already mounted on this screen. Anything else is why not.
func _mount(menu_options, tweaks) -> String:
	if menu_options == null or not is_instance_valid(menu_options):
		return "this screen has no Options menu where one was expected"

	var controller = menu_options.get_node_or_null(CONTROLLER_NAME)
	if controller == null or not is_instance_valid(controller):
		return "the Options menu has no Buttons node"
	if not ("buttons_tab_np" in controller) or not ("buttons_tab" in controller) \
			or not ("tab_container" in controller):
		return "the Options menu's Buttons node is no longer a UIBetterTabContainer"

	var tabs = controller.tab_container
	var paths: Array = controller.buttons_tab_np
	if not is_instance_valid(tabs) or tabs.get_child_count() == 0 or paths.empty():
		return "the Options menu has no tab to copy"

	var template = controller.get_node_or_null(paths[paths.size() - 1])
	if template == null or not is_instance_valid(template) or not is_instance_valid(template.get_parent()):
		return "the Options menu's last tab button is missing"

	var strip = template.get_parent()
	# The two adapters mount into different scenes, but a scene the game rebuilds could reach this
	# twice. One tab is enough.
	if strip.has_node(BUTTON_NAME):
		return ""

	var sections := Layout.build(tweaks.get_schema_properties(), tweaks.settings)
	if sections.empty():
		return "the config schema declares nothing this screen can draw"

	var script = load(TAB_SCRIPT)
	if script == null:
		return "the settings tab script is missing"

	var tab = script.new()
	tab.name = TAB_NAME
	_copy_layout(tabs.get_child(0), tab)
	tabs.add_child(tab)

	if not tab.set_sections(sections, tweaks.schema_description()):
		tabs.remove_child(tab)
		tab.queue_free()
		return "the game no longer has the slider this screen is built from"

	tab.connect("setting_changed", tweaks, "set_setting")
	tab.connect("reset_requested", tweaks, "reset_to_defaults")
	# Anything else that writes a setting — Mod Options, another screen of this one — moves these
	# widgets too. Godot drops the connection when the tab is freed with its scene.
	tweaks.connect("settings_changed", tab, "apply_settings")
	tab.apply_settings(tweaks.settings)

	_add_button(controller, strip, template, paths.size())
	return ""


# The button is a copy of a tab button already there, so it carries the game's theme, its focus
# sounds and its press behaviour and stays right when a patch restyles them. Groups and script are
# copied; signals deliberately are not, because the original's `pressed` opens the tab it belongs
# to and a copy carrying that would open two at once.
func _add_button(controller, strip, template, index: int) -> void:
	var button = template.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
	button.name = BUTTON_NAME
	button.text = BUTTON_TEXT
	button.toggle_mode = true
	button.pressed = false
	# The group is what makes the tab buttons exclusive; a duplicate gets the property but must be
	# put in the same group instance as the rest.
	button.group = template.group
	# Scene-unique names are per scene, and a copy of a `unique_name_in_owner` button would shadow
	# the one vanilla looks up. Ignored on an engine build with no such property.
	button.set("unique_name_in_owner", false)

	var icon = load(TAB_ICON)
	if icon != null:
		button.icon = icon

	strip.add_child(button)
	strip.move_child(button, template.get_index() + 1)

	# In the tree before `get_path()`, and in `buttons_tab_np` before the signal can fire.
	button.connect("pressed", controller, "_change_tab", [index])
	controller.buttons_tab_np.push_back(button.get_path())
	controller.buttons_tab.push_back(button)


func _copy_layout(template, tab) -> void:
	if template == null or not is_instance_valid(template):
		return
	for property in COPIED_PROPERTIES:
		var value = template.get(property)
		if value != null:
			tab.set(property, value)


func _tweaks(page: Node):
	var tree := page.get_tree()
	if tree == null:
		return null
	var found := tree.get_nodes_in_group(GROUP)
	if found.empty() or not is_instance_valid(found[0]):
		return null
	return found[0]
