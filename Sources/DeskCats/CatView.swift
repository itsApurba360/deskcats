import AppKit

/// A small transparent view that follows one cat around the overlay and draws it.
@MainActor
final class CatView: NSView {
    /// Overall drawing scale applied on top of each cat's own size.
    static let baseScale: CGFloat = 1.2
    static let size = CGSize(width: 170, height: 140)
    /// Where the cat's ground point sits inside the view.
    static let anchor = CGPoint(x: 85, y: 12)

    let cat: Cat

    init(cat: Cat) {
        self.cat = cat
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        syncFrame()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isOpaque: Bool { false }

    /// Moves the view to the cat's position and keeps cats nearer the floor in front.
    func syncFrame() {
        let origin = CGPoint(x: (cat.position.x - Self.anchor.x).rounded(),
                             y: (cat.position.y - Self.anchor.y).rounded())
        if frame.origin != origin { setFrameOrigin(origin) }
        layer?.zPosition = -cat.position.y
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let look = CGVector(dx: cat.facingRight ? cat.look.dx : -cat.look.dx, dy: cat.look.dy)
        let pose = CatPainter.Pose(coat: cat.coat, activity: cat.activity, progress: cat.activityProgress,
                                   legPhase: cat.legPhase, age: cat.age, blinking: cat.blinking, look: look)
        Self.render(pose, scale: Self.baseScale * cat.size, facingRight: cat.facingRight, at: Self.anchor)
    }

    /// Paints a pose with its ground point at `anchor` in the current graphics context.
    static func render(_ pose: CatPainter.Pose, scale: CGFloat, facingRight: Bool, at anchor: CGPoint) {
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: anchor.x, yBy: anchor.y)
        t.scaleX(by: facingRight ? scale : -scale, yBy: scale)
        t.concat()
        CatPainter(pose: pose).paint()
        NSGraphicsContext.restoreGraphicsState()

        if pose.activity == .sleep {
            drawZs(pose: pose, scale: scale, facingRight: facingRight, anchor: anchor)
        }
    }

    /// Little "z"s drifting up from a sleeping cat, drawn unmirrored so they stay readable.
    private static func drawZs(pose: CatPainter.Pose, scale: CGFloat, facingRight: Bool, anchor: CGPoint) {
        let head = CatPainter.sleepingHead
        let direction: CGFloat = facingRight ? 1 : -1
        let start = CGPoint(x: anchor.x + direction * (head.x + 6) * scale, y: anchor.y + (head.y + 12) * scale)
        for i in 0..<3 {
            var phase = pose.age * 0.32 + Double(i) / 3
            phase -= phase.rounded(.down)
            let alpha = sin(phase * .pi)
            let fontSize = (8 + 7 * phase) * scale
            let point = CGPoint(x: start.x + direction * CGFloat(phase) * 16 * scale + CGFloat(sin(phase * 6)) * 3,
                                y: start.y + CGFloat(phase) * 42 * scale)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
                .foregroundColor: NSColor(srgbRed: 0.93, green: 0.95, blue: 1, alpha: alpha),
                .strokeColor: NSColor(srgbRed: 0.2, green: 0.24, blue: 0.4, alpha: alpha),
                .strokeWidth: -3.5,
            ]
            ("z" as NSString).draw(at: point, withAttributes: attributes)
        }
    }
}
