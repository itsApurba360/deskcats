import AppKit

/// Receives a cat view's mouse gestures.
@MainActor
protocol CatViewDelegate: AnyObject {
    func catViewDidStartDrag(_ view: CatView, at point: CGPoint)
    func catView(_ view: CatView, didDragTo point: CGPoint)
    func catViewDidEndDrag(_ view: CatView)
    func catViewWasClicked(_ view: CatView)
}

/// A small transparent view that follows one cat around the overlay and draws it,
/// either flat or, through a `Cat3DView` subview, in 3D.
@MainActor
final class CatView: NSView {
    /// Overall drawing scale applied on top of each cat's own size.
    static let baseScale: CGFloat = 1.2
    private static let baseSize = CGSize(width: 170, height: 170)
    /// Where the cat's ground point sits inside a Medium-sized view.
    private static let baseAnchor = CGPoint(x: 85, y: 12)
    /// How far the mouse must move before a press becomes a drag.
    private static let dragThreshold: CGFloat = 3

    let cat: Cat
    weak var delegate: CatViewDelegate?
    private var pressPoint: CGPoint?
    private var dragging = false
    private var framesSinceDraw = 0
    private var drawnState: (Cat.Activity, Bool, Bool)?
    private var scene: Cat3DView?
    /// Draws the "z"s and hearts above the 3D cat.
    private var floaters: FloaterView?

    var style: RenderStyle = .flat {
        didSet {
            guard style != oldValue else { return }
            applyStyle()
        }
    }

    private var anchor: CGPoint {
        CGPoint(x: Self.baseAnchor.x * cat.displayScale, y: Self.baseAnchor.y * cat.displayScale)
    }

    init(cat: Cat, style: RenderStyle) {
        self.cat = cat
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        // Size the view first so a 3D scene never starts with an empty drawable.
        syncFrame()
        applyStyle()
    }

    private func applyStyle() {
        scene?.removeFromSuperview()
        floaters?.removeFromSuperview()
        scene = nil
        floaters = nil
        if style == .threeD {
            let scene = Cat3DView(coat: cat.coat)
            scene.frame = bounds
            scene.autoresizingMask = [.width, .height]
            addSubview(scene)
            let floaters = FloaterView(frame: bounds)
            floaters.autoresizingMask = [.width, .height]
            floaters.catView = self
            addSubview(floaters)
            self.scene = scene
            self.floaters = floaters
            scene.frame(anchor: anchor)
            scene.update(from: cat)
        }
        drawnState = nil
        needsDisplay = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isOpaque: Bool { false }

    /// Moves and sizes the view to match the cat, keeping cats nearer the floor in front.
    func syncFrame() {
        let size = CGSize(width: Self.baseSize.width * cat.displayScale,
                          height: Self.baseSize.height * cat.displayScale)
        if frame.size != size {
            setFrameSize(size)
            scene?.frame(anchor: anchor)
        }
        let origin = CGPoint(x: (cat.position.x - anchor.x).rounded(),
                             y: (cat.position.y - anchor.y).rounded())
        if frame.origin != origin { setFrameOrigin(origin) }
        // A carried cat is always in front.
        layer?.zPosition = cat.isHeld || cat.activity == .falling ? 100_000 : -cat.position.y

        // Resting cats change slowly, so redraw them less often to keep CPU use low.
        let interval: Int
        switch cat.activity {
        case .sleep, .loaf: interval = 3
        case .sit, .idle, .slowBlink: interval = 2
        default: interval = 1
        }
        let state = (cat.activity, cat.blinking, cat.facingRight)
        framesSinceDraw += 1
        if framesSinceDraw >= interval || drawnState.map({ $0 != state }) ?? true {
            framesSinceDraw = 0
            drawnState = state
            if let scene {
                scene.update(from: cat)
                if Floaters.shows(for: pose) || floaters?.showing == true { floaters?.needsDisplay = true }
            } else {
                needsDisplay = true
            }
        }
    }

    fileprivate var pose: CatPainter.Pose {
        let look = CGVector(dx: cat.facingRight ? cat.look.dx : -cat.look.dx, dy: cat.look.dy)
        return CatPainter.Pose(coat: cat.coat, activity: cat.activity, progress: cat.activityProgress,
                               legPhase: cat.legPhase, age: cat.age, blinking: cat.blinking, look: look,
                               swing: cat.facingRight ? cat.swing : -cat.swing)
    }

    fileprivate var drawScale: CGFloat { Self.baseScale * cat.scale }

    override func draw(_ dirtyRect: NSRect) {
        guard scene == nil else { return }
        Self.render(pose, scale: drawScale, facingRight: cat.facingRight, at: anchor)
    }

    fileprivate func drawFloaters() {
        Floaters(pose: pose, scale: drawScale, facingRight: cat.facingRight, anchor: anchor).draw()
    }

    // MARK: - Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override func accessibilityLabel() -> String? { "\(cat.coat.name) cat" }
    override func accessibilityValue() -> Any? { String(describing: cat.activity) }

    /// Reports the cat's body rather than the whole padded view.
    override func accessibilityFrame() -> NSRect {
        window?.convertToScreen(cat.hitRect) ?? super.accessibilityFrame()
    }

    // MARK: - Mouse

    // The overlay never becomes key, so the first click must count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressPoint = event.locationInWindow
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressPoint else { return }
        let point = event.locationInWindow
        if !dragging, hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold {
            dragging = true
            delegate?.catViewDidStartDrag(self, at: point)
        }
        if dragging { delegate?.catView(self, didDragTo: point) }
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            delegate?.catViewDidEndDrag(self)
        } else if pressPoint != nil {
            delegate?.catViewWasClicked(self)
        }
        pressPoint = nil
        dragging = false
    }

    // MARK: - Rendering

    /// Paints a pose with its ground point at `anchor` in the current graphics context.
    static func render(_ pose: CatPainter.Pose, scale: CGFloat, facingRight: Bool, at anchor: CGPoint) {
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: anchor.x, yBy: anchor.y)
        t.scaleX(by: facingRight ? scale : -scale, yBy: scale)
        t.concat()
        CatPainter(pose: pose).paint()
        NSGraphicsContext.restoreGraphicsState()
        Floaters(pose: pose, scale: scale, facingRight: facingRight, anchor: anchor).draw()
    }
}

/// Sits on top of a 3D cat and draws only its floating "z"s and hearts.
@MainActor
private final class FloaterView: NSView {
    weak var catView: CatView?
    /// Whether the last draw showed anything, so it gets cleared once afterwards.
    private(set) var showing = false

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let catView else { return }
        showing = Floaters.shows(for: catView.pose)
        if showing { catView.drawFloaters() }
    }
}

/// Little symbols drifting up from a cat's head, drawn unmirrored so they stay readable.
@MainActor
private struct Floaters {
    static let heartFill = NSColor(srgbRed: 1, green: 0.5, blue: 0.62, alpha: 1)
    static let heartEdge = NSColor(srgbRed: 0.55, green: 0.12, blue: 0.25, alpha: 1)

    let pose: CatPainter.Pose
    let scale: CGFloat
    let facingRight: Bool
    let anchor: CGPoint

    static func shows(for pose: CatPainter.Pose) -> Bool {
        switch pose.activity {
        case .sleep, .purr: true
        case .slowBlink: pose.progress > 0.6
        default: false
        }
    }

    func draw() {
        switch pose.activity {
        case .sleep:
            draw("z", count: 3, rate: 0.32, fill: NSColor(srgbRed: 0.93, green: 0.95, blue: 1, alpha: 1),
                 edge: NSColor(srgbRed: 0.2, green: 0.24, blue: 0.4, alpha: 1))
        case .purr:
            draw("♥", count: 3, rate: 0.6, fill: Floaters.heartFill, edge: Floaters.heartEdge)
        case .slowBlink where pose.progress > 0.6:
            draw("♥", phase: Double((pose.progress - 0.6) / 0.4),
                 fill: Floaters.heartFill, edge: Floaters.heartEdge)
        default:
            break
        }
    }

    /// A repeating stream of `count` symbols.
    func draw(_ symbol: String, count: Int, rate: Double, fill: NSColor, edge: NSColor) {
        for i in 0..<count {
            var phase = pose.age * rate + Double(i) / Double(count)
            phase -= phase.rounded(.down)
            draw(symbol, phase: phase, fill: fill, edge: edge)
        }
    }

    /// One symbol, `phase` of the way (0...1) through its rise.
    func draw(_ symbol: String, phase: Double, fill: NSColor, edge: NSColor) {
        let head = CatPainter.headPoint(for: pose.activity)
        let direction: CGFloat = facingRight ? 1 : -1
        let start = CGPoint(x: anchor.x + direction * (head.x + 6) * scale, y: anchor.y + (head.y + 12) * scale)
        let p = CGFloat(phase)
        let alpha = sin(p * .pi)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: (8 + 7 * p) * scale, weight: .heavy),
            .foregroundColor: fill.withAlphaComponent(alpha),
            .strokeColor: edge.withAlphaComponent(alpha),
            .strokeWidth: -3.5,
        ]
        let point = CGPoint(x: start.x + direction * p * 16 * scale + sin(p * 6) * 3,
                            y: start.y + p * 42 * scale)
        (symbol as NSString).draw(at: point, withAttributes: attributes)
    }
}
