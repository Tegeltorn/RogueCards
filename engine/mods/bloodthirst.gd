extends "res://engine/mods/mod_base.gd"
## ♠ Blodtörst: your attacks +1, enemy attacks +1.


func modify_player_attack(total: int) -> int:
	return total + int(params.get("player_attack_bonus", 1))


func modify_enemy_attack(value: int) -> int:
	return value + int(params.get("enemy_attack_bonus", 1))
