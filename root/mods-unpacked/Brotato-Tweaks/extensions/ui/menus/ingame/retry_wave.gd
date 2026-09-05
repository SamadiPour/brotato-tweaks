extends "res://ui/menus/ingame/retry_wave.gd"

# Adapter: Death Guard.
#
# `Main._on_EndWaveTimer_timeout()` shows this screen whenever a wave was failed, whatever the
# player's Options say. What the Options toggle decides is only which half of it is visible: the
# retry prompt, or a lone OK button that ends the run. So Death Guard's whole job on screen is to
# make the retry half visible — the restart behind the confirm button is vanilla's, untouched, and
# vanilla offers it without limit.
#
# `show()` is hooked rather than `_ready()`. Vanilla's `_ready()` reads the Options setting, and
# an extension that redefined it could not call the base version without running it twice; `show()`
# is called every time the screen appears, which is also the only moment the setting can have
# changed. Vanilla runs first, so its focus grab happens before this one replaces it.
#
# The retry line is written here because vanilla writes it only when its own Options toggle is on.
# `RunData.retries` is the game's own counter, incremented by the vanilla confirm button and saved
# with the run, so the number shown is the same one the end-run screen and the difficulty score
# report.
#
# Nothing here is undone. When the feature is off, or when any of the nodes below is missing, the
# screen is left exactly as vanilla drew it — including the vanilla retry prompt, if the player
# turned that on themselves. This adapter only ever adds the offer.
#
# See docs/01-architecture.md ("Extension points").

const TweaksLookup = preload("res://mods-unpacked/Brotato-Tweaks/core/tweaks_lookup.gd")
const TWEAKS_FEATURE := "death_guard"

var _tweaks_disabled := false


func show() -> void:
	.show()
	_tweaks_offer_retry()


func _tweaks_offer_retry() -> void:
	if _tweaks_disabled:
		return

	var tweaks = _tweaks()
	if tweaks == null:
		return

	if not tweaks.feature_enabled(TWEAKS_FEATURE):
		return

	if not is_instance_valid(_retry_wave_container) or not is_instance_valid(_confirm_button):
		_tweaks_disabled = true
		tweaks.disable_feature(TWEAKS_FEATURE, "the retry screen has no Retry_WaveContainer or ConfirmButton")
		return

	_retry_wave_container.visible = true
	if is_instance_valid(_ok_button):
		_ok_button.visible = false

	# Vanilla's own localised line, which vanilla itself writes only when its Options toggle is on.
	if is_instance_valid(_label_number_retry):
		_label_number_retry.text = Text.text("RETRY_NUMBER", [str(RunData.retries)])

	_confirm_button.grab_focus()


func _tweaks():
	return TweaksLookup.find(self)
