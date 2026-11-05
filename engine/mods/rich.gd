extends "res://engine/mods/mod_base.gd"
## ♦ Rich: rewards reveal more cards (and other tunable twists, see params in config/mods.json).


func modify_start_picks(n: int) -> int:
	return int(params.get("start_picks", n))


func modify_reward(reward: Dictionary) -> void:
	reward["reveal"] = int(reward["reveal"]) + int(params.get("reveal_bonus", 0))
	if reward.get("suit", "") == "D" and params.has("diamond_picks"):
		reward["picks"] = int(params["diamond_picks"])


func modify_menu(reward: Dictionary) -> void:
	reward["picks"] = int(reward["picks"]) + int(params.get("menu_take_bonus", 1))
