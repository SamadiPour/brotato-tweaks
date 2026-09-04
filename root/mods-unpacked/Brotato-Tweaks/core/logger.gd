extends Reference

# Thin wrapper over ModLoaderLog so every line carries the mod id.
#
# ModLoaderLog is a `class_name` static class, not an autoload: only its own static methods
# may be called on it. Naming an Object instance method on it — `has_method`, `call` — is a
# *parse* error, which fails this script, everything that preloads it, and with it the mod.
# So the level is dispatched by hand rather than by reflection.

const LOG_NAME := "Brotato-Tweaks"


static func info(message: String) -> void:
	_write("info", message)


static func success(message: String) -> void:
	_write("success", message)


static func warning(message: String) -> void:
	_write("warning", message)


static func error(message: String) -> void:
	_write("error", message)


static func _write(level: String, message: String) -> void:
	match level:
		"success":
			ModLoaderLog.success(message, LOG_NAME)
		"warning":
			ModLoaderLog.warning(message, LOG_NAME)
		"error":
			ModLoaderLog.error(message, LOG_NAME)
		_:
			ModLoaderLog.info(message, LOG_NAME)
