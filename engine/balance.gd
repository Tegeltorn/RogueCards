extends RefCounted
## Loads balance/mod data from JSON. All numbers in the game come from here.

const BALANCE_PATH := "res://config/balance.json"
const MODS_PATH := "res://config/mods.json"

const INT_KEYS := ["first_floor", "start_pick_rank", "start_pick_offer", "start_pick_take", "hand_size", "face_hand_size", "retain", "deck_cap", "deck_min", "lives",
	"graded_threshold", "club_pair_bonus", "overpower_multiplier", "overpower_draw", "perfect_draw", "min_draw", "ace_value", "burn_limit", "burn_min_deck"]
const BOOL_KEYS := ["keep_hand", "reward_optional", "free_discard", "ace_sac_enabled", "ace_sac_suit_effects",
	"mods_enabled", "failed_attack_returns", "burn_no_refill"]

static var _cache: Dictionary = {}
static var mods_path := MODS_PATH  # the simulator can point this at an alternate mods file


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
	b["spade_multiplier"] = float(b.get("spade_multiplier", 1.5))
	b["lives"] = clampi(int(b.get("lives", 3)), 1, 3)  # lives are physical aces: max 3
	if not ["double", "swap", "off"].has(str(b.get("burn_mode", "off"))):
		b["burn_mode"] = "off"
	b["burn_mode"] = str(b.get("burn_mode", "off"))
	if not b.has("heart_carry_mode"):
		b["heart_carry_mode"] = "next_round"
	return b


static func mods() -> Dictionary:
	return load_json(mods_path)
