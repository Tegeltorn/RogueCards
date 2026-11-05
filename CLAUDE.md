# CLAUDE.md – working on RogueCards

The owner develops this from a phone through Claude Code sessions. CI builds, tests and deploys every push, so keep CI green.

## Set up Godot in a fresh container
```bash
V=$(cat .godot-version)
mkdir -p /tmp/godot && cd /tmp/godot
curl -sSL -o g.zip "https://github.com/godotengine/godot/releases/download/${V}-stable/Godot_v${V}-stable_linux.x86_64.zip"
unzip -oq g.zip && mv "Godot_v${V}-stable_linux.x86_64" godot && cd -
export PATH=/tmp/godot:$PATH
godot --headless --import --path .        # needed once (fonts, class cache)
```

## Checks to run before every push
```bash
godot --headless --path . --script res://tests/run_tests.gd               # unit tests (exit 1 on failure)
godot --headless --path . --script res://tests/ui_smoke.gd -- --runs 2    # whole runs through the real UI
godot --headless --path . --script res://sim/run_sim.gd -- --runs 5000    # bot win rate
```
Screenshots (useful for checking visuals) need a virtual display:
```bash
xvfb-run -a -s "-screen 0 800x1400x24" godot --path . --resolution 720x1280 --rendering-driver opengl3 \
  --script res://tests/ui_smoke.gd -- --runs 1 --speed 2 --shots /some/dir
```

## Architecture rules
- `engine/` is pure logic (`RefCounted`, no nodes or UI). All state lives in `GameState`. All randomness goes through `engine/rng.gd` (seeded).
- Save & resume: every player action is a thin wrapper `func x(...): return _act("x", [...])` around `_do_x()`, so it is journaled; `engine.snapshot()`/`restore()` replay seed + journal. New actions must follow this pattern (`tests/test_save.gd`). The UI saves after each action (`user://run.save`) and resumes on start. On the web, a script in `html/head_include` reloads the page if WebGL is lost or the game stops beating (`window.rcBeat`) after switching apps.
- Each engine action emits events (`engine/events.gd`). The UI (`ui/main.gd`) replays them in order through the active screen's `play_event()`, then calls `refresh()` to sync with the state.
- All numbers live in `config/balance.json`. The current rules: every enemy card is fought once (`failed_shield` wound, `failed_attack_returns` false: a miss costs lives, the card falls anyway); reserve hand (`hand_size` at a floor's start, `draw_per_turn` later, `hand_max`, `refill_mode` continuous; `face_hand_size` from floor `face_from`); suits by mode keys (`heart_lone_mult`, `diamond_draw`, `spade_mode` lone, `club_mode` plus); after a floor a reward menu (`reward_mode` menu: take / trade / cull / heal, `deck_min` gates trade and cull). Older mechanics (returning cards, burn, overpower, perfect hits, mods, suit rewards) stay in `engine/engine.gd` behind their keys; `config/presets/classic.json` is the previous rule set and the mechanic unit tests run on it (`classic()` in `tests/test_base.gd`). Mods are in `config/mods.json` + `engine/mods/*.gd`. In the fight, `Pile` (ui/screens/combat.gd) draws the draw and discard piles.
- Design tools: `sim/design_metrics.gd` (dead / forced / choice rounds, tension, deck-building spread) and `sim/arch_sim.gd` (win rate per deck-building build); both take `--preset`. Presets of the design experiments are in `config/presets/`.
- Use `preload` consts, not `class_name`. Don't name a const `Engine`, it shadows the Godot singleton.
- Warnings are errors for inferred Variant types: write `var x: int = dict.get(...)`, not `var x := dict.get(...)`.

## Design constraints
- **Tabletop:** every rule must be playable by hand with a real 52-card deck, as simply as a patience. Use only the cards, integers and simple maths. Tuning may only touch knobs visible on the table.
- `RULES.md` (tabletop rules) must match `balance.json`. `tests/test_rules_doc.gd` enforces this, so update both together.
- Language: the whole game, the event log and the docs are in English.
- **Balance target:** bot win rate within `target.bot_win_rate_band` (15–22 %). Humans should land around 25 %. Use `sim/tune.gd` for sweeps. The spec's original values are in `config/presets/spec.json`.
- No assets, names or fonts from other games. Fonts must be OFL and listed in `CREDITS.md`.
- **Look:** illuminated manuscript (bardcore / Pre-Raphaelite): vellum, iron-gall ink, madder red, moss green, ochre gold. Low blue light: no saturated blues or pure white. All colours come from the palette in `ui/style.gd` (day and night variants; `Style.hex()` for bbcode), so never hardcode colours in screens. Effects stay gentle (soft fades, small shake). Smoke: shader-only swirling flow noise (`ui/fx/smoke.gdshader`). Sounds: synthesized medieval set in `ui/sfx.gd` (D dorian; levels in `LEVEL`). Loading screen: re-render with `tools/make_art.gd` (see its header) after changing cards or fonts. Icons are the owner's artwork: `icon.png` = browser tab (no letters), `assets/app_icon/icon_{144,180,512}.png` = installed web app (PWA, enabled in `export_presets.cfg`) and Android launcher; the web loader's colours are CSS in `export_presets.cfg` (`html/head_include`) and the boot splash colour in `project.godot`.
- The web build has no system fonts: every non-ASCII character in UI text must exist in `EBGaramond.ttf` / `UncialAntiqua.ttf` (both subset to Latin-1 plus general punctuation) or `SuitSymbols.ttf` (missing glyphs show as boxes with a hex code). System fallback is disabled so desktop screenshots show the same.

## Deploy
- `.github/workflows/build.yml`: tests → web export → GitHub Pages (root = latest push, `/branch/<name>/` per branch) and a debug APK → release `build-<branch>`.
