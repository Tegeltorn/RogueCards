extends "res://engine/mods/mod_base.gd"
## ♣ Foresight: see the next two enemy cards, but retain = 0.


func preview_count() -> int:
	return int(params.get("preview", 2))


func modify_retain(_n: int) -> int:
	return int(params.get("retain", 0))
