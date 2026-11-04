extends "res://engine/mods/mod_base.gd"
## ♣ Foresight: see the next enemy card.


func preview_count() -> int:
	return int(params.get("preview", 1))
