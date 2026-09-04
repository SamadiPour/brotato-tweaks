extends SceneTree

# Compiles every script in the mod except the adapters.
#
# extensions/ is skipped on purpose: those scripts `extends` a res:// path that only exists
# inside the game, so nothing here can load them. tests/run_extensions.sh compiles them against
# the decompiled game instead.
#
# load() still hands back a GDScript that failed to compile, so can_instance() is what tells the
# difference.

const MOD_ROOT := "res://mods-unpacked/Brotato-Tweaks"
const SKIP_DIR := "/extensions"


func _initialize() -> void:
	var paths := []
	_collect(MOD_ROOT, paths)

	var failed := 0
	for path in paths:
		var script = load(path)
		if script == null or not script.can_instance():
			print("PARSE FAIL: ", path)
			failed += 1
		else:
			print("ok: ", path)

	print("---- ", paths.size() - failed, "/", paths.size(), " scripts parsed")
	quit(1 if failed > 0 else 0)


func _collect(dir_path: String, out: Array) -> void:
	if dir_path.ends_with(SKIP_DIR):
		print("skipped (needs the game): ", dir_path)
		return

	var dir := Directory.new()
	if dir.open(dir_path) != OK:
		return

	dir.list_dir_begin(true, true)
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path + "/" + entry
		if dir.current_is_dir():
			_collect(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
