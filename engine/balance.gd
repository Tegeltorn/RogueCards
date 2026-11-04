extends RefCounted
## Loads balance/mod/joker data from JSON. All numbers in the game come from here.

const BALANCE_PATH := "res://config/balance.json"
const MODS_PATH := "res://config/mods.json"
const JOKERS_PATH := "res://config/jokers.json"

const INT_KEYS := ["first_floor", "start_pick_rank", "start_pick_offer", "start_pick_take", "hand_size", "boss_hand_size", "retain", "deck_cap", "deck_min", "lives",
	"graded_threshold", "club_pair_bonus", "overpower_multiplier", "overpower_draw", "ace_value", "joker_curse_value", "red_joker_after_floor"]
const BOOL_KEYS := ["keep_hand", "ace_sac_enabled", "ace_sac_own_color", "ace_sac_suit_effects",
	"mods_enabled", "jokers_enabled"]

static var _cache: Dictionary = {}


static func load_json(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path].duplicate(true)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open " + path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Invalid JSON in " + path)
		return {}
	_cache[path] = data
	return data.duplicate(true)


## Default balance merged with overrides, normalised to proper types.
static func make(overrides: Dictionary = {}) -> Dictionary:
	var b := load_json(BALANCE_PATH)
	for k in overrides:
		b[k] = overrides[k]
	return normalise(b)


static func normalise(b: Dictionary) -> Dictionary:
	for k in INT_KEYS:
		if b.has(k):
			b[k] = int(b[k])
	for k in BOOL_KEYS:
		if b.has(k):
			b[k] = bool(b[k])
	var sf: Array = []
	for v in b.get("short_floors", []):
		sf.append(int(v))
	b["short_floors"] = sf
	b["spade_multiplier"] = float(b.get("spade_multiplier", 1.5))
	b["lives"] = clampi(int(b.get("lives", 3)), 1, 3)  # lives are physical aces: max 3
	if not b.has("heart_carry_mode"):
		b["heart_carry_mode"] = "next_round"
	return b


static func mods() -> Dictionary:
	return load_json(MODS_PATH)


static func jokers() -> Dictionary:
	return load_json(JOKERS_PATH)
