# RogueCards – tabletop rules

A solo game for a standard deck (52 cards + 2 jokers). You need nothing but the cards.

## Setup
1. **Starting deck:** the four twos (2♥ 2♦ 2♠ 2♣), shuffled.
2. **Mod ace:** shuffle the four aces and draw one. Its suit sets the run's mod (see below). Put `lives` of the other aces in front of you as your **lives**.
3. **Theme king:** shuffle the four kings and draw one. Its suit decides the jokers.
4. **Boss pile:** the other three kings plus the black joker. Put the red joker aside.
5. **Enemies:** ranks 3 to Queen, one pile per rank. On the floors in `short_floors`, shuffle the pile and remove one card so that three are left.

## Floors and rounds
Play the floors in order: 3, 4 … 10, Jack, Queen and finally the kings. **At the start of each floor** shuffle your whole deck into a new draw pile. The discard pile is emptied, and kept cards and stored shield are reset.

Each round:
1. **Reveal** the top enemy card. Black = attack, red = shield. Its value is its rank.
2. **Fill your hand** up to `hand_size` cards (`boss_hand_size` against the kings). If the draw pile is empty, shuffle the discard pile into a new one.
3. **Play** any cards you like. Only the right colour counts against the enemy: red cards block attacks, black cards break shields. Cards of the wrong colour still trigger their own effects (♦ draws, ♥ stores shield).
   - **Attack:** if your block is enough you are safe, otherwise you take damage. The enemy card is beaten either way.
   - **Shield:** if your attack is enough the shield is beaten. Otherwise it goes to the bottom of the enemy pile.
   - **Last stand:** if you fail against a shield and there are no black cards left in the enemy pile, lose 1 life and the shield counts as beaten.
4. **Keep** up to `retain` unplayed cards. The rest of your hand and every played card go to the discard pile.

| Suit | Effect |
|---|---|
| ♥ | Block. Leftover block is stored as shield **for the next round** (at most the hearts' total). With no attack to block, the hearts' full value is stored. Leave the hearts face up as a reminder. |
| ♦ | Block. Draw 1 card for each diamond you play, even against a shield. The drawn cards can be played this round. |
| ♠ | Attack. Value × 1.5, rounded down (2→3, 3→4, 5→7 …). |
| ♣ | Attack. +`club_pair_bonus` if you play at least two clubs in the same round. |

Black cards played against an attack do nothing; they are just discarded.

**Damage:** a miss of 1 to `graded_threshold` − 1 costs 1 life. A bigger miss costs 2 lives. Put lost aces aside. When you have no aces left, you lose.

**Ace sacrifice:** while you have at least 2 lives you may sacrifice a life ace during a round. You lose that life, and the ace counts as a card worth 14 in its own colour for that round (red blocks, black attacks).

## Rewards (after every floor except the kings)
The suit of the **last beaten enemy card** decides the reward. You choose among the floor's beaten cards.

| Last card | Reward |
|---|---|
| ♠ | Pick any of the beaten cards. |
| ♣ | Reveal 2, take 1. Then remove 1 card of your choice from your deck. |
| ♥ | Get one lost life back. With all lives: reveal 2 and take 1. |
| ♦ | Reveal 2 and take both. |

If your deck has fewer than `deck_cap` cards you must add the new card. When it is full, swap a card out for the new one or decline. Your deck can never shrink below `deck_min` cards.

## Jokers and the kings
| Theme | Red joker (after the Jack floor: put it under any card in your deck) | Black joker (in the boss pile) |
|---|---|---|
| ♥ | The card counts as both colours | The last beaten king goes back to the bottom of the boss pile |
| ♦ | The card is always in your first hand of each floor | Shield 14 |
| ♠ | The card is worth double | Attack 14 |
| ♣ | Draw 2 cards when the card is played | Reveal the next two cards and beat both with the same hand |

Beat the whole boss pile to win.

## Mods (mod ace)
| Mod ace | Mod |
|---|---|
| ♥ Hardened | The ♥ reward heals 2 lives, but ace sacrifice is disabled. |
| ♦ Rich | Pick an extra three for your starting deck. Floor 3 is then the other three threes. The ♦ reward gives only 1 card. |
| ♠ Bloodthirst | Your attack gets +1, but every enemy attack also gets +1. |
| ♣ Foresight | You see the next two enemy cards, but you can't keep cards between rounds. |

## Current balance values
A test keeps these values in sync with `config/balance.json`.

| Key | Value | Meaning |
|---|---|---|
| `hand_size` | 4 | Hand size |
| `boss_hand_size` | 3 | Hand size against the kings |
| `retain` | 1 | Cards you may keep between rounds |
| `deck_cap` | 9 | Max cards in your deck |
| `deck_min` | 4 | Min cards in your deck |
| `lives` | 3 | Number of life aces |
| `short_floors` | [3,4,5] | Floors with only 3 enemies |
| `graded_threshold` | 5 | Miss that costs 2 lives |
| `club_pair_bonus` | 2 | Clubs bonus |
