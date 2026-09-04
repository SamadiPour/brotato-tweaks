class_name ModLoaderLog
extends Object

# Shaped like the real one on purpose: ModLoaderLog is a `class_name` static class, not an
# autoload. Stubbing it as an autoload Node once hid a parse error that took the whole mod
# down in game — `has_method()` and `call()` are instance methods, and naming one on a
# class is a parse error, which the harness could not see while the stub was a Node.

static func info(m, n) -> void: print(n, ": ", m)
static func success(m, n) -> void: print(n, ": ", m)
static func warning(m, n) -> void: print(n, ": ", m)
static func error(m, n) -> void: print(n, ": ", m)
static func debug(m, n) -> void: print(n, ": ", m)
