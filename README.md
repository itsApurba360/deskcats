# deskcats

Cute little cats that roam around your macOS desktop.

DeskCats is a native macOS desktop pet written in Swift and AppKit. A few cats
walk along the bottom of your screen, just above the Dock. They sit, groom,
stretch, nap (with little "z"s), and look at your mouse pointer when it comes
near. They float above your other windows, but every click passes straight
through them, so they never get in the way.

## Requirements

- macOS 13 or later (developed on macOS 15)
- Swift 6 toolchain (Xcode or the Command Line Tools)

## Build and run

From the repository root:

```sh
swift build    # compile
swift run      # build if needed, then launch the cats
```

Three cats appear when the app starts. DeskCats has no Dock icon and no window
of its own. You control it from the 🐱 item in the menu bar.

## The menu-bar item

Click the 🐱 in the menu bar:

- **Add a cat**: a new cat appears, wearing a coat that isn't already on screen
  where possible (orange tabby, black, white, grey, calico, tuxedo, brown tabby,
  Siamese).
- **Remove a cat**: the most recently added cat leaves.
- The greyed-out line shows how many cats are on your desk.
- **Quit DeskCats** (⌘Q) closes the app. Pressing Ctrl-C in the terminal that
  ran `swift run`, or sending `kill`, also quits cleanly.

## How it works

- `OverlayWindow` is a borderless, transparent, shadowless window the size of
  the main screen. It sits at status-bar level and appears on every Space. It
  sets `ignoresMouseEvents`, so clicks reach whatever is underneath.
- `Cat` is a small state machine (walk, idle, sit, sleep, stretch, groom) that
  moves through random states with calm dwell times. It stays inside the
  screen's visible frame.
- `CatPainter` draws each cat with vector shapes. There are no image assets.
- `AppDelegate` runs everything on a 30 fps timer and owns the menu-bar item.

Developer aid: `swift run DeskCats --render-sheet poses.png` writes every coat
in every pose to a single PNG, so you can check the drawing without the overlay.
