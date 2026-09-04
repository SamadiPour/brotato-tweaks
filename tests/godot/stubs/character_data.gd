class_name CharacterData
extends Resource

# The game's CharacterData is an ItemData, and CharacterSelection adds the chosen one through
# RunData.add_item() like any other item. core/curse.gd names the class to keep it out of the
# curse; this stub exists so that check compiles headless too.

var my_id := "character_stub"
var is_cursed := false
