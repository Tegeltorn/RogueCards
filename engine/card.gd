extends RefCounted
## A single playing card. Pure data, no presentation.

const SUITS := ["H", "D", "S", "C"]
const SYMBOL := {"H": "♥", "D": "♦", "S": "♠", "C": "♣"}
const RANK_NAME := {11: "J", 12: "Q", 13: "K", 14: "A"}

var id: int = 0
var rank: int = 0
var suit: String = ""      # "H", "D", "S" or "C"
var temp: bool = false     # sacrificed ace: never enters the deck/discard
var turned: bool = false   # enemy shield that already failed once (failed_shield "second")
var burned: bool = false   # burned this round: gone from the deck for good, counts with its burn value


func _init(p_id: int = 0, p_rank: int = 0, p_suit: String = "") -> void:
	id = p_id
	rank = p_rank
	suit = p_suit


func base_red() -> bool:
	return suit == "H" or suit == "D"


func base_black() -> bool:
	return suit == "S" or suit == "C"


func is_red() -> bool:
	return base_red()


func is_black() -> bool:
	return base_black()


func value() -> int:
	return rank


func label() -> String:
	var r: String = RANK_NAME.get(rank, str(rank))
	return r + SYMBOL.get(suit, suit)


func to_dict() -> Dictionary:
	return {"id": id, "rank": rank, "suit": suit, "temp": temp, "burned": burned}


func describe() -> String:
	return label() + (" (burned)" if burned else "")
