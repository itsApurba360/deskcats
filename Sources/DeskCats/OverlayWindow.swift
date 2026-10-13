import AppKit

/// A transparent window covering the main screen that the cats live in.
///
/// It is click-through (`ignoresMouseEvents`) except while the cursor is over a
/// cat; `AppDelegate` flips that each frame so a cat can be picked up.
@MainActor
final class OverlayWindow: NSPanel {
    init(screen: NSScreen, catAt: @escaping (CGPoint) -> CatView?) {
        // Non-activating, so grabbing a cat never steals focus from the app you're using.
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        // Every click, scroll, and drag passes straight through to the windows underneath.
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        let content = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        content.catAt = catAt
        content.wantsLayer = true
        contentView = content
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Routes clicks to the cat under the cursor rather than to whichever view frame is on top.
@MainActor
private final class OverlayView: NSView {
    var catAt: ((CGPoint) -> CatView?)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        return catAt?(local)
    }
}
