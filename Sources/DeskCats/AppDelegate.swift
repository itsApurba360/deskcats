import AppKit
import QuartzCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, CatViewDelegate {
    private static let startingCats = 3
    private static let maxCats = 24
    private static let sizes: [(name: String, scale: CGFloat)] = [("Small", 0.7), ("Medium", 1), ("Large", 1.45)]

    /// One overlay per Space the cats have been on. Each stays on its own Space.
    private var windows: [UInt64: OverlayWindow] = [:]
    /// The Space on screen, and every Space left to right, as last seen.
    private var activeSpace: UInt64 = 0
    private var spaceOrder: [UInt64] = []
    /// Stands in for Space IDs if the system won't say which Space is showing.
    private var guessedSpace: UInt64 = 1
    private var statusItem: NSStatusItem!
    private var removeItem: NSMenuItem!
    private var addItem: NSMenuItem!
    private var countItem: NSMenuItem!
    private var sizeItems: [NSMenuItem] = []
    private var styleItems: [NSMenuItem] = []
    private var style: RenderStyle = Cat3DView.isSupported ? .threeD : .flat
    private var displayScale: CGFloat = 1
    /// The cat being carried, if any.
    private var dragged: CatView?
    private var lastDragTime = CACurrentMediaTime()
    private var cats: [CatView] = []
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var signalSources: [DispatchSourceSignal] = []
    private var area = RoamArea(visibleFrame: .zero, screen: .zero, catScale: 1)

    /// The display with the menu bar.
    private var mainScreen: NSScreen? { NSScreen.screens.first }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = mainScreen else {
            NSApp.terminate(nil)
            return
        }
        activeSpace = Spaces.active ?? guessedSpace
        spaceOrder = Spaces.ordered ?? []
        updateArea(for: screen)
        showWindow(on: activeSpace)

        if let name = Settings.size, let size = Self.sizes.first(where: { $0.name == name }) {
            displayScale = size.scale
            updateArea(for: screen)
        }
        if let saved = Settings.style, saved != .threeD || Cat3DView.isSupported { style = saved }
        setUpStatusItem()
        // A first launch starts with a few cats in fresh coats.
        let coats: [Coat?] = Settings.coats ?? Array(repeating: nil, count: Self.startingCats)
        for coat in coats.prefix(Self.maxCats) { addCat(coat: coat) }
        saveCats()

        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        lastTick = CACurrentMediaTime()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Swiping to another desktop or full-screen app, closing a full-screen app,
        // and removing a desktop all switch the active Space.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        quitOnSignals()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    // MARK: - Animation

    private func tick() {
        let now = CACurrentMediaTime()
        // Clamp the step so a stall (sleep, debugger) doesn't teleport the cats.
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        let mouse = NSEvent.mouseLocation
        let origin = mainScreen?.frame.origin ?? .zero
        let local = CGPoint(x: mouse.x - origin.x, y: mouse.y - origin.y)
        for view in cats {
            view.cat.update(dt: dt, area: area, mouse: local)
            if view.cat.hasLeftForSpace { arrive(view) }
            view.syncFrame()
        }
        maybeWander(dt: dt)
        updateClickThrough(mouse: local)
    }

    /// Accepts mouse events only while the cursor is over a cat, so clicks
    /// everywhere else keep reaching the windows underneath.
    private func updateClickThrough(mouse: CGPoint) {
        // Safety net: if a mouse-up never reached us, drop the cat rather than
        // leaving the overlay swallowing clicks.
        if let dragged, NSEvent.pressedMouseButtons == 0 {
            catViewDidEndDrag(dragged)
        }
        // Never switch mid-press: that would cut a drag (ours or another app's) short.
        guard NSEvent.pressedMouseButtons == 0, dragged == nil else { return }
        for (space, window) in windows {
            let overCat = catView(at: mouse, on: space) != nil
            if window.ignoresMouseEvents == overCat {
                window.ignoresMouseEvents = !overCat
            }
        }
    }

    /// The front-most cat on `space` whose body is under `point` (overlay coordinates).
    private func catView(at point: CGPoint, on space: UInt64) -> CatView? {
        if let dragged { return dragged.space == space ? dragged : nil }
        return cats
            .filter { $0.space == space && $0.superview != nil && $0.cat.hitRect.contains(point) }
            .min { $0.cat.position.y < $1.cat.position.y }
    }

    private func updateArea(for screen: NSScreen) {
        let origin = screen.frame.origin
        area = RoamArea(visibleFrame: screen.visibleFrame.offsetBy(dx: -origin.x, dy: -origin.y),
                        screen: CGRect(origin: .zero, size: screen.frame.size), catScale: displayScale)
    }

    @objc private func screensChanged() {
        guard let screen = mainScreen else { return }
        for window in windows.values { window.setFrame(screen.frame, display: false) }
        updateArea(for: screen)
        for view in cats {
            view.cat.reclamp(to: area)
            view.syncFrame()
        }
        spaceChanged()
    }

    // MARK: - Spaces

    /// Shows an overlay on `space`, which must be the Space on screen right now:
    /// a new window joins whichever Space is showing and then stays there.
    @discardableResult
    private func showWindow(on space: UInt64) -> OverlayWindow? {
        if let window = windows[space] { return window }
        guard let screen = mainScreen else { return nil }
        let window = OverlayWindow(screen: screen) { [weak self] point in self?.catView(at: point, on: space) }
        window.orderFrontRegardless()
        windows[space] = window
        return window
    }

    /// The user moved to another Space. Every cat elsewhere hesitates a moment,
    /// then walks or runs off its screen toward the new Space and comes in from
    /// the other side once it has covered the distance.
    @objc private func spaceChanged() {
        let previousOrder = spaceOrder
        if let id = Spaces.active {
            activeSpace = id
        } else {
            // Without the system's answer every switch looks like a new Space.
            guessedSpace += 1
            activeSpace = guessedSpace
        }
        spaceOrder = Spaces.ordered ?? []

        // A closed full-screen app or removed desktop takes its overlay with it.
        // Its cats carry on out of sight and still have to make the trip.
        if !spaceOrder.isEmpty {
            for (space, window) in windows where space != activeSpace && !spaceOrder.contains(space) {
                for view in cats where view.space == space { view.removeFromSuperview() }
                window.close()
                windows[space] = nil
            }
        }
        showWindow(on: activeSpace)

        for view in cats where view !== dragged {
            if view.space == activeSpace {
                // Back where it started: a cat still on its way out turns around.
                view.destination = nil
                view.cat.comeBack(area: area)
                continue
            }
            view.destination = activeSpace
            let direction = direction(from: view.space, to: activeSpace, previousOrder: previousOrder)
            // Some cats follow at once, others dawdle for a few seconds.
            let delay = Double.random(in: 0...1) < 0.3 ? 0 : .random(in: 0.2...3.5)
            view.cat.setOff(direction: direction, delay: delay, area: area)
        }
    }

    /// +1 if `to` is to the right of `from` in the trackpad order, -1 if left.
    private func direction(from: UInt64, to: UInt64, previousOrder: [UInt64]) -> CGFloat {
        for order in [spaceOrder, previousOrder] {
            if let i = order.firstIndex(of: from), let j = order.firstIndex(of: to), i != j {
                return j > i ? 1 : -1
            }
        }
        // A Space that has gone: compare where it was with where the new one is.
        if let i = previousOrder.firstIndex(of: from), let j = spaceOrder.firstIndex(of: to) {
            return j >= i ? 1 : -1
        }
        // No order at all: a stable guess for this pair.
        return from < to ? 1 : -1
    }

    /// A cat that has walked off its old Space steps onto the one it was heading for.
    private func arrive(_ view: CatView) {
        // If that Space has gone since, it comes to the one on screen instead.
        let space = view.destination.flatMap { windows[$0] != nil ? $0 : nil } ?? activeSpace
        guard let content = windows[space]?.contentView else { return }
        if view.superview !== content {
            view.removeFromSuperview()
            content.addSubview(view)
        }
        view.space = space
        view.destination = nil
        view.cat.enter(area: area)
    }

    /// Rarely, one cat wanders off to a neighbouring desktop and comes back later.
    /// At least one cat always stays behind.
    private func maybeWander(dt: TimeInterval) {
        guard Double.random(in: 0..<1) < dt / 240 else { return }
        let home = cats.filter { $0.space == activeSpace && !$0.cat.isTravelling && $0 !== dragged }
        guard home.count >= 2, let view = home.randomElement() else { return }
        view.cat.wander(area: area)
    }

    // MARK: - Cats

    @objc private func addCatFromMenu() {
        addCat()
        saveCats()
    }

    /// Adds a cat wearing `coat`, or a coat not already on screen where possible.
    private func addCat(coat: Coat? = nil) {
        guard cats.count < Self.maxCats, let content = showWindow(on: activeSpace)?.contentView else { return }
        let used = cats.map(\.cat.coat)
        let fresh = Coat.all.filter { !used.contains($0) }
        let coat = coat ?? (fresh.isEmpty ? Coat.all : fresh).randomElement()!
        let start = CGPoint(x: .random(in: area.minX...area.maxX), y: area.floor + .random(in: 0...4))
        let cat = Cat(coat: coat, position: start, activity: Cat.Activity.roaming.randomElement()!,
                      area: area, displayScale: displayScale)
        let view = CatView(cat: cat, style: style)
        view.space = activeSpace
        view.delegate = self
        content.addSubview(view)
        cats.append(view)
        updateMenu()
    }

    @objc private func removeCat() {
        guard let view = cats.popLast() else { return }
        if view === dragged { dragged = nil }
        view.removeFromSuperview()
        updateMenu()
        saveCats()
    }

    /// Remembers which cats are on the desk so the same ones come back next launch.
    private func saveCats() {
        Settings.coats = cats.map(\.cat.coat)
    }

    @objc private func chooseSize(_ sender: NSMenuItem) {
        displayScale = Self.sizes[sender.tag].scale
        Settings.size = Self.sizes[sender.tag].name
        for item in sizeItems { item.state = item === sender ? .on : .off }
        if let screen = mainScreen { updateArea(for: screen) }
        for view in cats {
            view.cat.displayScale = displayScale
            view.cat.reclamp(to: area)
            view.syncFrame()
        }
    }

    @objc private func chooseStyle(_ sender: NSMenuItem) {
        style = RenderStyle.allCases[sender.tag]
        Settings.style = style
        for item in styleItems { item.state = item === sender ? .on : .off }
        for view in cats { view.style = style }
    }

    // MARK: - Dragging

    func catViewDidStartDrag(_ view: CatView, at point: CGPoint) {
        dragged = view
        // Picked up mid-trip, it stays on this Space.
        view.destination = nil
        lastDragTime = CACurrentMediaTime()
        view.cat.grab(at: point)
        view.syncFrame()
    }

    func catView(_ view: CatView, didDragTo point: CGPoint) {
        let now = CACurrentMediaTime()
        view.cat.carry(to: point, dt: now - lastDragTime, area: area)
        lastDragTime = now
        view.syncFrame()
    }

    func catViewDidEndDrag(_ view: CatView) {
        view.cat.drop()
        dragged = nil
    }

    func catViewWasClicked(_ view: CatView) {
        view.cat.pet(area: area)
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐱"
        statusItem.button?.toolTip = "DeskCats"

        let menu = NSMenu()
        menu.autoenablesItems = false
        addItem = NSMenuItem(title: "Add a cat", action: #selector(addCatFromMenu), keyEquivalent: "")
        addItem.target = self
        removeItem = NSMenuItem(title: "Remove a cat", action: #selector(removeCat), keyEquivalent: "")
        removeItem.target = self
        countItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        countItem.isEnabled = false
        let quitItem = NSMenuItem(title: "Quit DeskCats", action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        quitItem.target = NSApp

        let sizeMenu = NSMenu()
        sizeMenu.autoenablesItems = false
        for (index, size) in Self.sizes.enumerated() {
            let item = NSMenuItem(title: size.name, action: #selector(chooseSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = size.scale == displayScale ? .on : .off
            sizeMenu.addItem(item)
            sizeItems.append(item)
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu

        let styleMenu = NSMenu()
        styleMenu.autoenablesItems = false
        for (index, option) in RenderStyle.allCases.enumerated() {
            let item = NSMenuItem(title: option.title, action: #selector(chooseStyle(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = option == style ? .on : .off
            item.isEnabled = option != .threeD || Cat3DView.isSupported
            styleMenu.addItem(item)
            styleItems.append(item)
        }
        let styleItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        styleItem.submenu = styleMenu

        menu.addItem(addItem)
        menu.addItem(removeItem)
        menu.addItem(sizeItem)
        menu.addItem(styleItem)
        menu.addItem(.separator())
        menu.addItem(countItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu
        updateMenu()
    }

    private func updateMenu() {
        guard countItem != nil else { return }
        countItem.title = cats.count == 1 ? "1 cat on your desk" : "\(cats.count) cats on your desk"
        removeItem.isEnabled = !cats.isEmpty
        addItem.isEnabled = cats.count < Self.maxCats
    }

    // MARK: - Shutdown

    /// Ctrl-C or `kill` quits through AppKit, like choosing Quit from the menu.
    private func quitOnSignals() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
