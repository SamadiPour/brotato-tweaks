extends Node

# Stands in for the ModLoaderStore autoload. The mod reads one field from it: whether a user
# profile exists, which decides whether making a config current is a profile write or an engine
# error. Null here, which is the case the guard is for.

var current_user_profile = null
