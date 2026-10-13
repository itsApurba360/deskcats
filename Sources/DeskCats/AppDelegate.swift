import AppKit
import QuartzCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, CatViewDelegate {
    private static let startingCats = 3
    private static let maxCats = 24
    private static let sizes: [(name: String, scale: CGFloat)] = [("Small", 0.7), ("Medium", 1), ("Large", 1.45)]

    private var window: OverlayWindow!
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
        window = OverlayWindow(screen: screen) { [weak self] point in self?.catView(at: point) }
        updateArea(for: screen)
        window.orderFrontRegardless()

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
        let local = CGPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)
        for view in cats {
            view.cat.update(dt: dt, area: area, mouse: local)
            view.syncFrame()
        }
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
        let overCat = catView(at: mouse) != nil
        if window.ignoresMouseEvents == overCat {
            window.ignoresMouseEvents = !overCat
        }
    }

    /// The front-most cat whose body is under `point` (overlay coordinates).
    private func catView(at point: CGPoint) -> CatView? {
        if let dragged { return dragged }
        return cats
            .filter { $0.cat.hitRect.contains(point) }
            .min { $0.cat.position.y < $1.cat.position.y }
    }

    private func updateArea(for screen: NSScreen) {
        let origin = screen.frame.origin
        area = RoamArea(visibleFrame: screen.visibleFrame.offsetBy(dx: -origin.x, dy: -origin.y),
                        screen: CGRect(origin: .zero, size: screen.frame.size), catScale: displayScale)
    }

    @objc private func screensChanged() {
        guard let screen = mainScreen else { return }
        window.setFrame(screen.frame, display: false)
        updateArea(for: screen)
        for view in cats {
            view.cat.reclamp(to: area)
            view.syncFrame()
        }
    }

    // MARK: - Cats

    @objc private func addCatFromMenu() {
        addCat()
        saveCats()
    }

    /// Adds a cat wearing `coat`, or a coat not already on screen where possible.
    private func addCat(coat: Coat? = nil) {
        guard cats.count < Self.maxCats, let content = window.contentView else { return }
        let used = cats.map(\.cat.coat)
        let fresh = Coat.all.filter { !used.contains($0) }
        let coat = coat ?? (fresh.isEmpty ? Coat.all : fresh).randomElement()!
        let start = CGPoint(x: .random(in: area.minX...area.maxX), y: area.floor + .random(in: 0...4))
        let cat = Cat(coat: coat, position: start, activity: Cat.Activity.roaming.randomElement()!,
                      area: area, displayScale: displayScale)
        let view = CatView(cat: cat, style: style)
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
