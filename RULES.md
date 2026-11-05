# RogueCards – tabletop rules

A solo game for a standard deck of 52 cards, played like a patience. You need nothing but the cards (the jokers are not used).

## Setup
1. **Starting deck:** the four twos (2♥ 2♦ 2♠ 2♣). Then shuffle the four threes, reveal `start_pick_offer` of them and add `start_pick_take` of your choice to your deck. The other threes are not used.
2. **Mod ace:** shuffle the four aces and draw one. Its suit sets the run's mod (see below). Put `lives` of the other aces in front of you as your **lives**.
3. **Enemies:** ranks `first_floor` (4) to King, one pile of four cards per rank (the kings are the last floor).

## Floors and rounds
Play the floors in order: 4, 5 … 10, Jack, Queen and finally the kings. Every floor is the four cards of its rank, shuffled. **At the start of each floor** shuffle your whole deck into a new draw pile. The discard pile is emptied, and kept cards and stored shield are reset.

Each round:
1. **Reveal** the top enemy card. Black = attack, red = shield. Its value is its rank.
2. **Fill your hand** up to `hand_size` cards. The face cards demand tribute: on the Jack, Queen and King floors only up to `face_hand_size`. If you burned a card last round, skip this step (`burn_no_refill`). Cards you didn't play last round are still in your hand. If the draw pile runs out while you fill your hand, shuffle the discard pile into a new draw pile. This is the only time the discard pile is shuffled back during a floor.
3. **Play** any cards you like. Only the right colour counts against the enemy: red cards block attacks, black cards break shields. Cards of the wrong colour still trigger their own effects (♦ draws, ♥ stores shield).
   - **Attack:** if your block is enough the attack is beaten. Otherwise you take damage, and (with `failed_attack_returns`) the attack card goes to the bottom of the enemy pile and comes back. Sacrificing an ace to block it is often worth it.
   - **Shield:** if your attack is enough the shield is beaten. Otherwise it goes to the bottom of the enemy pile and comes back. Cards that can't break it still help you cycle: play them and they go to the discard pile, so you draw fresh ones next round. If you can't ever break it, the run is stuck: start a new one.
   - **Burn:** while your deck has at least `burn_min_deck` cards, you may burn cards from your hand, as many as you like (`burn_limit` 0 = no limit). A burned card counts **double its rank in its own colour** this round (`burn_mode` `double`), with no suit effect (no ♦ draw, no ♥ storing, no ♠ × 1.5, no ♣ bonus). Then it is gone for good: put it back in the box. The price: your hand is not refilled at the start of the next round. (With `burn_mode` `swap` it counts its rank in the other colour instead.)
4. **End your turn:** the revealed enemy card is resolved as above. Every played card goes to the discard pile; unplayed cards stay in your hand (`keep_hand`). With `keep_hand` off, you instead keep up to `retain` unplayed cards and discard the rest.

| Suit | Effect |
|---|---|
| ♥ | Block. Leftover block is stored as shield **for the next round** (at most the hearts' total). With no attack to block, the hearts' full value is stored. Leave the hearts face up as a reminder. |
| ♦ | Block. Draw 1 card for each diamond you play, even against a shield, if the draw pile has cards left (the discard pile is not shuffled back mid-round). The drawn cards can be played this round. |
| ♠ | Attack. Value × 1.5, rounded down (2→3, 3→4, 5→7 …). |
| ♣ | Attack. +`club_pair_bonus` if you play at least two clubs in the same round. |

**Perfect:** when your block exactly equals the attack, or your attack exactly equals the shield, draw `perfect_draw` extra cards in your next hand (0 = no bonus).

Black cards played against an attack don't block. **Overpower:** once per round, when the black cards you have played against an attack add up to at least `overpower_multiplier` × its value (♠ × 1.5 and the ♣ bonus count), discard them right away and draw `overpower_draw` cards. The enemy still attacks when you end your turn.

**Damage:** a miss of 1 to `graded_threshold` − 1 costs 1 life. A bigger miss costs 2 lives. Put lost aces aside. When you have no aces left, you lose.

**Ace sacrifice:** while you have at least 2 lives you may sacrifice a life ace during a round. You lose that life, and the ace counts as a card worth 14 in its own colour for that round (red blocks, black attacks).

## Rewards (after every floor except the kings)
The suit of **your last card that counted** against the floor's final enemy card decides the reward: the last card you played (or burned) that blocked its attack or broke its shield. A sacrificed ace counts with its own suit. If no card of yours counted (a stored ♥ shield blocked it alone), the enemy card's own suit decides. You choose among the floor's beaten cards.

| Finishing card | Reward |
|---|---|
| ♠ | Pick any of the beaten cards. |
| ♣ | Reveal 2, take 1, and remove 1 card of your choice from your deck (choose both together). |
| ♥ | Get one lost life back. With all lives: reveal 2 and take 1. |
| ♦ | Reveal 2 and take both. |

Your deck has no size limit (`deck_cap` 0), and you may decline any reward card (`reward_optional`) to keep your deck lean. With a `deck_cap`, you must add cards until the deck is full; then swap a card out for the new one or decline. Your deck can never shrink below `deck_min` cards.

## The kings
The last floor is the four kings, with `face_hand_size` cards in hand like the Jacks and Queens. Beat all four to win.

## Mods (mod ace)
| Mod ace | Mod |
|---|---|
| ♥ Hardened | Your mod ace is an extra life, but ace sacrifice is disabled. Attacks you fail to block are beaten anyway. |
| ♦ Rich | Every reward reveals 1 more card, and a ♦ reward lets you take all of them. |
| ♠ Bloodthirst | Your attack gets +4, but every enemy attack also gets +1. |
| ♣ Foresight | Keep the top card of the enemy pile face up: you always see the next enemy card. |

## Current balance values
A test keeps these values in sync with `config/balance.json`.

| Key | Value | Meaning |
|---|---|---|
| `first_floor` | 4 | First enemy floor |
| `start_pick_offer` | 3 | Threes revealed at the start |
| `start_pick_take` | 1 | Threes you keep |
| `hand_size` | 4 | Hand size |
| `face_hand_size` | 3 | Hand size on the Jack, Queen and King floors |
| `keep_hand` | true | Unplayed cards stay in hand between rounds |
| `retain` | 1 | Cards you may keep (only when `keep_hand` is off) |
| `deck_cap` | 0 | Max cards in your deck (0 = no limit) |
| `reward_optional` | true | You may always decline a reward card |
| `deck_min` | 4 | Min cards in your deck (♣ removal) |
| `lives` | 2 | Number of life aces |
| `graded_threshold` | 4 | Miss that costs 2 lives |
| `failed_attack_returns` | true | An attack you fail to block goes to the bottom of the enemy pile |
| `club_pair_bonus` | 1 | Clubs bonus |
| `overpower_multiplier` | 2 | Black value needed to overpower an attack (× its value) |
| `overpower_draw` | 0 | Cards drawn on overpower |
| `perfect_draw` | 1 | Extra cards next hand after a perfect hit |
| `burn_mode` | double | Burned card: `double` its rank in its own colour, or `swap` to the other colour |
| `burn_limit` | 0 | Cards you may burn per round (0 = no limit) |
| `burn_min_deck` | 5 | Cards your deck needs to burn one |
| `burn_no_refill` | true | After a round you burned in, your hand is not refilled |
