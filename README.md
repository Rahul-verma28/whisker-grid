# Whisker Grid 🐱

A cosy logic puzzle for phones, made with **Godot 4** and **Blender**. Hide one friend in every row, column and colour, and never let two of them touch.

## Features
- **100 hand-picked levels.** Grids grow from 4×4 to 10×10:

  | Levels | Grid | Feel |
  |---|---|---|
  | 1–5 | 4×4 | Easy |
  | 6–12 | 5×5 | Warm-up |
  | 13–22 | 6×6 | Medium |
  | 23–36 | 7×7 | Tricky |
  | 37–54 | 8×8 | Hard |
  | 55–76 | 9×9 | Expert |
  | 77–100 | 10×10 | Master |

  Each size starts gentle and ends tough. Every level has exactly one solution.
- **Levels map** with 1–3 stars per level. You get 3 stars for no mistakes and no hints, 2 stars for a total of up to 2 mistakes and hints, and 1 star otherwise.
- **Daily Challenge:** one new 7×7 puzzle per day.
- **Friends shop:** spend your points on Biscuit the dog, Clover the bunny or Pip the mouse. Your pick shows up on the board, the home screen, the rules and the celebrations.
- **Animated 3D characters** built in Blender. Each one breathes, blinks, sways its tail and twitches its ears, and does a happy hop when you tap it. They have cartoon outlines and rim lighting.
- **Level-complete celebration:** your friend dances, rays spin behind it, stars pop in with chimes, and confetti flies. It also shows your progress towards the next friend.
- **Settings:** music, sound effects and vibration toggles, 4 themes (Cozy Cream, Starry Night, Mint Garden, Sakura), How to play, and Reset progress.
- **Original music and sound effects**, composed in code.

## Controls
- **Tap** a cell for an X.
- **Double-tap** a cell to place your friend.
- **Drag** across cells to paint X's.
- A wrong guess costs a heart (you have 3).
- **Hint** reveals a friend (3 per level).

## Project layout
```
scenes/main.tscn              entry scene
scripts/main.gd               every screen: home, levels, friends, settings, game, popups, celebration
scripts/board.gd              puzzle grid: drawing, touch, undo, hints, rule checks
scripts/puzzle_generator.gd   generator, solver, human-style difficulty rating, campaign loader
scripts/character_view.gd     animated 3D character stage (outline + rim light)
scripts/characters.gd         list of friends and their prices
scripts/palette.gd            colour themes
scripts/audio.gd              autoload "Sfx": music, sound effects, vibration
assets/levels.json            the 100 pre-built levels
assets/characters/            <id>.glb (rigged, animated) + <id>_icon.png
assets/audio/                 music.ogg + effect .wav files
assets/fonts/Fredoka.ttf      rounded UI font (SIL Open Font License, see OFL.txt)
blender/make_characters.py    builds and animates all characters in Blender
tools/outline_icons.py        adds the cartoon outline to the icons
tools/make_audio.py           composes the music and sound effects (numpy + ffmpeg)
tools/build_levels.gd         generates and ranks the 100 levels
tools/export_web.sh           web build, for testing on a phone
docs/                         game website (GitHub Pages): home, privacy policy, terms, app-ads.txt
store/                        Play Store listing text and graphics
addons/admob/                 AdMob plugin (Poing Studios, MIT)
```

## Rebuilding assets
Run these from the project root:
```bash
"C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" -b -P blender/make_characters.py
```
```bash
python tools/outline_icons.py
```
```bash
python tools/make_audio.py
```
```bash
D:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/build_levels.gd
```

## Testing
Headless test suite, 37 checks:
```bash
D:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/smoke_test.tscn
```
Screenshots of every screen, saved to `%APPDATA%\Godot\app_userdata\Whisker Grid\screens`. Add `-- night` at the end for the dark theme:
```bash
D:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --path . res://tests/screenshots.tscn
```

## Playing on your phone over USB
Connect the phone with USB debugging on, then run these three commands:
```bash
bash tools/export_web.sh
```
```bash
cd build/web && python -m http.server 8000
```
```bash
~/AppData/Local/Android/Sdk/platform-tools/adb.exe reverse tcp:8000 tcp:8000
```
Then open `http://localhost:8000` in the phone's browser.

## Website
https://rahul-verma28.github.io/whisker-grid/ is served from `docs/`. See `docs/README.md`.

## Releasing on Google Play
This still needs an Android export: Godot's Android export template, a release keystore, and an `.aab` file. It also needs a Play Console account, a store listing, a privacy policy, and a 14-day closed test with 12 testers.
