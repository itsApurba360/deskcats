import AppKit

/// Draws one cat with vector shapes.
///
/// Drawing happens in "cat space": the origin is the ground point under the
/// cat, +x points the way the cat faces, +y is up, and an average cat is about
/// 60 units long. The caller sets up the transform from cat space to the view.
@MainActor
struct CatPainter {
    /// What the painter needs from a cat, so poses can also be painted without a live cat.
    struct Pose {
        var coat: Coat
        var activity: Cat.Activity
        var progress: CGFloat
        var legPhase: CGFloat
        var age: TimeInterval
        var blinking: Bool
        /// Pupil direction in cat space (+x is forward).
        var look: CGVector
    }

    enum Eyes { case open, sleepy, happy }

    let pose: Pose
    private let coat: Coat
    private let ink: NSColor
    private let faceInk: NSColor

    init(pose: Pose) {
        self.pose = pose
        coat = pose.coat
        ink = coat.outline.color
        let face = coat.muzzle ?? coat.base
        let luminance = 0.299 * face.r + 0.587 * face.g + 0.114 * face.b
        faceInk = luminance < 0.4 ? NSColor(white: 0.82, alpha: 1) : coat.outline.color
    }

    // MARK: - Poses

    func paint() {
        shadow(width: pose.activity == .sleep ? 58 : 52)
        switch pose.activity {
        case .walk: paintStanding(walking: true, bow: 0)
        case .idle: paintStanding(walking: false, bow: 0)
        case .stretch: paintStanding(walking: false, bow: stretchAmount)
        case .sit: paintSitting(grooming: false)
        case .groom: paintSitting(grooming: true)
        case .sleep: paintSleeping()
        }
    }

    /// Where the sleeping head sits, so the view can float "z"s above it.
    static let sleepingHead = CGPoint(x: 17, y: 15)

    private var stretchAmount: CGFloat {
        let p = pose.progress
        if p < 0.3 { return ease(p / 0.3) }
        if p > 0.72 { return ease((1 - p) / 0.28) }
        return 1
    }

    private var tailSway: CGFloat { CGFloat(sin(pose.age * 1.6)) * 4 }

    private func paintStanding(walking: Bool, bow: CGFloat) {
        let phase = pose.legPhase
        let bob = walking ? abs(sin(phase)) * 1.4 : CGFloat(sin(pose.age * 2.2)) * 0.4
        let hipY = 20 + bob + bow * 4
        let shoulderY = 20 + bob - bow * 9
        let hip = CGPoint(x: -13, y: hipY)
        let shoulder = CGPoint(x: 13, y: shoulderY)

        func foot(_ x: CGFloat, _ phase: CGFloat) -> CGPoint {
            guard walking else { return CGPoint(x: x, y: 3) }
            return CGPoint(x: x + sin(phase) * 7, y: 3 + max(0, cos(phase)) * 3.5)
        }
        let reach = bow * 13

        // Tail first: it sits behind everything.
        let tailBase = CGPoint(x: hip.x - 8, y: hipY + 3)
        let lift = walking ? 0 : bow * 6
        tail(from: tailBase,
             c1: CGPoint(x: tailBase.x - 10, y: tailBase.y + 4),
             c2: CGPoint(x: tailBase.x - 15 + tailSway * 0.3, y: tailBase.y + 18 + lift),
             to: CGPoint(x: tailBase.x - 8 + tailSway, y: tailBase.y + 28 + lift))

        // Far legs, shaded darker.
        let far = coat.base.darker(0.1)
        let farPaw = coat.paws.darker(0.1)
        leg(from: CGPoint(x: shoulder.x + 3, y: shoulderY - 4), to: foot(shoulder.x + 3 + reach, phase + .pi),
            color: far, paw: farPaw)
        leg(from: CGPoint(x: hip.x + 3, y: hipY - 4), to: foot(hip.x + 3, phase), color: far, paw: farPaw)

        // Body: an ellipse tilted from hip to shoulder.
        let tilt = atan2(shoulderY - hipY, shoulder.x - hip.x)
        let center = CGPoint(x: 0, y: (hipY + shoulderY) / 2 + 2)
        let body = ellipse(center: center, width: 46, height: 24, rotation: tilt)
        blob(body) { rect in
            if let chest = coat.chest {
                chest.color.setFill()
                ellipse(center: CGPoint(x: rect.maxX - 12, y: rect.minY + 6), width: 22, height: 16).fill()
            }
        }

        // Near legs.
        leg(from: CGPoint(x: shoulder.x, y: shoulderY - 4), to: foot(shoulder.x + reach, phase),
            color: coat.base.color, paw: coat.paws.color)
        leg(from: CGPoint(x: hip.x, y: hipY - 4), to: foot(hip.x, phase + .pi),
            color: coat.base.color, paw: coat.paws.color)

        let yawning = bow > 0.6 && (0.38...0.66).contains(pose.progress)
        head(center: CGPoint(x: 22 + bow * 6, y: 34 + bob - bow * 13),
             radius: 13, tilt: -bow * 0.12,
             eyes: bow > 0.3 ? .happy : (pose.blinking ? .sleepy : .open),
             yawning: yawning)
    }

    private func paintSitting(grooming: Bool) {
        let breath = CGFloat(sin(pose.age * 2)) * 0.6
        let lick = CGFloat(sin(pose.age * 9))

        // Haunch and torso.
        blob(ellipse(center: CGPoint(x: -8, y: 12), width: 30, height: 23))
        let torso = ellipse(center: CGPoint(x: 2, y: 21 + breath * 0.5), width: 25, height: 33 + breath,
                            rotation: 0.12)
        blob(torso) { rect in
            if let chest = coat.chest {
                chest.color.setFill()
                ellipse(center: CGPoint(x: rect.maxX - 9, y: rect.midY + 2), width: 14, height: 24).fill()
            }
        }
        paw(at: CGPoint(x: -4, y: 3), color: coat.paws.color)

        // Front legs; when grooming, the near one is lifted to the mouth.
        leg(from: CGPoint(x: 8, y: 18), to: CGPoint(x: 8, y: 3),
            color: coat.base.darker(0.1), paw: coat.paws.darker(0.1))
        if !grooming {
            leg(from: CGPoint(x: 13, y: 18), to: CGPoint(x: 13, y: 3),
                color: coat.base.color, paw: coat.paws.color)
        }

        // Tail wrapped around the front paws.
        let sway = tailSway * 0.4
        tail(from: CGPoint(x: -18, y: 6),
             c1: CGPoint(x: -18, y: -1),
             c2: CGPoint(x: 8, y: -2),
             to: CGPoint(x: 21, y: 4 + sway))

        let headCenter = CGPoint(x: 6, y: 42 + breath * 0.4)
        head(center: headCenter, radius: 13.5,
             tilt: grooming ? -0.16 : 0,
             eyes: grooming ? .happy : (pose.blinking ? .sleepy : .open),
             yawning: false)

        if grooming {
            leg(from: CGPoint(x: 12, y: 20), to: CGPoint(x: 16 + lick * 1.2, y: 33 + lick * 1.5),
                color: coat.base.color, paw: coat.paws.color)
        }
    }

    private func paintSleeping() {
        let breath = CGFloat(sin(pose.age * 1.8)) * 0.5 + 0.5
        blob(ellipse(center: CGPoint(x: -3, y: 12 + breath * 0.6), width: 50, height: 22 + breath * 1.6))
        paw(at: CGPoint(x: 25, y: 3), color: coat.paws.color)
        head(center: Self.sleepingHead, radius: 12.5, tilt: -0.18, eyes: .sleepy, yawning: false)
        tail(from: CGPoint(x: -26, y: 8),
             c1: CGPoint(x: -26, y: -2),
             c2: CGPoint(x: 2, y: -3),
             to: CGPoint(x: 14, y: 3))
    }

    // MARK: - Parts

    private func head(center: CGPoint, radius r: CGFloat, tilt: CGFloat, eyes: Eyes, yawning: Bool) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let t = NSAffineTransform()
        t.translateX(by: center.x, yBy: center.y)
        t.rotate(byRadians: tilt)
        t.concat()

        // Ears, behind the head.
        for (index, angle) in [CGFloat.pi * 0.70, CGFloat.pi * 0.30].enumerated() {
            let spread: CGFloat = 0.42
            let tip = polar(angle, r * 1.55)
            let a = polar(angle + spread, r * 0.78)
            let b = polar(angle - spread, r * 0.78)
            var earColor = coat.ears.color
            if case let .patches(first, second) = coat.pattern { earColor = index == 0 ? first.color : second.color }
            let ear = triangle(tip, a, b)
            earColor.setFill()
            ear.fill()
            stroke(ear, width: 1.6)
            let mid = CGPoint(x: (tip.x + a.x + b.x) / 3, y: (tip.y + a.y + b.y) / 3)
            coat.earInner.color.setFill()
            triangle(lerp(mid, tip, 0.6), lerp(mid, a, 0.55), lerp(mid, b, 0.55)).fill()
        }

        let face = NSBezierPath(ovalIn: CGRect(x: -r * 1.12, y: -r * 0.92, width: r * 2.24, height: r * 1.84))
        blob(face, stripeStyle: .forehead) { _ in
            if let muzzle = coat.muzzle {
                muzzle.color.setFill()
                ellipse(center: CGPoint(x: r * 0.1, y: -r * 0.42), width: r * 1.25, height: r * 0.8).fill()
            }
        }

        // Rosy cheeks.
        NSColor(srgbRed: 1, green: 0.45, blue: 0.55, alpha: 0.28).setFill()
        for side in [-1.0, 1.0] as [CGFloat] {
            ellipse(center: CGPoint(x: side * r * 0.66 + r * 0.1, y: -r * 0.28), width: r * 0.42, height: r * 0.22).fill()
        }

        let shift = r * 0.1
        for side in [-1.0, 1.0] as [CGFloat] {
            eye(at: CGPoint(x: side * r * 0.42 + shift, y: r * 0.02), size: r, style: eyes)
        }

        // Nose, mouth, whiskers.
        let noseY = -r * 0.22
        coat.nose.color.setFill()
        let nose = triangle(CGPoint(x: shift - r * 0.11, y: noseY + r * 0.05),
                            CGPoint(x: shift + r * 0.11, y: noseY + r * 0.05),
                            CGPoint(x: shift, y: noseY - r * 0.08))
        nose.lineJoinStyle = .round
        nose.fill()

        faceInk.setStroke()
        if yawning {
            NSColor(srgbRed: 0.85, green: 0.35, blue: 0.42, alpha: 1).setFill()
            let mouth = ellipse(center: CGPoint(x: shift, y: noseY - r * 0.3), width: r * 0.3, height: r * 0.34)
            mouth.fill()
            mouth.lineWidth = 1
            mouth.stroke()
        } else {
            let mouth = NSBezierPath()
            let top = CGPoint(x: shift, y: noseY - r * 0.08)
            mouth.move(to: CGPoint(x: shift - r * 0.2, y: top.y - r * 0.06))
            mouth.curve(to: top, controlPoint1: CGPoint(x: shift - r * 0.18, y: top.y - r * 0.16),
                        controlPoint2: CGPoint(x: shift, y: top.y - r * 0.14))
            mouth.curve(to: CGPoint(x: shift + r * 0.2, y: top.y - r * 0.06),
                        controlPoint1: CGPoint(x: shift, y: top.y - r * 0.14),
                        controlPoint2: CGPoint(x: shift + r * 0.18, y: top.y - r * 0.16))
            mouth.lineWidth = 1
            mouth.lineCapStyle = .round
            mouth.stroke()
        }

        let whiskers = NSBezierPath()
        for side in [-1.0, 1.0] as [CGFloat] {
            let root = CGPoint(x: shift + side * r * 0.62, y: noseY - r * 0.04)
            whiskers.move(to: root)
            whiskers.line(to: CGPoint(x: root.x + side * r * 0.62, y: root.y + r * 0.1))
            whiskers.move(to: CGPoint(x: root.x, y: root.y - r * 0.08))
            whiskers.line(to: CGPoint(x: root.x + side * r * 0.6, y: root.y - r * 0.2))
        }
        faceInk.withAlphaComponent(0.55).setStroke()
        whiskers.lineWidth = 0.7
        whiskers.lineCapStyle = .round
        whiskers.stroke()
    }

    private func eye(at c: CGPoint, size r: CGFloat, style: Eyes) {
        let w = r * 0.36
        let h = r * 0.44
        switch style {
        case .open:
            let iris = ellipse(center: c, width: w, height: h)
            coat.eyes.color.setFill()
            iris.fill()
            let pupilOffset = CGPoint(x: pose.look.dx * w * 0.18, y: pose.look.dy * h * 0.14)
            NSColor(white: 0.08, alpha: 1).setFill()
            ellipse(center: CGPoint(x: c.x + pupilOffset.x, y: c.y + pupilOffset.y),
                    width: w * 0.62, height: h * 0.86).fill()
            NSColor.white.setFill()
            ellipse(center: CGPoint(x: c.x + pupilOffset.x - w * 0.14, y: c.y + pupilOffset.y + h * 0.2),
                    width: w * 0.32, height: w * 0.32).fill()
            ellipse(center: CGPoint(x: c.x + pupilOffset.x + w * 0.16, y: c.y + pupilOffset.y - h * 0.18),
                    width: w * 0.14, height: w * 0.14).fill()
            iris.lineWidth = 0.9
            ink.setStroke()
            iris.stroke()
        case .sleepy, .happy:
            let line = NSBezierPath()
            let dip: CGFloat = style == .happy ? h * 0.45 : -h * 0.35
            line.move(to: CGPoint(x: c.x - w * 0.6, y: c.y - dip * 0.3))
            line.curve(to: CGPoint(x: c.x + w * 0.6, y: c.y - dip * 0.3),
                       controlPoint1: CGPoint(x: c.x - w * 0.3, y: c.y + dip),
                       controlPoint2: CGPoint(x: c.x + w * 0.3, y: c.y + dip))
            line.lineWidth = 1.4
            line.lineCapStyle = .round
            faceInk.setStroke()
            line.stroke()
        }
    }

    private func leg(from hip: CGPoint, to foot: CGPoint, color: NSColor, paw pawColor: NSColor) {
        limb([hip, foot], width: 8, color: color)
        paw(at: foot, color: pawColor)
    }

    private func paw(at p: CGPoint, color: NSColor) {
        let path = ellipse(center: CGPoint(x: p.x + 1.5, y: p.y), width: 11, height: 6.5)
        color.setFill()
        path.fill()
        stroke(path, width: 1.4)
    }

    private func tail(from a: CGPoint, c1: CGPoint, c2: CGPoint, to b: CGPoint) {
        let path = NSBezierPath()
        path.move(to: a)
        path.curve(to: b, controlPoint1: c1, controlPoint2: c2)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = 9.5
        ink.setStroke()
        path.stroke()
        path.lineWidth = 6.5
        coat.tail.color.setStroke()
        path.stroke()
        if case let .stripes(stripe) = coat.pattern {
            path.setLineDash([2.5, 4.5], count: 2, phase: 1)
            path.lineCapStyle = .butt
            stripe.color.setStroke()
            path.stroke()
        }
    }

    private func shadow(width: CGFloat) {
        NSColor(white: 0, alpha: 0.16).setFill()
        ellipse(center: CGPoint(x: -2, y: 1.5), width: width, height: 7).fill()
    }

    // MARK: - Shape helpers

    private enum StripeStyle { case body, forehead }

    /// Fills a shape with the coat, its markings, and any extra detail, then outlines it.
    private func blob(_ path: NSBezierPath, stripeStyle: StripeStyle = .body,
                      detail: ((CGRect) -> Void)? = nil) {
        coat.base.color.setFill()
        path.fill()
        let rect = path.bounds
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        switch coat.pattern {
        case .solid:
            break
        case let .stripes(stripe):
            stripe.color.setStroke()
            let marks = NSBezierPath()
            marks.lineWidth = 3
            marks.lineCapStyle = .round
            switch stripeStyle {
            case .body:
                for f in [0.3, 0.46, 0.62] as [CGFloat] {
                    let x = rect.minX + rect.width * f
                    marks.move(to: CGPoint(x: x + 2, y: rect.maxY + 2))
                    marks.curve(to: CGPoint(x: x - 1, y: rect.midY - 2),
                                controlPoint1: CGPoint(x: x + 3, y: rect.maxY - 4),
                                controlPoint2: CGPoint(x: x - 2, y: rect.midY + 3))
                }
            case .forehead:
                let top = rect.maxY
                for dx in [-3.5, 0, 3.5] as [CGFloat] {
                    let x = rect.midX + dx + 1
                    marks.move(to: CGPoint(x: x, y: top + 1))
                    marks.line(to: CGPoint(x: x + dx * 0.15, y: top - rect.height * 0.22))
                }
            }
            marks.stroke()
        case let .patches(first, second):
            first.color.setFill()
            ellipse(center: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.maxY - rect.height * 0.15),
                    width: rect.width * 0.5, height: rect.height * 0.7).fill()
            second.color.setFill()
            ellipse(center: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.maxY - rect.height * 0.05),
                    width: rect.width * 0.36, height: rect.height * 0.55).fill()
        }
        detail?(rect)
        NSGraphicsContext.restoreGraphicsState()
        stroke(path, width: 1.6)
    }

    private func stroke(_ path: NSBezierPath, width: CGFloat) {
        path.lineWidth = width
        path.lineJoinStyle = .round
        ink.setStroke()
        path.stroke()
    }

    /// A round-capped thick line with an outline.
    private func limb(_ points: [CGPoint], width: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: points[0])
        for p in points.dropFirst() { path.line(to: p) }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = width + 3
        ink.setStroke()
        path.stroke()
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    private func ellipse(center: CGPoint, width: CGFloat, height: CGFloat, rotation: CGFloat = 0) -> NSBezierPath {
        let path = NSBezierPath(ovalIn: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        let t = AffineTransform(translationByX: center.x, byY: center.y)
        var r = AffineTransform(rotationByRadians: rotation)
        r.append(t)
        path.transform(using: r)
        return path
    }

    private func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: a)
        path.line(to: b)
        path.line(to: c)
        path.close()
        path.lineJoinStyle = .round
        return path
    }

    private func polar(_ angle: CGFloat, _ length: CGFloat) -> CGPoint {
        CGPoint(x: cos(angle) * length, y: sin(angle) * length)
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private func ease(_ t: CGFloat) -> CGFloat {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
