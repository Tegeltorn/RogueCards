extends RefCounted
## Base class for run modifiers (picked by the mod ace). Override only the hooks you need.
## A new mod = a new script in this folder + an entry in config/mods.json.

var id: String = ""
var suit: String = ""
var name: String = ""
var desc: String = ""
var params: Dictionary = {}


func setup(p_suit: String, data: Dictionary) -> void:
	suit = p_suit
	id = data.get("id", "")
	name = data.get("name", id)
	desc = data.get("desc", "")
	params = data.get("params", {})


## How many of the offered start cards the player keeps.
func modify_start_picks(n: int) -> int:
	return n


## Total player attack for one round (called only when attack cards were played).
func modify_player_attack(total: int) -> int:
	return total


## Value of a single enemy attack card.
func modify_enemy_attack(value: int) -> int:
	return value


## Reward dictionary: {suit, heal, picks, reveal, remove}. Mutate in place.
func modify_reward(_reward: Dictionary) -> void:
	pass


func modify_retain(n: int) -> int:
	return n


func can_ace_sac() -> bool:
	return true


## How many upcoming enemy cards the player can see.
func preview_count() -> int:
	return 0
