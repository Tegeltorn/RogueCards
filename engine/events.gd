extends RefCounted
## Event types emitted by the engine, plus human-readable descriptions for the log.

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
const LAST_STAND_BLOCKED := "last_stand_blocked"
const PERFECT := "perfect"
const CARD_DISCARDED := "card_discarded"
const OVERPOWER := "overpower"
const ACE_SACRIFICED := "ace_sacrificed"
const BLOCKED := "blocked"
const DAMAGE_TAKEN := "damage_taken"
const SHIELD_STORED := "shield_stored"
const ATTACK_SUCCEEDED := "attack_succeeded"
const ATTACK_FAILED := "attack_failed"
const ATTACK_RETURNED := "attack_returned"
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
		11: return "Jack"
		12: return "Queen"
		13: return "King"
	return str(f)


static func describe(e: Dictionary) -> String:
	var t: String = e.get("type", "")
	match t:
		RUN_STARTED: return "New run, seed %s" % str(e.get("seed"))
		MOD_REVEALED: return "Mod ace: %s (%s)" % [SUIT_NAME.get(e.get("suit"), "?"), e.get("name", "")]
		THEME_REVEALED: return "Theme king: %s" % SUIT_NAME.get(e.get("suit"), "?")
		SETUP_PICK: return "Pick a three for your deck"
		SETUP_PICKED: return "Added %s to the deck" % e.get("card", "")
		FLOOR_STARTED: return "— Floor %s (%d cards) —" % [floor_name(e.get("floor", 0)), e.get("count", 0)]
		ENEMY_REVEALED:
			return "Enemy: %s (%s %d), %d in pile" % [e.get("card", ""),
				"attack" if e.get("intent") == "attack" else "shield", e.get("value", 0), e.get("left", 0)]
		JOKER_TRIGGERED: return "Black joker: %s" % e.get("desc", "")
		DECK_RESHUFFLED: return "Discard pile shuffled into a new draw pile"
		CARD_DRAWN: return "Drew %s" % e.get("card", "")
		HAND_FILLED: return "Hand: %s" % ", ".join(e.get("hand", []))
		CARDS_PLAYED: return "Played %s" % ", ".join(e.get("cards", []))
		LAST_STAND_BLOCKED: return "Last stand: blocked its strike (%d vs %d), the shield falls" % [e.get("block", 0), e.get("shield", 0)]
		PERFECT: return "Perfect %s! +%d card next hand" % [e.get("kind", ""), e.get("draw", 1)]
		CARD_DISCARDED: return "Discarded %s" % e.get("card", "")
		OVERPOWER: return "Overpower! %d vs attack %d: %s discarded, draw 1" % [e.get("attack", 0), e.get("enemy", 0), ", ".join(e.get("cards", []))]
		ACE_SACRIFICED: return "Sacrificed %s (value %d)" % [e.get("card", ""), e.get("value", 0)]
		BLOCKED: return "Blocked %d against %d" % [e.get("block", 0), e.get("attack", 0)]
		DAMAGE_TAKEN: return "Missed by %d: -%d lives" % [e.get("miss", 0), e.get("lives", 0)]
		SHIELD_STORED: return "Stored shield: %d" % e.get("amount", 0)
		ATTACK_SUCCEEDED: return "Attack %d vs shield %d: broken" % [e.get("attack", 0), e.get("shield", 0)]
		ATTACK_RETURNED: return "%s was not blocked: it goes to the bottom and comes back" % e.get("card", "")
		ATTACK_FAILED: return "Attack %d vs shield %d: goes to the bottom" % [e.get("attack", 0), e.get("shield", 0)]
		LOCKOUT: return "Last stand! The shield held with no attackers left: -1 life, the shield counts as beaten"
		ENEMY_DEFEATED: return "Defeated %s" % e.get("card", "")
		LIFE_LOST: return "Lost a life (%s), %d left" % [e.get("card", ""), e.get("lives", 0)]
		LIFE_RESTORED: return "Life restored (%s), %d lives" % [e.get("card", ""), e.get("lives", 0)]
		RETAINED: return "Kept %s" % ", ".join(e.get("cards", [])) if not e.get("cards", []).is_empty() else "Kept nothing"
		FLOOR_CLEARED:
			if e.get("by_player", true):
				return "Floor %s cleared, finished with %s" % [floor_name(e.get("floor", 0)), e.get("last", "")]
			return "Floor %s cleared, no card of yours finished it: %s sets the reward" % [floor_name(e.get("floor", 0)), e.get("last", "")]
		REWARD_OFFERED:
			var rs: String = SUIT_NAME.get(e.get("suit"), "?")
			if int(e.get("healed", 0)) > 0:
				return "Reward (%s): a life back, no card" % rs
			return "Reward (%s): %s" % [rs, ", ".join(e.get("options", []))]
		REWARD_TAKEN:
			if e.get("replaced", "") != "":
				return "Took %s, swapped out %s" % [e.get("card", ""), e.get("replaced", "")]
			return "Took %s" % e.get("card", "")
		REWARD_SKIPPED: return "Declined reward"
		CARD_REMOVED: return "Removed %s from the deck" % e.get("card", "")
		JOKER_OFFERED: return "Red joker: attach it under a card (%s)" % e.get("desc", "")
		JOKER_ATTACHED: return "Red joker attached under %s" % e.get("card", "")
		RUN_WON: return "VICTORY!"
		RUN_LOST: return "Defeated on floor %s" % floor_name(e.get("floor", 0))
		DEBUG: return "[debug] %s" % e.get("msg", "")
	return t
