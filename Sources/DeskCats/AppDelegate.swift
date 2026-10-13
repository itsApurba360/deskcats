import AppKit
import QuartzCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let startingCats = 3
    private static let maxCats = 24

    private var window: OverlayWindow!
    private var statusItem: NSStatusItem!
    private var removeItem: NSMenuItem!
    private var addItem: NSMenuItem!
    private var countItem: NSMenuItem!
    private var cats: [CatView] = []
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var signalSources: [DispatchSourceSignal] = []
    private var area = RoamArea(visibleFrame: .zero)

    /// The display with the menu bar.
    private var mainScreen: NSScreen? { NSScreen.screens.first }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = mainScreen else {
            NSApp.terminate(nil)
            return
        }
        window = OverlayWindow(screen: screen)
        updateArea(for: screen)
        window.orderFrontRegardless()

        setUpStatusItem()
        for _ in 0..<Self.startingCats { addCat() }

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
    }

    private func updateArea(for screen: NSScreen) {
        let origin = screen.frame.origin
        area = RoamArea(visibleFrame: screen.visibleFrame.offsetBy(dx: -origin.x, dy: -origin.y))
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

    @objc private func addCat() {
        guard cats.count < Self.maxCats, let content = window.contentView else { return }
        let used = cats.map(\.cat.coat)
        let fresh = Coat.all.filter { !used.contains($0) }
        let coat = (fresh.isEmpty ? Coat.all : fresh).randomElement()!
        let start = CGPoint(x: .random(in: area.minX...area.maxX), y: area.floor + .random(in: 0...4))
        let cat = Cat(coat: coat, position: start,
                      activity: [.walk, .walk, .idle, .sit].randomElement()!, area: area)
        let view = CatView(cat: cat)
        content.addSubview(view)
        cats.append(view)
        updateMenu()
    }

    @objc private func removeCat() {
        guard let view = cats.popLast() else { return }
        view.removeFromSuperview()
        updateMenu()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐱"
        statusItem.button?.toolTip = "DeskCats"

        let menu = NSMenu()
        menu.autoenablesItems = false
        addItem = NSMenuItem(title: "Add a cat", action: #selector(addCat), keyEquivalent: "")
        addItem.target = self
        removeItem = NSMenuItem(title: "Remove a cat", action: #selector(removeCat), keyEquivalent: "")
        removeItem.target = self
        countItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        countItem.isEnabled = false
        let quitItem = NSMenuItem(title: "Quit DeskCats", action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        quitItem.target = NSApp

        menu.addItem(addItem)
        menu.addItem(removeItem)
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
