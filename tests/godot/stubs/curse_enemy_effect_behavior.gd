extends Node

# Stands in for the DLC's `CurseEnemyEffectBehavior`, the node it adds to an enemy it curses.
#
# Its *file name* is the whole stub. core/curse.gd recognises an already-cursed enemy by the
# script path of the behaviours hanging off it, because the class itself is a DLC `class_name` and
# naming it would make the mod fail to parse for anyone without Abyssal Terrors. So this file is
# named after the vanilla one on purpose: it is what makes that check testable, and it fails here
# if the DLC ever renames the file.
