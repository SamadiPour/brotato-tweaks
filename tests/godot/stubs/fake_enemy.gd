extends Node

# Stands in for an `Enemy`, for the three things core/curse.gd asks one: whether it opted out of
# curses, whether it is already dead, and what is under its `effect_behaviors` node.
#
# It is a Node because the real one is, and because `effect_behaviors` has to be something children
# can be added to — which is how "already cursed" is asked in the game.

var can_be_cursed := true
var dead := false
var effect_behaviors: Node = null


func _init() -> void:
	effect_behaviors = Node.new()
	effect_behaviors.name = "EffectBehaviors"
	add_child(effect_behaviors)
