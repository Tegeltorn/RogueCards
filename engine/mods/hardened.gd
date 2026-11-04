extends "res://engine/mods/mod_base.gd"
## ♥ Hardened: heart reward heals 2, ace sacrifice disabled.


func modify_reward(reward: Dictionary) -> void:
	if reward.get("suit", "") == "H":
		reward["heal"] = int(params.get("heart_heal", 2))


func can_ace_sac() -> bool:
	return false
