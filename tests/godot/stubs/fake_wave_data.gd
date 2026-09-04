extends Resource

# Stands in for WaveData (res://zones/wave_data.gd), carrying only the fields the mod reads.
#
# `export` rather than plain `var`, and a top-level script rather than an inner class, because the
# real one is both — and the difference is not cosmetic: `Resource.duplicate()` copies properties
# with storage usage, and a plain `var` on an inner class does not get it. A stub that used plain
# vars made `duplicate()` silently drop the array, which is the opposite of the bug a harness
# should invent.

export (int) var max_enemies = 100
export (int) var wave_duration = 60
export (Array, Resource) var groups_data
