extends "res://engine/mods/mod_base.gd"
## ♦ Rich: keep two of the offered threes, but the diamond reward gives only 1 card.


func modify_start_picks(_n: int) -> int:
	return int(params.get("start_picks", 2))


func modify_reward(reward: Dictionary) -> void:
	if reward.get("suit", "") == "D":
		reward["picks"] = int(params.get("diamond_picks", 1))
