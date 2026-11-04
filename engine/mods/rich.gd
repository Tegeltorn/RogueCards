extends "res://engine/mods/mod_base.gd"
## ♦ Rich: pick an extra three for the starting deck, but the diamond reward gives only 1 card.


func setup_pick_rank() -> int:
	return int(params.get("extra_rank", 3))


func modify_reward(reward: Dictionary) -> void:
	if reward.get("suit", "") == "D":
		reward["picks"] = int(params.get("diamond_picks", 1))
