import AppKit

/// A transparent, click-through window covering the main screen that the cats live in.
@MainActor
final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        // Every click, scroll, and drag passes straight through to the windows underneath.
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        let content = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        content.wantsLayer = true
        contentView = content
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
