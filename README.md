# RogueCards

A solo roguelike deckbuilder played with a standard 54-card deck. This repo is a mobile playtest prototype made in Godot 4. The rules are also playable on a table: see [`RULES.md`](RULES.md).

## Play
- **Web (phone browser):** https://tegeltorn.github.io/RogueCards/ always has the latest push from any branch. Each branch also gets its own copy at `https://tegeltorn.github.io/RogueCards/branch/<branch>/`.
  GitHub Pages only works if the repo is public (or on GitHub Pro). If the page doesn't show up after the first build, go to Settings → Pages and pick Source: `gh-pages` branch.
- **Android:** download `RogueCards.apk` from the release `build-<branch>` under *Releases* and install it ("allow unknown sources").

CI builds, tests and deploys on every push (`.github/workflows/build.yml`). You don't need a computer.

## Balance
Every number lives in [`config/balance.json`](config/balance.json). Mods are in `config/mods.json`, jokers in `config/jokers.json`. The spec's original values are kept in `config/presets/spec.json`.
In the game: long-press the title to open the debug menu. There you can edit balance values (they apply from the next run), force a theme king or mod ace, jump to a floor, or give a life.

## Simulation
```
godot --headless --script res://sim/run_sim.gd -- --runs 20000            # current balance
godot --headless --script res://sim/run_sim.gd -- --runs 20000 --all      # + parity with the Python reference
godot --headless --script res://sim/run_sim.gd -- --set deck_cap=6 --no-mods
godot --headless --script res://sim/tune.gd -- --runs 600 --final-runs 5000
```
Each push writes a 5,000-run report to the CI job summary.

## Tests
```
godot --headless --script res://tests/run_tests.gd
```

## Layout
- `engine/`: the pure rules engine (`RefCounted`, no nodes). `engine.gd` holds the actions, `game_state.gd` the state, `mods/` the mods and `bot.gd` the simulation bot.
- `sim/`: headless simulation and tuning, plus the Python reference in `sim/reference/`.
- `tests/`: a minimal test runner and the tests.
- `ui/`: screens, card rendering, shaders and synthesized sound.
