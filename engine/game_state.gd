extends RefCounted
## All mutable state of one run. Owned and mutated only by engine.gd.

enum Phase { SETUP_PICK, REVEAL, PLAY, RETAIN, REWARD, REWARD_REMOVE, JOKER_ATTACH, WON, LOST }

const BOSS_FLOOR := 13
const FIRST_FLOOR := 3

var seed_value: int = 0
var balance: Dictionary = {}
var phase: int = Phase.REVEAL

var mod_suit: String = ""
var mod_ace = null          # Card
var theme_suit: String = ""
var theme_king = null       # Card

var lives: Array = []       # Card (aces) currently alive
var lost_lives: Array = []  # Card (aces) lost, can be restored
var max_lives: int = 3

var deck: Array = []        # all owned cards
var draw_pile: Array = []   # top of pile = last element
var discard: Array = []
var hand: Array = []
var played: Array = []      # cards played this round (incl. sacrificed aces)
var retained: Array = []

var floor_num: int = FIRST_FLOOR
var enemy_pile: Array = []  # front = next card
var current: Array = []     # revealed enemy cards being fought
var beaten: Array = []      # beaten enemy cards this floor (in order)
var last_beaten = null

var carry_shield: int = 0   # stored ♥ overflow
var overpowered := false    # overpower already triggered this round
var bonus_draw: int = 0     # extra cards for the next hand (perfect hits)
var round_num: int = 0
var floor_round: int = 0

var setup_options: Array = []
var setup_picks: int = 0     # how many of setup_options may still be taken
var reward: Dictionary = {}  # {suit, heal, picks, reveal, remove, options:[Card]}
var red_joker_effect: String = ""
var black_joker_effect: String = ""
var joker_attached: bool = false

var next_id: int = 1
var result: String = ""      # "", "win", "dead"
var events: Array = []


func is_boss() -> bool:
	return floor_num == BOSS_FLOOR


## Enemy needs for the currently revealed cards.
func enemy_attack_cards() -> Array:
	var out: Array = []
	for c in current:
		if c.base_black():
			out.append(c)
	return out


func enemy_shield_cards() -> Array:
	var out: Array = []
	for c in current:
		if c.base_red():
			out.append(c)
	return out


func find_in(arr: Array, card_id: int):
	for c in arr:
		if c.id == card_id:
			return c
	return null


func phase_name() -> String:
	return Phase.keys()[phase]
