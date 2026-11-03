extends RefCounted
## Event types emitted by the engine, plus human-readable (Swedish) descriptions for the log.

const RUN_STARTED := "run_started"
const MOD_REVEALED := "mod_revealed"
const THEME_REVEALED := "theme_revealed"
const SETUP_PICK := "setup_pick_offered"
const SETUP_PICKED := "setup_picked"
const FLOOR_STARTED := "floor_started"
const ENEMY_REVEALED := "enemy_revealed"
const JOKER_TRIGGERED := "joker_triggered"
const DECK_RESHUFFLED := "deck_reshuffled"
const CARD_DRAWN := "card_drawn"
const HAND_FILLED := "hand_filled"
const CARDS_PLAYED := "cards_played"
const ACE_SACRIFICED := "ace_sacrificed"
const BLOCKED := "blocked"
const DAMAGE_TAKEN := "damage_taken"
const SHIELD_STORED := "shield_stored"
const ATTACK_SUCCEEDED := "attack_succeeded"
const ATTACK_FAILED := "attack_failed"
const LOCKOUT := "lockout"
const ENEMY_DEFEATED := "enemy_defeated"
const LIFE_LOST := "life_lost"
const LIFE_RESTORED := "life_restored"
const RETAINED := "retained"
const FLOOR_CLEARED := "floor_cleared"
const REWARD_OFFERED := "reward_offered"
const REWARD_TAKEN := "reward_taken"
const REWARD_SKIPPED := "reward_skipped"
const CARD_REMOVED := "card_removed"
const JOKER_OFFERED := "joker_offered"
const JOKER_ATTACHED := "joker_attached"
const RUN_WON := "run_won"
const RUN_LOST := "run_lost"
const DEBUG := "debug"

const SUIT_NAME := {"H": "♥", "D": "♦", "S": "♠", "C": "♣", "J": "Joker"}


static func floor_name(f: int) -> String:
	match f:
		11: return "Knekt"
		12: return "Dam"
		13: return "Kung"
	return str(f)


static func describe(e: Dictionary) -> String:
	var t: String = e.get("type", "")
	match t:
		RUN_STARTED: return "Ny omgång, seed %s" % str(e.get("seed"))
		MOD_REVEALED: return "Modess: %s (%s)" % [SUIT_NAME.get(e.get("suit"), "?"), e.get("name", "")]
		THEME_REVEALED: return "Temakung: %s" % SUIT_NAME.get(e.get("suit"), "?")
		SETUP_PICK: return "Välj en extra trea till leken"
		SETUP_PICKED: return "Tog %s till leken" % e.get("card", "")
		FLOOR_STARTED: return "— Våning %s (%d kort) —" % [floor_name(e.get("floor", 0)), e.get("count", 0)]
		ENEMY_REVEALED:
			return "Fiende: %s (%s %d), %d kvar" % [e.get("card", ""),
				"attack" if e.get("intent") == "attack" else "sköld", e.get("value", 0), e.get("left", 0)]
		JOKER_TRIGGERED: return "Svart joker: %s" % e.get("desc", "")
		DECK_RESHUFFLED: return "Slänghögen blandas till ny dragbunt"
		CARD_DRAWN: return "Drog %s" % e.get("card", "")
		HAND_FILLED: return "Hand: %s" % ", ".join(e.get("hand", []))
		CARDS_PLAYED: return "Spelade %s" % ", ".join(e.get("cards", []))
		ACE_SACRIFICED: return "Offrade %s (värde %d)" % [e.get("card", ""), e.get("value", 0)]
		BLOCKED: return "Blockerade %d mot %d" % [e.get("block", 0), e.get("attack", 0)]
		DAMAGE_TAKEN: return "Miss med %d: -%d liv" % [e.get("miss", 0), e.get("lives", 0)]
		SHIELD_STORED: return "Sparad sköld: %d" % e.get("amount", 0)
		ATTACK_SUCCEEDED: return "Attack %d mot sköld %d: besegrad" % [e.get("attack", 0), e.get("shield", 0)]
		ATTACK_FAILED: return "Attack %d mot sköld %d: läggs sist" % [e.get("attack", 0), e.get("shield", 0)]
		LOCKOUT: return "Låst! Inga svarta kort kvar: -1 liv, skölden räknas som besegrad"
		ENEMY_DEFEATED: return "Besegrade %s" % e.get("card", "")
		LIFE_LOST: return "Förlorade liv (%s), %d kvar" % [e.get("card", ""), e.get("lives", 0)]
		LIFE_RESTORED: return "Fick tillbaka liv (%s), %d liv" % [e.get("card", ""), e.get("lives", 0)]
		RETAINED: return "Sparade %s" % ", ".join(e.get("cards", [])) if not e.get("cards", []).is_empty() else "Sparade inget"
		FLOOR_CLEARED: return "Våning %s klar, sista kortet: %s" % [floor_name(e.get("floor", 0)), e.get("last", "")]
		REWARD_OFFERED: return "Belöning (%s): %s" % [SUIT_NAME.get(e.get("suit"), "?"), ", ".join(e.get("options", []))]
		REWARD_TAKEN:
			if e.get("replaced", "") != "":
				return "Tog %s, bytte ut %s" % [e.get("card", ""), e.get("replaced", "")]
			return "Tog %s" % e.get("card", "")
		REWARD_SKIPPED: return "Avstod belöning"
		CARD_REMOVED: return "Tog bort %s ur leken" % e.get("card", "")
		JOKER_OFFERED: return "Röd joker: fäst under ett kort (%s)" % e.get("desc", "")
		JOKER_ATTACHED: return "Röd joker fäst under %s" % e.get("card", "")
		RUN_WON: return "SEGER!"
		RUN_LOST: return "Förlust på våning %s" % floor_name(e.get("floor", 0))
		DEBUG: return "[debug] %s" % e.get("msg", "")
	return t
