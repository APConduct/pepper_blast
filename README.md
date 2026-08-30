# Pepper Blast

A tap game for **Pepper**, Joey's cockatiel. 🦜

Brightly coloured snacks dance around the screen. Pepper touches one, it pops
with a chirp, and the chirps climb a scale as he keeps going. Every 10 pops the
screen throws confetti and a synthesised cockatiel song plays.

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
| Tap / click a snack | pop, chirp, +1 point |
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
- **Huge, high-contrast targets.** Fully saturated fills with hard white
  outlines on a dark background. Hit areas are 1.3× the visible radius.
- **Curiosity pull.** For ~1.5s after a touch, the snacks drift gently toward
  wherever Pepper touched. It quietly converts near-misses into hits.
- **Attract mode.** After 14 seconds of no play, the snacks slow down, grow,
  gather toward the centre, and the game whistles a cockatiel *contact call*
  every 7-10 seconds to invite him back.
- **Sound is the reward.** Pops walk up a pentatonic ladder (1.2 kHz → 2.9 kHz)
  so a run of hits sounds like a tune, and milestones play one of three
  whistled songs, including the classic wolf whistle.
- **Progress is drawn, not written.** The row of seeds along the top fills up
  toward the next song. The numeric score in the corner is for Joey.

## Practical tips for playing with Pepper

- A dry beak is keratin and often won't register on a capacitive screen. Most
  birds end up using their **tongue**, or a foot, which works fine. Let him
  figure it out; don't force it.
- Start him off by tapping a snack yourself while he watches.
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
local BASE_TARGETS = 3      -- snacks on screen to start
local MAX_TARGETS  = 6      -- cap as the score climbs
local HOLD_TO_MUTE = 1.1    -- seconds to hold the hidden corner
```

If Pepper is struggling, raise the hit radius multiplier in
`Target:contains` (`src/target.lua`) or lower `baseSpeed` in `Target.new`.
Colours and shapes live in the same file.

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
that no NaN reaches a colour/transform/audio sample, and verifies every
synthesised whistle lands in cockatiel range (0.5–4 kHz).

## Layout

```
main.lua           LOVE callbacks, touch/mouse routing
conf.lua           window + module config
src/game.lua       state, scoring, celebrations, HUD
src/target.lua     the dancing snacks (movement + drawing)
src/effects.lua    bursts, rings, ripples, confetti, ambience
src/audio.lua      the whistle synthesiser
tests/headless.lua stubbed-LOVE regression test
```
