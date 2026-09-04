extends ScrollContainer

# The mod's own settings screen — one tab in the game's Options menu, built in code from the same
# schema `manifest.json` declares.
#
# It renders what it is handed and reads nothing: no config, no ModLoader, no singleton.
# `set_sections()` builds the widgets, `apply_settings()` moves them, and every change leaves as
# `setting_changed(key, value)` for whoever mounted it to save. That is what keeps every decision
# in `tweaks.gd`, and what lets this file be opened by a harness with no game behind it.
#
# Widgets are the game's own: `slider_option.tscn` for numbers, a themed `CheckButton` for
# switches. Nothing here draws a control of its own, so the tab restyles itself with the game.
#
# Programmatic writes are wrapped in `set_block_signals()` rather than guarded by a flag. Both
# `SliderOption` and `MyHSlider` listen to the same `value_changed`, one to relabel and one to play
# a click, so blocking is the only way to move a slider without a sound and an echoed save.
#
# See docs/01-architecture.md ("The settings tab").

signal setting_changed(key, value)
signal reset_requested

const Layout := preload("../core/settings_layout.gd")

# Vanilla resources, loaded rather than preloaded: an extension of a vanilla script may be compiled
# outside the game (see tests/run_extensions.sh), and every one of these is optional to this file
# being *parsed*.
const SLIDER_SCENE := "res://ui/menus/global/slider_option.tscn"
# The game's own theme draws every row title at 40, so the heading has to be larger than that or it
# reads as a caption on the row under it rather than as the start of a section. 60 is the next size
# the game itself ships; 26, which this used to be, was smaller than the settings it introduced.
const FONT_HEADING := "res://resources/fonts/actual/base/font_60_outline.tres"
const FONT_SMALL := "res://resources/fonts/actual/base/font_smallest_text.tres"

const COLOR_HEADING := Color(0.941, 0.769, 0.098)
const COLOR_RULE := Color(0.941, 0.769, 0.098, 0.35)
const COLOR_MUTED := Color(0.66, 0.66, 0.66)

const INDENT_WIDTH := 48
const VALUE_WIDTH := 150
const RESET_TEXT := "Reset every tweak to its default"

# What separates a section from the one before it. A heading is three things at once — space above
# it, a bigger coloured line of text, and a rule under it — because any one of them alone is what
# the rows already have: rows are spaced, row titles are large, and the tab is full of horizontal
# widgets. Together they read as a break in the page.
const SECTION_SPACE := 44
const HEADING_RULE_GAP := 10
const HEADING_SPACE := 20
const RULE_HEIGHT := 3

# Between one feature and the next inside a section. A feature's dials sit right under its switch
# at the row separation, so this is what keeps a section from reading as one undivided list.
const BLOCK_SPACE := 22

# key -> {"row": Control, "spec": Dictionary, "widget": Node, "value_label": Label, "note": Label}
var _widgets := {}

# Everything this script added, in one node, so a rebuild frees exactly that and nothing else.
# A ScrollContainer's children are not all the caller's: the engine adds `h_scroll` and `v_scroll`
# in the constructor and keeps raw pointers to them, so a `for child in get_children(): free()`
# leaves it dereferencing freed memory on the next layout pass. That is a segfault, not an error —
# there is no message and no stack, and it lands one frame after the tab first becomes visible.
var _content: Control = null


# Builds the whole tab. False means a vanilla widget this screen is made of is gone, and the caller
# should leave the Options menu as it found it — see options_tab.gd.
func set_sections(sections: Array, intro: String = "") -> bool:
	var slider_scene = load(SLIDER_SCENE)
	if slider_scene == null:
		return false

	_widgets.clear()
	if _content != null and is_instance_valid(_content):
		remove_child(_content)
		_content.queue_free()
	_content = null

	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["left", "right", "top", "bottom"]:
		margin.set("custom_constants/margin_" + side, 30)
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(margin)
	_content = margin

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.set("custom_constants/separation", 14)
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	margin.add_child(rows)

	if intro != "":
		rows.add_child(_note_label(intro))

	# Only the very first heading on the page skips the space above it; one under the intro line
	# still needs it.
	var first_heading := intro == ""
	for section in sections:
		rows.add_child(_heading_block(str(section["title"]), first_heading))
		first_heading = false
		var first_row := true
		for spec in section["rows"]:
			if not _build_row(rows, spec, slider_scene, first_row):
				return false
			first_row = false

	var reset := Button.new()
	reset.name = "Reset"
	reset.text = RESET_TEXT
	reset.size_flags_horizontal = SIZE_SHRINK_CENTER
	reset.connect("pressed", self, "_on_reset_pressed")
	rows.add_child(_spaced_above(reset, SECTION_SPACE))

	return true


# Moves every widget to what `settings` says, and hides the sub-options whose feature is off.
# Safe to call at any time, including from the signal one of these widgets just caused.
func apply_settings(settings: Dictionary) -> void:
	for key in _widgets.keys():
		var entry: Dictionary = _widgets[key]
		var spec: Dictionary = entry.spec
		var row: Control = entry.row
		if not is_instance_valid(row):
			continue

		row.visible = Layout.row_visible(spec, settings)
		if not settings.has(key):
			continue

		var widget = entry.widget
		if not is_instance_valid(widget):
			continue

		widget.set_block_signals(true)
		if spec.kind == "bool":
			widget.pressed = bool(settings[key])
		else:
			var value := float(settings[key])
			widget.value = value
			_set_value_text(entry, value)
		widget.set_block_signals(false)


# --- building one row --------------------------------------------------------------------

# The row is put in the tree before anything is built into it. `SliderOption` reaches its three
# children through `onready` vars, which are assigned when it enters the tree and are null until
# then — so a row assembled first and mounted afterwards is a row of null widgets.
func _build_row(parent: Node, spec: Dictionary, slider_scene, first_in_section: bool) -> bool:
	var container := VBoxContainer.new()
	container.name = str(spec.key)
	container.set("custom_constants/separation", 2)
	container.size_flags_horizontal = SIZE_EXPAND_FILL

	var indented := str(spec.parent) != ""
	# The space goes above the next switch, never between a switch and the dials it owns, so a
	# feature reads as one block. The first row of a section already has the heading above it.
	var mounted: Control = container
	if not indented and not first_in_section:
		mounted = _spaced_above(container, BLOCK_SPACE)
	parent.add_child(mounted)

	var line := HBoxContainer.new()
	line.size_flags_horizontal = SIZE_EXPAND_FILL
	container.add_child(_indented(line, indented))

	# `row` is what `apply_settings()` hides, so it is the outermost node — hiding the container
	# inside its spacer would leave the spacer's own height behind as a gap.
	var entry := {"row": mounted, "spec": spec, "widget": null, "value_label": null}

	if spec.kind == "bool":
		if not _build_bool(line, spec, entry):
			return false
	elif not _build_number(line, spec, entry, slider_scene):
		return false

	var description := str(spec.description)
	if description != "":
		container.add_child(_indented(_note_label(description), indented))

	_widgets[str(spec.key)] = entry
	return true


func _build_bool(line: HBoxContainer, spec: Dictionary, entry: Dictionary) -> bool:
	var label := Label.new()
	label.text = str(spec.title)
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.autowrap = true
	line.add_child(label)

	var check := CheckButton.new()
	check.pressed = bool(spec.value)
	check.connect("toggled", self, "_on_toggled", [str(spec.key)])
	line.add_child(check)

	entry["widget"] = check
	return true


# `SliderOption` exposes its three children as `onready` vars, so they exist only once it is in the
# tree — everything below the add_child() is in that order for that reason.
func _build_number(line: HBoxContainer, spec: Dictionary, entry: Dictionary, slider_scene) -> bool:
	var option = slider_scene.instance()
	if option == null:
		return false
	option.size_flags_horizontal = SIZE_EXPAND_FILL
	line.add_child(option)

	if not ("_slider" in option) or not ("_label" in option) or not ("_value" in option):
		return false

	var slider = option._slider
	var value_label = option._value
	if not is_instance_valid(slider) or not is_instance_valid(value_label):
		return false

	option._label.text = str(spec.title)
	value_label.rect_min_size = Vector2(VALUE_WIDTH, 0)

	# Vanilla's own handler writes `str(value * 100) + "%"`, which is right for the three audio
	# sliders it was written for and wrong for every dial in this mod.
	if slider.is_connected("value_changed", option, "_on_HSlider_value_changed"):
		slider.disconnect("value_changed", option, "_on_HSlider_value_changed")

	slider.set_block_signals(true)
	slider.min_value = float(spec.minimum)
	slider.max_value = float(spec.maximum)
	slider.step = float(spec.step)
	slider.value = float(spec.value)
	slider.set_block_signals(false)

	slider.connect("value_changed", self, "_on_slider_changed", [str(spec.key)])

	entry["widget"] = slider
	entry["value_label"] = value_label
	_set_value_text(entry, float(spec.value))
	return true


# --- what the widgets report --------------------------------------------------------------

func _on_toggled(pressed: bool, key: String) -> void:
	emit_signal("setting_changed", key, pressed)


func _on_slider_changed(value: float, key: String) -> void:
	if _widgets.has(key):
		_set_value_text(_widgets[key], value)
	emit_signal("setting_changed", key, value)


func _on_reset_pressed() -> void:
	emit_signal("reset_requested")


# --- odds and ends -------------------------------------------------------------------------

func _set_value_text(entry: Dictionary, value: float) -> void:
	var label = entry.get("value_label")
	if label == null or not is_instance_valid(label):
		return
	label.text = Layout.format_value(str(entry.spec.key), value)


# A sub-option is set in from the toggle it belongs to, so the two read as one block rather than as
# two settings that happen to be next to each other. Godot has no margin on a plain Control, so the
# indent is a spacer — the same thing vanilla's own `empty_space_left` is.
func _indented(control: Control, indented: bool) -> Control:
	if not indented:
		return control
	var line := HBoxContainer.new()
	line.size_flags_horizontal = SIZE_EXPAND_FILL
	var spacer := Control.new()
	spacer.rect_min_size = Vector2(INDENT_WIDTH, 0)
	line.add_child(spacer)
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	line.add_child(control)
	return line


# A section header: space, the title, a rule, then space again before the first row. `first` is the
# heading at the very top of the page, which has nothing above it to be separated from.
func _heading_block(text: String, first: bool) -> Control:
	var box := VBoxContainer.new()
	box.set("custom_constants/separation", HEADING_RULE_GAP)
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_child(_heading_label(text))
	box.add_child(_rule())

	var margin := MarginContainer.new()
	margin.name = "Heading"
	margin.set("custom_constants/margin_top", 0 if first else SECTION_SPACE)
	margin.set("custom_constants/margin_bottom", HEADING_SPACE)
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	margin.add_child(box)
	return margin


func _heading_label(text: String) -> Label:
	var label := Label.new()
	# Upper case because the heading font is the size of a row title: the case is what says this
	# line is a header and not another setting, before the colour or the rule are read.
	label.text = text.to_upper()
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	var font = load(FONT_HEADING)
	if font != null:
		label.set("custom_fonts/font", font)
	label.set("custom_colors/font_color", COLOR_HEADING)
	return label


# Under the heading, the width of the tab. A `ColorRect` rather than an `HSeparator` because a
# separator is drawn by the theme's stylebox, and the game's own is a 128x32 texture with two bolt
# heads on it — right once at the top of the Options menu, and much too loud repeated per section.
func _rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = COLOR_RULE
	rule.rect_min_size = Vector2(0, RULE_HEIGHT)
	rule.size_flags_horizontal = SIZE_EXPAND_FILL
	return rule


# `control` with empty space above it. Godot 3 has no margin on a plain Control, so the space is a
# container that has one — the same reason `_indented()` is a spacer node.
func _spaced_above(control: Control, space: int) -> Control:
	var margin := MarginContainer.new()
	margin.set("custom_constants/margin_top", space)
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	margin.add_child(control)
	return margin


func _note_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap = true
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	var font = load(FONT_SMALL)
	if font != null:
		label.set("custom_fonts/font", font)
	label.set("custom_colors/font_color", COLOR_MUTED)
	return label
