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

When you switch desktops or full-screen apps (or close one), the cats stay put on the old one, then each one, after a moment's hesitation, walks or runs off the side toward you and comes in from the other side to its old spot. Now and then a cat wanders off to a neighbouring desktop for a while and comes back.

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
remembers how many cats you had, their coats, the size, and the style you
chose, so the same cats come back next launch. DeskCats has no Dock icon and no window of its
own. You control it from the 🐱 item in the menu bar.

## The menu-bar item

Click the 🐱 in the menu bar:

- **Add a cat**: a new cat appears, wearing a coat that isn't already on screen
  where possible (orange tabby, black, white, grey, calico, tuxedo, brown tabby,
  Siamese).
- **Remove a cat**: the most recently added cat leaves.
- **Size**: Small, Medium (the default), or Large. This rescales every cat and
  its walking speed straight away.
- **Style**: 3D (the default) draws round, softly lit cats with SceneKit; Flat
  draws the original 2D cartoon cats. Switching takes effect straight away.
- The greyed-out line shows how many cats are on your desk.
- **Quit DeskCats** (⌘Q) closes the app. Pressing Ctrl-C in the terminal that
  ran `swift run`, or sending `kill`, also quits cleanly.

## How it works

- `OverlayWindow` is a borderless, transparent, shadowless, non-activating
  panel the size of the main screen. It sits at status-bar level, above
  full-screen apps too. There is one per Space the cats have visited, and each
  stays on its own Space, so cats slide away with their desktop when you
  swipe. `Spaces` reads the Space order from private CoreGraphics calls, so a
  cat knows which edge to leave by. Each overlay normally sets `ignoresMouseEvents`, so clicks reach whatever
  is underneath. Each frame, `AppDelegate` checks whether the pointer is over a
  cat and accepts mouse events only then, so you can grab a cat without
  blocking anything else. Grabbing a cat never takes focus from the app you
  are using.
- `Cat` is a state machine with weighted random transitions and randomized
  durations. It stays inside the screen's visible frame.
- `CatPainter` draws each flat cat with vector shapes. There are no image assets.
- `Cat3DView` builds each 3D cat from SceneKit spheres, cones, cylinders, and
  capsules, and poses it every frame from the same `Cat` state. It uses a
  transparent background and an orthographic camera, so the 3D cat lines up
  with the flat cat's position and hit area.
- `CatView` draws one cat (flat, or through its `Cat3DView`), handles the
  mouse, and floats the "z"s and hearts. Resting cats are redrawn less often to
  keep CPU use low.
- `Settings` keeps the cats' coats, the size, and the style in `UserDefaults`.
- `AppDelegate` runs everything on a 30 fps timer and owns the menu-bar item.

Developer aid: `swift run DeskCats --render-sheet poses.png` writes every coat
in every pose to a single PNG, so you can check the drawing without the overlay.
