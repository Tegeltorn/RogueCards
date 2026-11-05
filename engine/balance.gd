extends RefCounted
## Loads balance/mod data from JSON. All numbers in the game come from here.

const BALANCE_PATH := "res://config/balance.json"
const MODS_PATH := "res://config/mods.json"

const INT_KEYS := ["first_floor", "start_pick_rank", "start_pick_offer", "start_pick_take", "start_random", "hand_size", "face_hand_size", "retain", "deck_cap", "deck_min", "lives",
	"graded_threshold", "club_pair_bonus", "overpower_multiplier", "overpower_draw", "perfect_draw", "min_draw", "ace_value", "burn_limit", "burn_min_deck", "burn_draw", "redraw_limit", "redraw_cost", "draw_per_turn", "hand_max",
	"club_swarm_bonus", "spade_lone_mult", "heart_wall_cap", "menu_take", "menu_cull", "hand_per_deck", "reward_max_rank", "face_from", "heart_lone_mult"]
const BOOL_KEYS := ["keep_hand", "reward_optional", "free_discard", "ace_sac_enabled", "ace_sac_suit_effects",
	"mods_enabled", "failed_attack_returns", "burn_no_refill", "rest_heal", "heart_heal"]

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
	# Lives are physical aces: max 3, or 4 when there is no mod ace.
	b["lives"] = clampi(int(b.get("lives", 3)), 1, 3 if bool(b.get("mods_enabled", true)) else 4)
	if not ["double", "swap", "dig", "off"].has(str(b.get("burn_mode", "off"))):
		b["burn_mode"] = "off"
	b["burn_mode"] = str(b.get("burn_mode", "off"))
	if not ["empty", "continuous"].has(str(b.get("refill_mode", "empty"))):
		b["refill_mode"] = "empty"
	if not b.has("heart_carry_mode"):
		b["heart_carry_mode"] = "next_round"
	return b


static func mods() -> Dictionary:
	return load_json(mods_path)
