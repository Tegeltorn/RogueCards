# RogueCards – tabletop rules

A solo game for a standard deck of 52 cards, played like a patience. You need nothing but the cards (the jokers are not used).

## Setup
1. **Lives:** the four aces are your lives (`lives` of them: put the others back in the box). Lose them all and the run ends.
2. **Starting deck:** the four twos (2♥ 2♦ 2♠ 2♣). Shuffle the four threes and deal `start_random` of them into your deck, face down: a deck of six cards. The other threes are not used.
3. **Enemies:** ranks `first_floor` (4) to King, one pile of four cards per rank. Each floor is the four cards of its rank, shuffled; the kings are the last floor.

## Floors and rounds
Play the floors in order: 4, 5 … 10, Jack, Queen, King. **At the start of each floor** shuffle your whole deck into a new draw pile; the discard pile and stored shield are cleared, and you draw a hand of `hand_size` cards. **The face cards demand tribute:** from the Jack floor on (`face_from` 11) the hand is `face_hand_size`.

Each round:
1. **Reveal** the top enemy card. Black = attack, red = shield. Its value is its rank.
2. **Draw** `draw_per_turn` cards (not in the first round of a floor). If the draw pile runs out while you draw, shuffle the discard pile into a new draw pile and keep drawing (`refill_mode` continuous).
3. **Play** any cards you like. Only the right colour counts: red cards block attacks, black cards break shields. Cards of the wrong colour still trigger their own effects (♦ draws, ♥ stores shield).
4. **End your turn:** the enemy card is resolved. **Every enemy card is fought once:** if your block (against an attack) or your attack (against a shield) reaches its value, it is beaten; if not, you lose 1 life — 2 lives if you missed by `graded_threshold` or more — and it is beaten anyway (`failed_attack_returns` false, `failed_shield` wound). Played cards go to the discard pile. Unplayed cards stay in your hand, but you hold at most `hand_max`: discard down to that many, your choice.

| Suit | Effect |
|---|---|
| ♥ | Block. A ♥ that is your only block card this round counts double (`heart_lone_mult`). Leftover block is stored as shield for the next round (at most the hearts' total); with no attack to block, the hearts' full value is stored. |
| ♦ | Block. Each ♦ you play draws 1 card (`diamond_draw` always), even against a shield, if the draw pile has cards. |
| ♠ | Attack. A ♠ that is your only attack card this round counts double (`spade_mode` lone, `spade_lone_mult`); with other attack cards, just its rank. |
| ♣ | Attack. Each ♣ counts its rank + `club_swarm_bonus` (`club_mode` plus). |

## After each floor (except the kings): choose one
- **Take:** add one of the floor's four beaten cards to your deck.
- **Trade:** add one beaten card and put one of your deck cards back in the box.
- **Cull:** put up to `menu_cull` of your deck cards back in the box.
- **Heal:** take back one lost ace.

Trade and cull need a deck of at least `deck_min` cards, and culling never takes it below that (`reward_mode` menu).

Beat the four kings to win.

## Current balance values
A test keeps these values in sync with `config/balance.json`. Older rules (returning cards, burn, overpower, perfect hits, mods, suit rewards) are still in the engine behind their keys, off by default; `config/presets/classic.json` holds the previous rule set.

| Key | Value | Meaning |
|---|---|---|
| `first_floor` | 4 | First enemy floor |
| `start_random` | 2 | Threes dealt at random into the starting deck |
| `lives` | 2 | Number of life aces |
| `hand_size` | 4 | Hand drawn at the start of each floor |
| `face_from` | 11 | First floor that demands tribute (Jack) |
| `face_hand_size` | 3 | Hand size from that floor on |
| `draw_per_turn` | 2 | Cards drawn each later round |
| `hand_max` | 4 | Most cards you may hold at the end of a turn |
| `refill_mode` | continuous | Shuffle the discard pile when the draw pile runs out mid-draw |
| `failed_attack_returns` | false | A failed attack does not come back (it is beaten anyway) |
| `failed_shield` | wound | A failed shield costs lives like a missed attack and is beaten anyway |
| `graded_threshold` | 2 | A miss this big costs 2 lives |
| `heart_lone_mult` | 2 | A lone ♥ block counts × this |
| `diamond_draw` | always | Every ♦ played draws a card |
| `spade_mode` | lone | A lone ♠ attack counts × `spade_lone_mult` |
| `spade_lone_mult` | 2 | Multiplier for a lone ♠ |
| `club_mode` | plus | Every ♣ gets + `club_swarm_bonus` |
| `club_swarm_bonus` | 4 | The ♣ bonus |
| `reward_mode` | menu | After a floor: take, trade, cull or heal |
| `menu_take` | 1 | Cards you may take |
| `menu_cull` | 2 | Cards you may cull |
| `deck_min` | 9 | Deck size needed to trade or cull (never culled below) |
| `burn_mode` | off | Burning is not used |
| `overpower_multiplier` | 0 | Overpower is not used |
| `perfect_draw` | 0 | No bonus for perfect hits |
| `ace_sac_enabled` | false | Aces are not sacrificed |
| `mods_enabled` | false | No mod ace |
