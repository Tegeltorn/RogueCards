# Credits

## Fonts
- **EB Garamond** by The EB Garamond Project Authors (https://github.com/octaviopardo/EBGaramond12).
  Licensed under the SIL Open Font License 1.1. See `assets/fonts/OFL-EBGaramond.txt`. Subset to Latin.
- **Uncial Antiqua** by Astigmatic (AOETI).
  Licensed under the SIL Open Font License 1.1. See `assets/fonts/OFL-UncialAntiqua.txt`. Subset to Latin.
- **Noto Sans Symbols 2** (subset with card suit symbols, `assets/fonts/SuitSymbols.ttf`) by Google.
  Licensed under the SIL Open Font License 1.1. See `assets/fonts/OFL-NotoSansSymbols2.txt`.

## Graphics, shaders and sound
Everything is made for this project:
- Cards and suit symbols are drawn in code (`ui/card_view.gd`). The app icon (`icon.png`) and the
  loading-screen image (`assets/splash.png`) are rendered from that code by `tools/make_art.gd`.
- The shaders are in `ui/fx/`. The drifting smoke is a flow-noise shader (`ui/fx/smoke.gdshader`).
- The sounds are synthesized at runtime (`ui/sfx.gd`): plucked strings (Karplus-Strong), wooden knocks,
  parchment rustles, a frame drum and a hand bell.

There are no third-party graphics or sounds. The style is inspired by medieval illuminated manuscripts and Pre-Raphaelite painting but uses no assets, names or fonts from any other game.

## Engine
Built with [Godot Engine](https://godotengine.org) (MIT license).
