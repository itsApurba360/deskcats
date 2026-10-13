import AppKit
import Metal
import SceneKit

/// A transparent SceneKit view that draws one cat as a rounded 3D figure.
///
/// It sits inside a `CatView`, which still handles the mouse, so dragging,
/// petting, and click-through work exactly as they do for flat cats. The scene
/// uses an orthographic camera with one scene unit per point, and the rig is
/// built in the same "cat space" as `CatPainter`: the origin is the ground
/// point, +x is the way the cat faces, +y is up.
@MainActor
final class Cat3DView: SCNView {
    /// Whether this Mac can draw the 3D cats at all.
    static let isSupported = MTLCreateSystemDefaultDevice() != nil

    /// How far the camera looks down on the cats, in radians.
    private static let cameraPitch: CGFloat = 0.32

    private let rig: CatRig
    private let cameraNode = SCNNode()

    init(coat: Coat) {
        rig = CatRig(coat: coat)
        super.init(frame: .zero, options: [
            SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue,
        ])
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        backgroundColor = .clear
        allowsCameraControl = false
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 30
        isPlaying = false
        rendersContinuously = false

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.zNear = 1
        camera.zFar = 4000
        cameraNode.camera = camera
        cameraNode.eulerAngles.x = -Self.cameraPitch
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 620
        ambient.light?.color = NSColor(srgbRed: 1, green: 0.97, blue: 0.94, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 560
        sun.light?.castsShadow = false
        sun.eulerAngles = SCNVector3(-0.75, -0.5, 0)
        scene.rootNode.addChildNode(sun)

        scene.rootNode.addChildNode(rig.root)
        self.scene = scene
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // The containing CatView takes every click.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Points the camera so the cat's ground point lands on `anchor` in this view.
    func frame(anchor: CGPoint) {
        guard let camera = cameraNode.camera else { return }
        let w = bounds.width, h = bounds.height
        camera.orthographicScale = Double(h / 2)
        let pitch = Self.cameraPitch
        // Camera right, up, and backward axes after pitching down.
        let up = SCNVector3(0, cos(pitch), -sin(pitch))
        let back = SCNVector3(0, sin(pitch), cos(pitch))
        let dx = anchor.x - w / 2, dy = anchor.y - h / 2
        cameraNode.position = SCNVector3(-dx, -dy * up.y + 1500 * back.y, -dy * up.z + 1500 * back.z)
    }

    func update(from cat: Cat) {
        rig.apply(cat)
    }
}

/// The nodes that make up one 3D cat, and how they move for each activity.
@MainActor
private final class CatRig {
    let root = SCNNode()
    private let coat: Coat
    private let shadow: SCNNode
    /// Rotates the whole cat about the scruff while it dangles.
    private let swingNode = SCNNode()
    private let facingNode = SCNNode()
    private let body = SCNNode()
    private let head = SCNNode()
    private let mouth: SCNNode
    private var openEyes: [SCNNode] = []
    private var closedEyes: [SCNNode] = []
    /// Front near, front far, back near, back far.
    private var legs: [Leg] = []
    private var tail: [SCNNode] = []
    private var yaw: CGFloat

    private struct Leg {
        let node: SCNNode
        let bone: SCNNode
        let paw: SCNNode
    }

    // Rest geometry in cat space.
    private static let bodyCenter = CGPoint(x: -2, y: 19)
    private static let shoulders: [SCNVector3] = [
        SCNVector3(11, -6, 6.5), SCNVector3(11, -6, -6.5), SCNVector3(-11, -6, 6.5), SCNVector3(-11, -6, -6.5),
    ]
    private static let neck = CGPoint(x: 14, y: 9)
    private static let headOffset = CGPoint(x: 5, y: 6)
    private static let tailSegments = 6
    private static let tailSegmentLength: CGFloat = 4.6

    init(coat: Coat) {
        self.coat = coat
        yaw = Self.facingYaw(true)
        shadow = Self.shadowNode()
        mouth = Self.sphere(radius: 2.6, color: NSColor(srgbRed: 0.35, green: 0.12, blue: 0.16, alpha: 1))
        root.addChildNode(shadow)
        swingNode.position = SCNVector3(0, Cat.scruffHeight, 0)
        root.addChildNode(swingNode)
        let unswing = SCNNode()
        unswing.position = SCNVector3(0, -Cat.scruffHeight, 0)
        swingNode.addChildNode(unswing)
        unswing.addChildNode(facingNode)
        facingNode.addChildNode(body)
        facingNode.addChildNode(head)
        buildBody()
        buildHead()
        buildLegs()
        buildTail()
    }

    // MARK: - Building

    private func buildBody() {
        let shape = SCNNode(geometry: SCNSphere(radius: 1))
        shape.geometry?.materials = [Self.material(Self.bodyTexture(for: coat))]
        shape.scale = SCNVector3(12.5, 17, 12.5)
        // Lay the sphere's poles along the body so stripes run across the back.
        shape.eulerAngles.z = .pi / 2
        body.addChildNode(shape)
        if let chest = coat.chest {
            let patch = Self.sphere(radius: 1, color: chest.color)
            patch.scale = SCNVector3(6, 9.5, 9)
            patch.position = SCNVector3(11, -2.5, 0)
            body.addChildNode(patch)
        }
    }

    private func buildHead() {
        let skull = Self.sphere(radius: 13.5, color: coat.base.color)
        skull.scale = SCNVector3(1, 0.93, 1.04)
        head.addChildNode(skull)

        let cheek = coat.muzzle ?? coat.base
        for side: CGFloat in [-1, 1] {
            let puff = Self.sphere(radius: 4.4, color: cheek.color)
            puff.position = SCNVector3(10.6, -4.4, 2.8 * side)
            head.addChildNode(puff)

            let ear = SCNNode()
            ear.position = SCNVector3(-1.5, 9.5, 7.2 * side)
            ear.eulerAngles = SCNVector3(0.42 * side, 0, -0.12)
            let outer = SCNNode(geometry: SCNCone(topRadius: 0.9, bottomRadius: 5.6, height: 10))
            outer.geometry?.materials = [Self.material(coat.ears.color)]
            outer.position = SCNVector3(0, 4, 0)
            let inner = SCNNode(geometry: SCNCone(topRadius: 0.5, bottomRadius: 3.6, height: 7))
            inner.geometry?.materials = [Self.material(coat.earInner.color)]
            inner.position = SCNVector3(2.6, 3.2, 0)
            ear.addChildNode(outer)
            ear.addChildNode(inner)
            head.addChildNode(ear)

            // The eye looks out along its normal from just under the skin.
            let n = Self.normalized(SCNVector3(0.84, 0.16, 0.5 * side))
            let open = SCNNode()
            let iris = Self.sphere(radius: 3.7, color: coat.eyes.color)
            iris.position = n * 11.6
            let pupil = Self.sphere(radius: 2.6, color: NSColor(white: 0.05, alpha: 1))
            pupil.position = n * 13.1
            let shine = Self.sphere(radius: 0.9, color: .white, lit: false)
            shine.position = n * 15.4 + SCNVector3(0, 1.2, 0.4)
            [iris, pupil, shine].forEach(open.addChildNode)
            open.pivot = SCNMatrix4MakeTranslation(n.x * 13, n.y * 13, n.z * 13)
            open.position = n * 13
            head.addChildNode(open)
            openEyes.append(open)

            // A closed eye is a short dark line lying across the face.
            let closed = SCNNode()
            closed.position = n * 13.4
            closed.eulerAngles.y = -0.54 * side
            let lid = SCNNode(geometry: SCNCapsule(capRadius: 0.75, height: 6))
            lid.geometry?.materials = [Self.material(faceInk)]
            lid.eulerAngles.x = .pi / 2
            closed.addChildNode(lid)
            closed.isHidden = true
            head.addChildNode(closed)
            closedEyes.append(closed)

            for (i, angle) in [CGFloat(0.12), -0.12].enumerated() {
                let whisker = SCNNode(geometry: SCNCylinder(radius: 0.22, height: 10))
                whisker.geometry?.materials = [Self.material(NSColor(white: 0.97, alpha: 0.85), lit: false)]
                whisker.position = SCNVector3(12, -4.5 - CGFloat(i) * 1.6, 7.5 * side)
                whisker.eulerAngles = SCNVector3(.pi / 2 * side, 0, angle * side)
                head.addChildNode(whisker)
            }
        }

        let nose = Self.sphere(radius: 1.7, color: coat.nose.color)
        nose.scale = SCNVector3(0.8, 0.7, 1.2)
        nose.position = SCNVector3(14.4, -1.6, 0)
        head.addChildNode(nose)
        mouth.position = SCNVector3(12.4, -7.2, 0)
        mouth.isHidden = true
        head.addChildNode(mouth)

        if case .stripes(let stripe) = coat.pattern {
            for z: CGFloat in [-3.4, 0, 3.4] {
                let mark = Self.sphere(radius: 1, color: stripe.color)
                mark.scale = SCNVector3(0.9, 3.2, 0.9)
                mark.position = SCNVector3(9.4, 7.6, z)
                mark.eulerAngles.z = -0.55
                head.addChildNode(mark)
            }
        }
    }

    private func buildLegs() {
        for shoulder in Self.shoulders {
            let node = SCNNode()
            let bone = SCNNode(geometry: SCNCylinder(radius: 3.7, height: 1))
            bone.geometry?.materials = [Self.material(coat.base.color)]
            let paw = Self.sphere(radius: 4.2, color: coat.paws.color)
            paw.scale = SCNVector3(1.2, 0.72, 1.02)
            node.addChildNode(bone)
            node.addChildNode(paw)
            node.position = shoulder
            facingNode.addChildNode(node)
            legs.append(Leg(node: node, bone: bone, paw: paw))
        }
    }

    private func buildTail() {
        var parent = body
        let stripe: RGB? = if case .stripes(let s) = coat.pattern { s } else { nil }
        for i in 0..<Self.tailSegments {
            let joint = SCNNode()
            joint.position = i == 0 ? SCNVector3(-15, 3, 0) : SCNVector3(0, Self.tailSegmentLength, 0)
            let radius = 3.3 - CGFloat(i) * 0.18
            let color = stripe.map { i % 2 == 1 ? $0 : coat.tail } ?? coat.tail
            let piece = SCNNode(geometry: SCNCapsule(capRadius: radius, height: Self.tailSegmentLength + 2 * radius))
            piece.geometry?.materials = [Self.material(color.color)]
            piece.position = SCNVector3(0, Self.tailSegmentLength / 2, 0)
            joint.addChildNode(piece)
            parent.addChildNode(joint)
            tail.append(joint)
            parent = joint
        }
    }

    // MARK: - Posing

    /// What one frame of animation sets on the rig, in cat space.
    private struct Pose {
        var lift: CGFloat = 0
        /// Nose-up rotation of the body about its center.
        var pitch: CGFloat = 0
        /// Moves the body center down (crouching, lying) or up.
        var bodyDrop: CGFloat = 0
        var squash: CGFloat = 1
        /// Hips wiggling before a pounce.
        var hipSway: CGFloat = 0
        /// Head relative to its rest spot on the neck.
        var headShift = CGPoint.zero
        var nod: CGFloat = 0
        var turn: CGFloat = 0
        var tilt: CGFloat = 0
        /// Per leg: planted foot offset from the shoulder, or a fixed angle and length.
        var legs: [LegPose] = Array(repeating: .planted(0), count: 4)
        var eyes: Eyes = .open
        var yawn: CGFloat = 0
        /// Tail base angle (from pointing straight up, positive leans back), bend per joint, and sway.
        var tailBase: CGFloat = 0.95
        var tailBend: CGFloat = -0.16
        var tailSway: CGFloat = 0
        /// Lying down: the tail curls around the body along the ground.
        var tailWrap = false
    }

    private enum LegPose {
        case planted(CGFloat)
        case free(angle: CGFloat, length: CGFloat)
        case tucked
    }

    private enum Eyes { case open, half, closed }

    func apply(_ cat: Cat) {
        let s = CatView.baseScale * cat.scale
        root.scale = SCNVector3(s, s, s)

        let held = cat.activity == .held || cat.activity == .falling
        let goal = held ? (cat.facingRight ? -1.25 : -1.9) : Self.facingYaw(cat.facingRight)
        yaw += (goal - yaw) * 0.22
        facingNode.eulerAngles.y = yaw
        swingNode.eulerAngles.z = held ? cat.swing : 0
        shadow.isHidden = held

        var pose = pose(for: cat)
        if cat.blinking && pose.eyes == .open { pose.eyes = .closed }
        if !held && pose.eyes != .closed { lookAt(cat, &pose) }
        place(pose, held: held)
    }

    /// Facing right turns the face a little toward the viewer, and so does facing left.
    private static func facingYaw(_ right: Bool) -> CGFloat { right ? -0.5 : -.pi + 0.5 }

    private func lookAt(_ cat: Cat, _ pose: inout Pose) {
        let forward = cat.facingRight ? cat.look.dx : -cat.look.dx
        pose.turn += (forward - 0.35) * 0.7
        pose.nod += cat.look.dy * 0.35
    }

    private func pose(for cat: Cat) -> Pose {
        let p = cat.activityProgress
        let age = cat.age
        var pose = Pose()
        pose.tailSway = CGFloat(sin(age * 1.6)) * 0.22
        switch cat.activity {
        case .walk:
            walk(&pose, phase: cat.legPhase, stride: 0.42)
        case .idle:
            pose.bodyDrop = CGFloat(sin(age * 2)) * 0.3
        case .chaseTail:
            walk(&pose, phase: CGFloat(age * 14), stride: 0.5)
            pose.lift = abs(CGFloat(sin(age * 9))) * 2.5
            pose.tailBase = 1.6
            pose.tailSway = 0.6
            pose.turn = -0.6
        case .stretch:
            let bow = ease(p < 0.3 ? p / 0.3 : p > 0.72 ? (1 - p) / 0.28 : 1)
            pose.pitch = -0.34 * bow
            pose.legs = [.planted(9 * bow), .planted(9 * bow), .planted(-3 * bow), .planted(-3 * bow)]
            pose.headShift = CGPoint(x: 3 * bow, y: -6 * bow)
            pose.nod = 0.3 * bow
            pose.tailBase = 0.95 - 0.5 * bow
            if bow > 0.3 { pose.eyes = .closed }
            if bow > 0.6 && (0.38...0.66).contains(p) { pose.yawn = 1 }
        case .hop:
            let arc = sin(p * .pi)
            pose.lift = arc * 16
            let tuck = 1 - 0.55 * arc
            pose.legs = Self.shoulders.map { .free(angle: 0, length: (19 + $0.y) * tuck) }
        case .pounce:
            if p < 0.55 {
                let crouch = ease(min(1, p / 0.15))
                pose.bodyDrop = -7 * crouch
                pose.hipSway = p > 0.2 ? CGFloat(sin(age * 22)) * 0.12 : 0
                pose.headShift = CGPoint(x: 0, y: -4 * crouch)
                pose.legs = [.planted(4 * crouch), .planted(4 * crouch), .planted(-2), .planted(-2)]
                pose.tailBase = 1.5
            } else if p < 0.85 {
                let arc = sin((p - 0.55) / 0.3 * .pi)
                pose.lift = arc * 22
                pose.pitch = 0.15 * arc
                pose.legs = [
                    .free(angle: 1.1 * arc, length: 13), .free(angle: 1.1 * arc, length: 13),
                    .free(angle: -1 * arc, length: 13), .free(angle: -1 * arc, length: 13),
                ]
                pose.tailBase = 1.7
            } else {
                pose.bodyDrop = -3.5 * (1 - (p - 0.85) / 0.15)
            }
        case .sit, .groom, .bat, .slowBlink, .yawn, .scratch, .purr:
            sit(&pose, cat: cat, p: p)
        case .sleep, .loaf:
            lie(&pose, sleeping: cat.activity == .sleep, age: age)
        case .held, .falling:
            pose.pitch = 1.45
            pose.bodyDrop = 15
            pose.headShift = CGPoint(x: 5, y: 2)
            pose.turn = -0.5
            let dangle = CGFloat(sin(age * 3)) * 0.12
            pose.legs = [
                .free(angle: -0.15 + dangle, length: 12), .free(angle: -0.25 - dangle, length: 12),
                .free(angle: 0.1 - dangle, length: 13), .free(angle: 0.2 + dangle, length: 13),
            ]
            // Straight down, against the body's pitch.
            pose.tailBase = 1.7
            pose.tailBend = 0.05
            pose.tailSway = CGFloat(sin(age * 2.4)) * 0.3
        }
        return pose
    }

    private func walk(_ pose: inout Pose, phase: CGFloat, stride: CGFloat) {
        // Diagonal pairs move together, like a real trot.
        let a = sin(phase), b = sin(phase + .pi)
        pose.legs = [.planted(stride * 12 * a), .planted(stride * 12 * b),
                     .planted(stride * 12 * b), .planted(stride * 12 * a)]
        pose.bodyDrop = abs(cos(phase)) * 1.2 - 0.6
        pose.headShift.y = abs(cos(phase)) * 0.8
    }

    private func sit(_ pose: inout Pose, cat: Cat, p: CGFloat) {
        let age = cat.age
        pose.pitch = 0.78
        pose.bodyDrop = -4
        pose.legs = [.planted(1), .planted(1),
                     .free(angle: 1.45, length: 10), .free(angle: 1.45, length: 10)]
        pose.tailBase = 1.9
        pose.tailBend = -0.22
        pose.tailSway = CGFloat(sin(age * 1.3)) * 0.15
        pose.headShift = CGPoint(x: -3, y: -1)
        switch cat.activity {
        case .groom:
            pose.eyes = .closed
            pose.nod = -0.45
            pose.turn = -0.5
            let lick = CGFloat(sin(age * 7))
            pose.headShift.y -= 2 + lick * 0.8
            pose.legs[0] = .free(angle: 2.1 + lick * 0.15, length: 13)
        case .bat:
            pose.nod = 0.3
            let swipe = CGFloat(sin(age * 6))
            pose.legs[swipe > 0 ? 0 : 1] = .free(angle: 2.2 + abs(swipe) * 0.6, length: 14)
        case .slowBlink:
            pose.eyes = (0.3...0.62).contains(p) ? .closed : .half
            pose.turn = -0.7
        case .yawn:
            let open = sin(p * .pi)
            pose.yawn = open
            pose.nod = 0.35 * open
            if open > 0.4 { pose.eyes = .closed }
        case .scratch:
            pose.eyes = .closed
            pose.tilt = 0.35
            pose.legs[2] = .free(angle: 2.4 + CGFloat(sin(age * 22)) * 0.25, length: 14)
        case .purr:
            pose.eyes = .closed
            pose.turn = -0.6
            pose.tilt = CGFloat(sin(age * 1.5)) * 0.16
        default:
            break
        }
    }

    private func lie(_ pose: inout Pose, sleeping: Bool, age: TimeInterval) {
        let breath = CGFloat(sin(age * (sleeping ? 1.6 : 2.2)))
        pose.bodyDrop = -8.5
        pose.squash = 0.82 + breath * 0.02
        pose.legs = Array(repeating: .tucked, count: 4)
        pose.tailWrap = true
        pose.tailSway = breath * 0.05
        if sleeping {
            pose.headShift = CGPoint(x: 0, y: -11)
            pose.nod = -0.25
            pose.turn = -0.75
            pose.tilt = 0.25
            pose.eyes = .closed
        } else {
            pose.headShift = CGPoint(x: -2, y: -6)
            pose.eyes = .half
            pose.turn = -0.3
        }
    }

    // MARK: - Applying a pose

    private func place(_ pose: Pose, held: Bool) {
        let center = CGPoint(x: Self.bodyCenter.x, y: Self.bodyCenter.y + pose.bodyDrop + pose.lift)
        body.position = SCNVector3(center.x, center.y, 0)
        body.eulerAngles = SCNVector3(0, pose.hipSway, pose.pitch)
        body.scale = SCNVector3(1, pose.squash, 1)

        func inBody(_ p: CGPoint) -> CGPoint {
            let c = cos(pose.pitch), s = sin(pose.pitch)
            return CGPoint(x: center.x + p.x * c - p.y * s * pose.squash,
                           y: center.y + p.x * s + p.y * c * pose.squash)
        }

        let neck = inBody(Self.neck)
        // Sitting tilts the neck back; keep the head itself upright.
        head.position = SCNVector3(neck.x + Self.headOffset.x + pose.headShift.x,
                                   neck.y + Self.headOffset.y + pose.headShift.y, 0)
        head.eulerAngles = SCNVector3(pose.tilt, pose.turn, pose.nod)

        for (i, leg) in legs.enumerated() {
            let shoulder = Self.shoulders[i]
            let top = inBody(CGPoint(x: shoulder.x, y: shoulder.y))
            leg.node.position = SCNVector3(top.x, top.y, shoulder.z)
            let angle: CGFloat, length: CGFloat
            switch pose.legs[i] {
            case .planted(let reach):
                let height = max(1, top.y)
                angle = atan2(reach, height)
                length = hypot(reach, height)
            case .free(let a, let l):
                angle = a
                length = l
            case .tucked:
                angle = .pi / 2
                length = 6
            }
            leg.node.isHidden = false
            leg.node.eulerAngles.z = angle
            leg.bone.scale = SCNVector3(1, length, 1)
            leg.bone.position = SCNVector3(0, -length / 2, 0)
            leg.paw.position = SCNVector3(0, -length + 1.2, 0)
            // The paw stays flat: undo the leg's swing on it.
            leg.paw.eulerAngles.z = -angle
        }

        let swaying = pose.tailSway
        for (i, joint) in tail.enumerated() {
            if pose.tailWrap {
                // Down behind the body, then along the ground around the near side.
                if i == 0 {
                    joint.position = SCNVector3(-14, -6, 0)
                    joint.eulerAngles = SCNVector3(0, 0, 1.75)
                } else {
                    joint.eulerAngles = SCNVector3(0.5 + swaying, 0, 0)
                }
            } else if i == 0 {
                joint.position = SCNVector3(-15, 3, 0)
                joint.eulerAngles = SCNVector3(swaying, 0, pose.tailBase)
            } else {
                joint.eulerAngles = SCNVector3(swaying * 0.6, 0, pose.tailBend)
            }
        }

        for eye in openEyes {
            eye.isHidden = pose.eyes == .closed
            eye.scale = SCNVector3(1, pose.eyes == .half ? 0.55 : 1, 1)
        }
        for eye in closedEyes { eye.isHidden = pose.eyes != .closed }
        mouth.isHidden = pose.yawn < 0.05
        mouth.scale = SCNVector3(1, max(0.1, pose.yawn * 1.5), 0.9)
    }

    private func ease(_ t: CGFloat) -> CGFloat { t * t * (3 - 2 * t) }

    // MARK: - Materials

    private var faceInk: NSColor {
        let face = coat.muzzle ?? coat.base
        let luminance = 0.299 * face.r + 0.587 * face.g + 0.114 * face.b
        return luminance < 0.4 ? NSColor(white: 0.82, alpha: 1) : coat.outline.color
    }

    private static func material(_ contents: Any, lit: Bool = true) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = contents
        m.lightingModel = lit ? .lambert : .constant
        m.locksAmbientWithDiffuse = true
        return m
    }

    private static func sphere(radius: CGFloat, color: NSColor, lit: Bool = true) -> SCNNode {
        let geometry = SCNSphere(radius: radius)
        geometry.segmentCount = 32
        geometry.materials = [material(color, lit: lit)]
        return SCNNode(geometry: geometry)
    }

    private static func shadowNode() -> SCNNode {
        let disc = SCNNode(geometry: SCNCylinder(radius: 1, height: 0.1))
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(white: 0, alpha: 0.18)
        m.lightingModel = .constant
        m.writesToDepthBuffer = false
        disc.geometry?.materials = [m]
        disc.scale = SCNVector3(25, 1, 13)
        disc.renderingOrder = -1
        return disc
    }

    private static func normalized(_ v: SCNVector3) -> SCNVector3 {
        let length = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
        return SCNVector3(v.x / length, v.y / length, v.z / length)
    }

    /// The body's fur: stripes across the back or calico patches over the base color.
    private static func bodyTexture(for coat: Coat) -> NSImage {
        let size = CGSize(width: 256, height: 128)
        return NSImage(size: size, flipped: false) { rect in
            coat.base.color.setFill()
            rect.fill()
            switch coat.pattern {
            case .solid:
                break
            case .stripes(let stripe):
                // Texture height runs nose to tail; each band wraps around the body.
                stripe.color.setFill()
                for i in 0..<7 {
                    let y = rect.height * (0.2 + CGFloat(i) * 0.085)
                    let path = NSBezierPath()
                    path.move(to: CGPoint(x: 0, y: y))
                    for x in stride(from: 0, through: rect.width, by: 8) {
                        path.line(to: CGPoint(x: x, y: y + sin(x / 20 + CGFloat(i)) * 2.5))
                    }
                    for x in stride(from: rect.width, through: 0, by: -8) {
                        path.line(to: CGPoint(x: x, y: y + 4.5 + sin(x / 17 + CGFloat(i)) * 2))
                    }
                    path.fill()
                }
            case .patches(let a, let b):
                let spots: [(CGRect, RGB)] = [
                    (CGRect(x: 10, y: 20, width: 70, height: 46), a), (CGRect(x: 150, y: 70, width: 64, height: 40), a),
                    (CGRect(x: 92, y: 44, width: 46, height: 52), b), (CGRect(x: 200, y: 14, width: 50, height: 38), b),
                    (CGRect(x: 40, y: 80, width: 40, height: 34), b),
                ]
                for (spot, color) in spots {
                    color.color.setFill()
                    NSBezierPath(ovalIn: spot).fill()
                }
            }
            return true
        }
    }
}

private func * (v: SCNVector3, k: CGFloat) -> SCNVector3 { SCNVector3(v.x * k, v.y * k, v.z * k) }
private func + (a: SCNVector3, b: SCNVector3) -> SCNVector3 { SCNVector3(a.x + b.x, a.y + b.y, a.z + b.z) }
