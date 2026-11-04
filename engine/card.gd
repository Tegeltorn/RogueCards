extends RefCounted
## A single playing card. Pure data, no presentation.

const SUITS := ["H", "D", "S", "C"]
const SYMBOL := {"H": "♥", "D": "♦", "S": "♠", "C": "♣", "J": "🃏"}
const RANK_NAME := {11: "J", 12: "Q", 13: "K", 14: "A"}

var id: int = 0
var rank: int = 0
var suit: String = ""      # "H", "D", "S", "C" or "J" (black joker)
var joker: String = ""     # red-joker effect attached under this card ("dual", "innate", "double", "draw2")
var temp: bool = false     # sacrificed ace or a virtual boss card: never enters the deck/discard
var from_joker: bool = false  # virtual enemy card produced by the black joker


func _init(p_id: int = 0, p_rank: int = 0, p_suit: String = "") -> void:
	id = p_id
	rank = p_rank
	suit = p_suit


func base_red() -> bool:
	return suit == "H" or suit == "D"


func base_black() -> bool:
	return suit == "S" or suit == "C"


## Player-card colour checks (respect the "dual" red joker).
func is_red() -> bool:
	return base_red() or joker == "dual"


func is_black() -> bool:
	return base_black() or joker == "dual"


## Card value including the "double" red joker.
func value() -> int:
	return rank * (2 if joker == "double" else 1)


func label() -> String:
	if suit == "J":
		return "Joker"
	if from_joker:
		return "Joker %d%s" % [rank, SYMBOL.get(suit, suit)]
	var r: String = RANK_NAME.get(rank, str(rank))
	return r + SYMBOL.get(suit, suit)


func to_dict() -> Dictionary:
	return {"id": id, "rank": rank, "suit": suit, "joker": joker, "temp": temp}


func describe() -> String:
	var s := label()
	if joker != "":
		s += "(" + joker + ")"
	return s
