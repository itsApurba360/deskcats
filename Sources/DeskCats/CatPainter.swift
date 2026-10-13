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
        /// Pendulum angle while dangling from the cursor.
        var swing: CGFloat = 0
    }

    enum Eyes { case open, half, sleepy, happy }

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
        let p = pose.progress
        switch pose.activity {
        case .held, .falling:
            paintHeld()
            return
        case .sleep, .loaf:
            shadow(width: 58)
        default:
            shadow(width: 52)
        }

        switch pose.activity {
        case .walk:
            paintStanding(Stance(walking: true, legPhase: pose.legPhase))
        case .run:
            paintStanding(Stance(walking: true, running: true, legPhase: pose.legPhase))
        case .idle:
            paintStanding(Stance())
        case .stretch:
            let bow = stretchAmount
            paintStanding(Stance(bow: bow, eyes: bow > 0.3 ? .happy : nil,
                                 yawning: bow > 0.6 && (0.38...0.66).contains(p)))
        case .chaseTail:
            paintStanding(Stance(walking: true, legPhase: CGFloat(pose.age * 14),
                                 lift: abs(CGFloat(sin(pose.age * 9))) * 2.5, tailCurl: 1))
        case .hop:
            let arc = sin(p * .pi)
            paintStanding(Stance(tuck: arc, lift: arc * 16))
        case .pounce:
            paintStanding(pounceStance(p))
        case .sit: paintSitting(.plain)
        case .groom: paintSitting(.groom)
        case .bat: paintSitting(.bat)
        case .slowBlink: paintSitting(.slowBlink)
        case .yawn: paintSitting(.yawn)
        case .scratch: paintSitting(.scratch)
        case .purr: paintSitting(.purr)
        case .sleep: paintLying(sleeping: true)
        case .loaf: paintLying(sleeping: false)
        case .held, .falling: break
        }
    }

    /// Where the head sits in a pose, so the view can float "z"s and hearts above it.
    static func headPoint(for activity: Cat.Activity) -> CGPoint {
        switch activity {
        case .sleep: CGPoint(x: 17, y: 15)
        case .loaf: CGPoint(x: 14, y: 27)
        case .held, .falling: CGPoint(x: 0, y: 49)
        case .sit, .groom, .bat, .slowBlink, .yawn, .scratch, .purr: CGPoint(x: 6, y: 42)
        default: CGPoint(x: 22, y: 34)
        }
    }

    private var stretchAmount: CGFloat {
        let p = pose.progress
        if p < 0.3 { return ease(p / 0.3) }
        if p > 0.72 { return ease((1 - p) / 0.28) }
        return 1
    }

    private var tailSway: CGFloat { CGFloat(sin(pose.age * 1.6)) * 4 }

    // MARK: Standing

    /// Knobs for every four-legged pose.
    private struct Stance {
        var walking = false
        /// A dash: longer strides, a bigger bounce, and the tail streaming out behind.
        var running = false
        var legPhase: CGFloat = 0
        /// Stretch: front end down, rear up.
        var bow: CGFloat = 0
        /// Pounce wind-up: whole body low to the ground.
        var crouch: CGFloat = 0
        /// Mid-leap: front legs reach forward, back legs push back.
        var leap: CGFloat = 0
        /// Hop: feet pulled up under the body.
        var tuck: CGFloat = 0
        /// Height above the ground.
        var lift: CGFloat = 0
        /// Chasing its tail: the tail curls forward toward the head.
        var tailCurl: CGFloat = 0
        /// Sideways shuffle of the hips before a pounce.
        var wiggle: CGFloat = 0
        var eyes: Eyes?
        var yawning = false
    }

    private func pounceStance(_ p: CGFloat) -> Stance {
        if p < 0.55 {
            let wiggle = p > 0.2 ? CGFloat(sin(pose.age * 22)) * 1.6 : 0
            return Stance(crouch: ease(p / 0.15), wiggle: wiggle)
        }
        if p < 0.85 {
            let t = (p - 0.55) / 0.3
            let arc = sin(t * .pi)
            return Stance(leap: arc, lift: arc * 22)
        }
        return Stance(crouch: 0.5 * (1 - (p - 0.85) / 0.15))
    }

    private func paintStanding(_ s: Stance) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if s.lift != 0 {
            let t = NSAffineTransform()
            t.translateX(by: 0, yBy: s.lift)
            t.concat()
        }

        let phase = s.legPhase
        let bob = s.running ? abs(sin(phase)) * 3.2
            : s.walking ? abs(sin(phase)) * 1.4 : CGFloat(sin(pose.age * 2.2)) * 0.4
        let hipY = 20 + bob + s.bow * 4 - s.crouch * 7
        let shoulderY = 20 + bob - s.bow * 9 - s.crouch * 6
        let hip = CGPoint(x: -13 + s.wiggle, y: hipY)
        let shoulder = CGPoint(x: 13, y: shoulderY)
        let reach = s.bow * 13

        func foot(_ x: CGFloat, _ phase: CGFloat, front: Bool) -> CGPoint {
            var p = CGPoint(x: x, y: 3 + s.tuck * 8)
            if s.walking {
                p.x += sin(phase) * (s.running ? 12 : 7)
                p.y += max(0, cos(phase)) * (s.running ? 6 : 3.5)
            }
            p.x += s.leap * (front ? 11 : -9)
            p.y += s.leap * (front ? 6 : 4)
            return p
        }

        // Tail first: it sits behind everything.
        let tailBase = CGPoint(x: hip.x - 8, y: hipY + 3)
        let lift = s.running ? -14 : s.walking ? 0 : s.bow * 6
        let twitch = s.crouch * CGFloat(sin(pose.age * 12)) * 3
        let curl = s.tailCurl
        tail(from: tailBase,
             c1: CGPoint(x: tailBase.x - 10 + curl * 2, y: tailBase.y + 4 + curl * 12),
             c2: CGPoint(x: tailBase.x - 15 + tailSway * 0.3 + curl * 22, y: tailBase.y + 18 + lift + curl * 10 - s.crouch * 10),
             to: CGPoint(x: tailBase.x - 8 + tailSway + twitch + curl * 40,
                         y: tailBase.y + 28 + lift - curl * 6 - s.crouch * 22))

        // Far legs, shaded darker.
        let far = coat.base.darker(0.1)
        let farPaw = coat.paws.darker(0.1)
        leg(from: CGPoint(x: shoulder.x + 3, y: shoulderY - 4),
            to: foot(shoulder.x + 3 + reach, phase + .pi, front: true), color: far, paw: farPaw)
        leg(from: CGPoint(x: hip.x + 3, y: hipY - 4), to: foot(hip.x + 3, phase, front: false),
            color: far, paw: farPaw)

        // Body: an ellipse tilted from hip to shoulder.
        let tilt = atan2(shoulderY - hipY, shoulder.x - hip.x)
        let center = CGPoint(x: (hip.x + shoulder.x) / 2, y: (hipY + shoulderY) / 2 + 2)
        let body = ellipse(center: center, width: 46 + s.leap * 6, height: 24 - s.leap * 2, rotation: tilt)
        blob(body) { rect in
            if let chest = coat.chest {
                chest.color.setFill()
                ellipse(center: CGPoint(x: rect.maxX - 12, y: rect.minY + 6), width: 22, height: 16).fill()
            }
        }

        // Near legs.
        leg(from: CGPoint(x: shoulder.x, y: shoulderY - 4), to: foot(shoulder.x + reach, phase, front: true),
            color: coat.base.color, paw: coat.paws.color)
        leg(from: CGPoint(x: hip.x, y: hipY - 4), to: foot(hip.x, phase + .pi, front: false),
            color: coat.base.color, paw: coat.paws.color)

        head(center: CGPoint(x: 22 + s.bow * 6 + s.leap * 4, y: 34 + bob - s.bow * 13 - s.crouch * 7),
             radius: 13, tilt: -s.bow * 0.12,
             eyes: s.eyes ?? (pose.blinking ? .sleepy : .open),
             yawning: s.yawning)
    }

    // MARK: Sitting

    private enum SitStyle { case plain, groom, bat, slowBlink, yawn, scratch, purr }

    private func paintSitting(_ style: SitStyle) {
        let p = pose.progress
        let breath = CGFloat(sin(pose.age * 2)) * 0.6
        let lick = CGFloat(sin(pose.age * 9))

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if style == .purr {
            // A tiny contented rumble.
            let t = NSAffineTransform()
            t.translateX(by: CGFloat(sin(pose.age * 40)) * 0.35, yBy: 0)
            t.concat()
        }

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
        if style == .scratch {
            // Hind leg up behind the ear, going like the clappers.
            let jitter = CGFloat(sin(pose.age * 26)) * 2
            leg(from: CGPoint(x: -12, y: 12), to: CGPoint(x: -9 + jitter, y: 39 + jitter),
                color: coat.base.color, paw: coat.paws.color)
        } else {
            paw(at: CGPoint(x: -4, y: 3), color: coat.paws.color)
        }

        // Front legs; grooming and batting lift the near one.
        leg(from: CGPoint(x: 8, y: 18), to: CGPoint(x: 8, y: 3),
            color: coat.base.darker(0.1), paw: coat.paws.darker(0.1))
        let pawRaised = style == .groom || style == .bat
        if !pawRaised {
            leg(from: CGPoint(x: 13, y: 18), to: CGPoint(x: 13, y: 3),
                color: coat.base.color, paw: coat.paws.color)
        }

        // Tail wrapped around the front paws.
        let sway = tailSway * 0.4
        tail(from: CGPoint(x: -18, y: 6),
             c1: CGPoint(x: -18, y: -1),
             c2: CGPoint(x: 8, y: -2),
             to: CGPoint(x: 21, y: 4 + sway))

        var eyes: Eyes = pose.blinking ? .sleepy : .open
        var tilt: CGFloat = 0
        var yawning = false
        switch style {
        case .plain: break
        case .groom: eyes = .happy; tilt = -0.16
        case .bat: tilt = 0.1
        case .slowBlink: eyes = (0.3...0.62).contains(p) ? .sleepy : .half
        case .yawn:
            let wide = (0.15...0.85).contains(p)
            eyes = wide ? .happy : .half
            yawning = wide
            tilt = 0.2 * sin(p * .pi)
        case .scratch: eyes = .happy; tilt = 0.24
        case .purr: eyes = .happy; tilt = CGFloat(sin(pose.age * 1.5)) * 0.08
        }
        head(center: CGPoint(x: 6, y: 42 + breath * 0.4), radius: 13.5, tilt: tilt, eyes: eyes, yawning: yawning)

        switch style {
        case .groom:
            leg(from: CGPoint(x: 12, y: 20), to: CGPoint(x: 16 + lick * 1.2, y: 33 + lick * 1.5),
                color: coat.base.color, paw: coat.paws.color)
        case .bat:
            let swat = max(0, CGFloat(sin(pose.age * 7)))
            leg(from: CGPoint(x: 12, y: 20), to: CGPoint(x: 17 + swat * 10, y: 24 + swat * 14),
                color: coat.base.color, paw: coat.paws.color)
            butterfly(at: CGPoint(x: 34 + CGFloat(sin(pose.age * 1.7)) * 4,
                                  y: 44 + CGFloat(sin(pose.age * 2.3)) * 7))
        default:
            break
        }
    }

    // MARK: Lying down

    private func paintLying(sleeping: Bool) {
        let breath = CGFloat(sin(pose.age * 1.8)) * 0.5 + 0.5
        let head = Self.headPoint(for: sleeping ? .sleep : .loaf)
        if sleeping {
            blob(ellipse(center: CGPoint(x: -3, y: 12 + breath * 0.6), width: 50, height: 22 + breath * 1.6))
            paw(at: CGPoint(x: 25, y: 3), color: coat.paws.color)
            self.head(center: head, radius: 12.5, tilt: -0.18, eyes: .sleepy, yawning: false)
            tail(from: CGPoint(x: -26, y: 8),
                 c1: CGPoint(x: -26, y: -2),
                 c2: CGPoint(x: 2, y: -3),
                 to: CGPoint(x: 14, y: 3))
        } else {
            // A loaf: paws tucked out of sight, tail wrapped along the side.
            blob(ellipse(center: CGPoint(x: -2, y: 13 + breath * 0.4), width: 46, height: 26 + breath))
            tail(from: CGPoint(x: -24, y: 8),
                 c1: CGPoint(x: -24, y: 0),
                 c2: CGPoint(x: -2, y: -1),
                 to: CGPoint(x: 12, y: 4 + tailSway * 0.3))
            self.head(center: head, radius: 13, tilt: 0, eyes: pose.blinking ? .sleepy : .half, yawning: false)
        }
    }

    // MARK: Held

    /// Dangling from the scruff, legs hanging, swinging with the cursor.
    private func paintHeld() {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let t = NSAffineTransform()
        t.translateX(by: 0, yBy: Cat.scruffHeight)
        t.rotate(byRadians: pose.swing + CGFloat(sin(pose.age * 3)) * 0.05)
        t.translateX(by: 0, yBy: -Cat.scruffHeight)
        t.concat()

        let dangle = CGFloat(sin(pose.age * 4)) * 1.5
        tail(from: CGPoint(x: 0, y: 16),
             c1: CGPoint(x: 3, y: 6),
             c2: CGPoint(x: -5, y: 2),
             to: CGPoint(x: -2 + CGFloat(sin(pose.age * 3)) * 5, y: -4))
        leg(from: CGPoint(x: -6, y: 20), to: CGPoint(x: -8 + dangle, y: 3),
            color: coat.base.darker(0.1), paw: coat.paws.darker(0.1))
        leg(from: CGPoint(x: 6, y: 20), to: CGPoint(x: 7 - dangle, y: 3),
            color: coat.base.darker(0.1), paw: coat.paws.darker(0.1))
        blob(ellipse(center: CGPoint(x: 0, y: 30), width: 26, height: 33)) { rect in
            if let chest = coat.chest {
                chest.color.setFill()
                ellipse(center: CGPoint(x: rect.midX, y: rect.midY + 2), width: 14, height: 24).fill()
            }
        }
        leg(from: CGPoint(x: -9, y: 38), to: CGPoint(x: -11 - dangle * 0.6, y: 27),
            color: coat.base.color, paw: coat.paws.color)
        leg(from: CGPoint(x: 9, y: 38), to: CGPoint(x: 11 + dangle * 0.6, y: 27),
            color: coat.base.color, paw: coat.paws.color)
        head(center: Self.headPoint(for: .held), radius: 13, tilt: 0,
             eyes: pose.blinking ? .sleepy : .open, yawning: false)
    }

    // MARK: - Parts

    /// A little fluttering butterfly for the cat to bat at.
    private func butterfly(at c: CGPoint) {
        let flap = 0.35 + 0.65 * abs(CGFloat(sin(pose.age * 16)))
        let wing = NSColor(srgbRed: 0.98, green: 0.62, blue: 0.78, alpha: 1)
        let edge = NSColor(srgbRed: 0.62, green: 0.25, blue: 0.42, alpha: 1)
        for side in [-1.0, 1.0] as [CGFloat] {
            let upper = ellipse(center: CGPoint(x: c.x + side * 3.4 * flap, y: c.y + 2), width: 6.5 * flap, height: 7)
            let lower = ellipse(center: CGPoint(x: c.x + side * 2.6 * flap, y: c.y - 2.6), width: 4.8 * flap, height: 5)
            for path in [upper, lower] {
                wing.setFill()
                path.fill()
                path.lineWidth = 0.8
                edge.setStroke()
                path.stroke()
            }
        }
        edge.setFill()
        ellipse(center: c, width: 1.8, height: 8).fill()
    }

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
        case .open, .half:
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
            if style == .half {
                // A heavy, contented eyelid over the top half.
                let lidY = c.y + h * 0.04
                NSGraphicsContext.saveGraphicsState()
                iris.addClip()
                coat.base.color.setFill()
                CGRect(x: c.x - w, y: lidY, width: w * 2, height: h).fill()
                NSGraphicsContext.restoreGraphicsState()
                let lid = NSBezierPath()
                lid.move(to: CGPoint(x: c.x - w * 0.62, y: lidY))
                lid.line(to: CGPoint(x: c.x + w * 0.62, y: lidY))
                lid.lineWidth = 1.4
                lid.lineCapStyle = .round
                faceInk.setStroke()
                lid.stroke()
            }
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
