# deskcats

Cute little cats that roam around your macOS desktop.

DeskCats is a native macOS desktop pet written in Swift and AppKit. A few cats
walk along the bottom of your screen, just above the Dock. They float above your
other windows, but clicks anywhere that isn't a cat pass straight through, so
they never get in the way.

Each cat picks what to do next at random, weighted by its own personality
(some are playful, some are lazy), so no two cats move in step. They walk,
sit, groom, stretch, yawn, nap (with little "z"s), loaf with their paws tucked,
slow-blink at you, chase their tails, bat at a butterfly, hop, pounce, and
scratch behind an ear. Their eyes follow your mouse pointer when it comes near.

## Playing with the cats

- **Pick one up**: press on a cat and drag. It dangles by the scruff and
  swings as you move. Let go and it drops back down to the floor, usually
  tidying itself up before wandering off again.
- **Pet one**: click a cat without dragging. It purrs and shows little hearts.

## Requirements

- macOS 13 or later (developed on macOS 15)
- Swift 6 toolchain (Xcode or the Command Line Tools)

## Build and run

From the repository root:

```sh
swift build    # compile
swift run      # build if needed, then launch the cats
```

For the lowest CPU use, run an optimized build: `swift run -c release`.

Three cats appear the first time the app starts. After that, DeskCats
remembers how many cats you had, their coats, and the size you chose, so the
same cats come back next launch. DeskCats has no Dock icon and no window of its
own. You control it from the 🐱 item in the menu bar.

## The menu-bar item

Click the 🐱 in the menu bar:

- **Add a cat**: a new cat appears, wearing a coat that isn't already on screen
  where possible (orange tabby, black, white, grey, calico, tuxedo, brown tabby,
  Siamese).
- **Remove a cat**: the most recently added cat leaves.
- **Size**: Small, Medium (the default), or Large. This rescales every cat and
  its walking speed straight away.
- The greyed-out line shows how many cats are on your desk.
- **Quit DeskCats** (⌘Q) closes the app. Pressing Ctrl-C in the terminal that
  ran `swift run`, or sending `kill`, also quits cleanly.

## How it works

- `OverlayWindow` is a borderless, transparent, shadowless, non-activating
  panel the size of the main screen. It sits at status-bar level and appears on
  every Space. It normally sets `ignoresMouseEvents`, so clicks reach whatever
  is underneath. Each frame, `AppDelegate` checks whether the pointer is over a
  cat and accepts mouse events only then, so you can grab a cat without
  blocking anything else. Grabbing a cat never takes focus from the app you
  are using.
- `Cat` is a state machine with weighted random transitions and randomized
  durations. It stays inside the screen's visible frame.
- `CatPainter` draws each cat with vector shapes. There are no image assets.
- `CatView` draws one cat, handles the mouse, and floats the "z"s and hearts.
  Resting cats are redrawn less often to keep CPU use low.
- `AppDelegate` runs everything on a 30 fps timer and owns the menu-bar item.

Developer aid: `swift run DeskCats --render-sheet poses.png` writes every coat
in every pose to a single PNG, so you can check the drawing without the overlay.
