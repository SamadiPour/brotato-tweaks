extends Reference

# ModLoader's own `ModConfig`, cut down to the four fields core/settings_store.gd reads off one.
#
# `name` is what tells `default.json` from `user.json` and is the whole of the store's "is this the
# file the loader regenerates" test; `mod_id` is what `current_config_changed` is filtered on;
# `data` is the settings themselves and `schema` the manifest's `config_schema`.
#
# A Reference rather than a Resource: the real one is a Resource, but nothing here duplicates or
# saves the config object itself — only `data`, which is a plain Dictionary either way.

var name := ""
var mod_id := ""
var data := {}
var schema := {}
