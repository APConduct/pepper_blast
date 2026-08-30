# Pepper Blast

A tap game for **Pepper**, Joey's cockatiel. 🦜

Seeds dance around the screen. Pepper touches one, it pops with a chirp, and
the chirps climb a scale as he keeps going. Every 10 pops the screen throws
confetti and a synthesised cockatiel song plays.

Built with [LÖVE](https://love2d.org) 11.4. Runs on desktop (mouse) and iPhone
/ iPad (touch). No image or audio assets — every shape is drawn with primitives
and every sound is synthesised at startup, so the whole game is ~1000 lines of
Lua and nothing else.

## Run it on a computer

```sh
love .
```

Or drag the folder onto the LÖVE app. To make a distributable file:

```sh
zip -9 -r pepper_blast.love . -x '.git/*' 'tests/*' '*.love'
```

## Controls

There are deliberately no menus — Pepper cannot use menus.

| Input | Action |
| --- | --- |
| Tap / click anywhere | ripple + soft blip |
| Tap / click a seed | pop, chirp, +1 point |
| **Hold** the top-right corner for ~1s | sound on/off |
| `M` | mute | 
| `F` | fullscreen |
| `R` | reset the current score |
| `Esc` | quit |

The mute control is a *hold*, not a tap, because birds tap but don't hold. It's
the one thing you don't want Pepper switching off by accident.

## How it's designed for a bird

These aren't arbitrary choices, they're why the game works:

- **You cannot lose.** No timers, no misses, no game over. Every touch produces
  a visible ripple and a small sound, so Pepper learns that touching the screen
  does something even before he learns to aim.
- **Seed-sized art, oversized hit areas.** Pepper prefers small seeds to big
  cartoon fruit, so the targets are roughly life-size — but the hit area is
  **2.4× the visible radius**, which is invisible to him. At 900x620 the seeds
  are 33-68 px across while the touch zones are 80-163 px. Shrinking the
  picture deliberately does not shrink the target.
- **High contrast at small size.** Every seed gets a pale halo, a hard white
  outline and a specular highlight on a dark background, which is what makes
  something small still pop — including the dark grey sunflower seeds.
- **Four real seed silhouettes**, weighted like a cockatiel mix: millet ~39%,
  canary ~30%, safflower ~22%, sunflower ~9% (the fatty treat).
- **The dance is measured in screen units, not seed radii**, so tiny seeds
  still bob and sway across the screen as much as large targets would.
- **Curiosity pull.** For ~1.5s after a touch, the seeds drift gently toward
  wherever Pepper touched. It quietly converts near-misses into hits.
- **Attract mode.** After 14 seconds of no play, the seeds slow down, swell by
  35%, gather toward the centre, and the game whistles a cockatiel *contact
  call* every 7-10 seconds to invite him back.
- **Sound is the reward.** Pops walk up a pentatonic ladder (1.2 kHz → 2.9 kHz)
  so a run of hits sounds like a tune, and milestones play one of three
  whistled songs, including the classic wolf whistle.
- **Progress is drawn, not written.** The row of seeds along the top fills up
  toward the next song. The numeric score in the corner is for Joey.

## Practical tips for playing with Pepper

- A dry beak is keratin and often won't register on a capacitive screen. Most
  birds end up using their **tongue**, or a foot, which works fine. Let him
  figure it out; don't force it.
- Start him off by tapping a seed yourself while he watches.
- Keep the volume moderate — cockatiel hearing is sensitive, and the reward
  works better quiet than loud. The game's master volume is already set to 0.75.
- A screen protector is a good idea. Beaks are strong.
- Wipe the screen afterwards. You'll see why.

## Tuning

The knobs are all at the top of `src/game.lua`:

```lua
local REWARD_EVERY = 10     -- pops per cockatiel song
local PARTY_TIME   = 5.0    -- seconds of celebration
local IDLE_AFTER   = 14     -- seconds before attract mode
local BASE_TARGETS = 5      -- seeds on screen to start
local MAX_TARGETS  = 9      -- cap as the score climbs
local HOLD_TO_MUTE = 1.1    -- seconds to hold the hidden corner
```

Seed size and difficulty live at the top of `src/target.lua`:

```lua
local HIT_SCALE  = 2.4      -- invisible hit radius / visible radius
local DANCE_BOB  = 9        -- dance amplitude, in screen units
local DANCE_SWAY = 7
```

If Pepper is struggling, raise `HIT_SCALE` (costs nothing visually) or lower
`baseSpeed` in `Target.new`. To resize the seeds themselves, change
`baseRadius` in `Target.new` — the per-seed `size` multipliers in the `KIND`
table keep millet small and sunflower large relative to each other. Seed
colours and silhouettes are in the same file.

## Getting it on the iPhone

LÖVE for iOS has to be built in Xcode; there's no App Store shortcut.

1. Download the **iOS source** for LÖVE 11.4 from
   <https://love2d.org/> (the `love-11.4-ios-source.zip` package).
2. Open `platform/xcode/love.xcodeproj`.
3. Drag this whole project folder into the Xcode project so it's added to the
   `love-ios` target as a **folder reference** (blue icon) named `game`, or add
   a zipped `game.love` to the app bundle. Both are described in
   `readme-iOS.rtf` inside that download.
4. Select the **love-ios** scheme, pick your iPhone, set your signing team, and
   run.
5. In `Info.plist`, allow all orientations — the game re-lays out on `resize`,
   so portrait and landscape both work.

With a free Apple developer account the app expires after 7 days and needs
re-installing; a paid account gives you a year.

**Recommended iOS settings while Pepper plays:** turn on Guided Access
(Settings → Accessibility → Guided Access) so he can't swipe out of the game,
and lock the volume where you want it.

## Tests

There's a headless regression test that stubs the LÖVE API, so it runs with no
window or audio device:

```sh
luajit tests/headless.lua      # or: lua tests/headless.lua
```

It simulates ~3400 frames of play across desktop and phone-sized resizes,
exercises attract mode, celebrations, mute and the keyboard shortcuts, asserts
that no NaN reaches a colour/transform/audio sample, verifies every synthesised
whistle lands in cockatiel range (0.5–4 kHz), and measures seed size against
hit size so the targets can't quietly become unfair to hit.

## Layout

```
main.lua           LOVE callbacks, touch/mouse routing
conf.lua           window + module config
src/game.lua       state, scoring, celebrations, HUD
src/target.lua     the dancing seeds (movement + drawing)
src/effects.lua    bursts, rings, ripples, confetti, ambience
src/audio.lua      the whistle synthesiser
tests/headless.lua stubbed-LOVE regression test
```
