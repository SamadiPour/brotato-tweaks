extends HBoxContainer

# A copy of vanilla's `res://ui/menus/global/slider_option.tscn` script, at the path the game keeps
# it, so the settings tab can be built headless.
#
# Copied rather than approximated, because the two things the tab does to it are the two things
# that could quietly stop working: it reaches `_slider`, `_label` and `_value`, which are `onready`
# and therefore null until the option is in the tree; and it disconnects
# `HSlider.value_changed -> _on_HSlider_value_changed`, whose whole body is the percentage
# rendering the mod's dials must not get.

signal value_changed(value)

onready var _label = $Label
onready var _slider = $HSlider
onready var _value = $Value


func _ready() -> void:
	_value.text = str(_slider.value * 100) + "%"


func set_value(value: float) -> void:
	_slider.value = value
	_on_HSlider_value_changed(value)


func _on_HSlider_value_changed(value: float) -> void:
	_value.text = str(value * 100) + "%"
	emit_signal("value_changed", value)
