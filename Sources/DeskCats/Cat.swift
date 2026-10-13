import AppKit

/// The rectangle a cat may roam in, in overlay-view coordinates.
struct RoamArea {
    var minX: CGFloat
    var maxX: CGFloat
    /// The "floor" the cats walk on, just above the Dock.
    var floor: CGFloat
    /// How far above the floor a cat may wander.
    var ceiling: CGFloat

    init(visibleFrame vf: CGRect) {
        minX = vf.minX + 50
        maxX = max(vf.minX + 51, vf.maxX - 50)
        floor = vf.minY + 4
        ceiling = max(floor, min(vf.minY + 80, vf.maxY - 120))
    }

    func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, minX), maxX), y: min(max(p.y, floor), ceiling))
    }
}

/// One cat: where it is, which way it faces, and what it is doing.
@MainActor
final class Cat {
    enum Activity: CaseIterable {
        case walk, idle, sit, sleep, stretch, groom
    }

    let coat: Coat
    /// Per-cat size multiplier so the group isn't uniform.
    let size: CGFloat
    /// Ground point under the cat's middle, in overlay-view coordinates.
    private(set) var position: CGPoint
    private(set) var facingRight: Bool
    private(set) var activity: Activity = .idle
    private(set) var activityTime: TimeInterval = 0
    private(set) var activityDuration: TimeInterval = 1
    /// Advances with distance walked; drives the leg swing.
    private(set) var legPhase: CGFloat = 0
    /// Seconds since the cat appeared; drives breathing, tail sway, and "z"s.
    private(set) var age: TimeInterval
    private(set) var blinking = false
    /// Where the pupils point, in screen space, each axis in -1...1.
    private(set) var look: CGVector = .zero

    private var target: CGPoint
    private var walkSpeed: CGFloat
    private let baseSpeed: CGFloat
    private var nextBlink: TimeInterval

    var activityProgress: CGFloat { CGFloat(min(1, activityTime / activityDuration)) }

    init(coat: Coat, position: CGPoint, activity: Activity = .walk, area: RoamArea) {
        self.coat = coat
        size = .random(in: 0.88...1.1)
        self.position = position
        facingRight = Bool.random()
        age = .random(in: 0...100)
        baseSpeed = .random(in: 30...44)
        walkSpeed = baseSpeed
        target = position
        nextBlink = age + .random(in: 1...4)
        begin(activity, area: area)
    }

    func update(dt: TimeInterval, area: RoamArea, mouse: CGPoint) {
        age += dt
        activityTime += dt
        updateBlink()

        if activity == .walk {
            let dx = target.x - position.x
            let dy = target.y - position.y
            let distance = hypot(dx, dy)
            let step = min(distance, walkSpeed * CGFloat(dt))
            if distance > 0.01 {
                position.x += dx / distance * step
                position.y += dy / distance * step
                legPhase += step * 0.2
            }
            if abs(dx) > 0.5 { facingRight = dx > 0 }
            if distance < 1 || activityTime >= activityDuration {
                begin(next(after: .walk), area: area)
            }
        } else if activityTime >= activityDuration {
            begin(next(after: activity), area: area)
        }

        position = area.clamp(position)
        updateLook(dt: dt, mouse: mouse)
    }

    /// Keeps the cat on screen after the display arrangement changes.
    func reclamp(to area: RoamArea) {
        position = area.clamp(position)
        target = area.clamp(target)
    }

    // MARK: - State machine

    private func begin(_ activity: Activity, area: RoamArea) {
        self.activity = activity
        activityTime = 0
        switch activity {
        case .walk:
            target = pickTarget(area: area)
            walkSpeed = baseSpeed * (Double.random(in: 0...1) < 0.15 ? 1.8 : 1)
            let distance = hypot(target.x - position.x, target.y - position.y)
            activityDuration = Double(distance / walkSpeed) + 2
        case .idle: activityDuration = .random(in: 2...5)
        case .sit: activityDuration = .random(in: 5...12)
        case .sleep: activityDuration = .random(in: 15...40)
        case .stretch: activityDuration = 2.8
        case .groom: activityDuration = .random(in: 3.5...7)
        }
    }

    private func next(after activity: Activity) -> Activity {
        let weights: [(Activity, Double)]
        switch activity {
        case .walk: weights = [(.idle, 4), (.sit, 3), (.walk, 2), (.stretch, 1)]
        case .idle: weights = [(.walk, 5), (.sit, 2.5), (.stretch, 1.5), (.groom, 1)]
        case .sit: weights = [(.groom, 3), (.sleep, 3), (.walk, 2), (.idle, 2)]
        case .sleep: weights = [(.stretch, 7), (.sit, 3)]
        case .stretch: weights = [(.walk, 6), (.idle, 4)]
        case .groom: weights = [(.sit, 4), (.walk, 3), (.sleep, 3)]
        }
        var roll = Double.random(in: 0..<weights.reduce(0) { $0 + $1.1 })
        for (candidate, weight) in weights {
            if roll < weight { return candidate }
            roll -= weight
        }
        return weights[0].0
    }

    private func pickTarget(area: RoamArea) -> CGPoint {
        let reach = CGFloat.random(in: 80...420) * (Bool.random() ? 1 : -1)
        var x = position.x + reach
        if x < area.minX || x > area.maxX { x = position.x - reach }
        let wanderUp = Double.random(in: 0...1) < 0.2
        let y = wanderUp
            ? area.floor + .random(in: 12...max(12, area.ceiling - area.floor))
            : area.floor + .random(in: 0...4)
        return area.clamp(CGPoint(x: x, y: y))
    }

    // MARK: - Eyes

    private func updateBlink() {
        if age >= nextBlink {
            blinking = true
            if age >= nextBlink + 0.14 {
                blinking = false
                nextBlink = age + .random(in: 2.5...6)
            }
        }
    }

    /// Turns the eyes (and, when resting, the whole cat) toward a nearby cursor.
    private func updateLook(dt: TimeInterval, mouse: CGPoint) {
        let head = CGPoint(x: position.x, y: position.y + 38 * size)
        let dx = mouse.x - head.x
        let dy = mouse.y - head.y
        let distance = hypot(dx, dy)
        var goal = CGVector(dx: facingRight ? 0.35 : -0.35, dy: 0)
        if distance < 260, activity != .sleep {
            goal = CGVector(dx: dx / max(distance, 1), dy: dy / max(distance, 1))
            if activity == .idle || activity == .sit, abs(dx) > 16 {
                facingRight = dx > 0
            }
        }
        let k = CGFloat(min(1, dt * 8))
        look = CGVector(dx: look.dx + (goal.dx - look.dx) * k, dy: look.dy + (goal.dy - look.dy) * k)
    }
}
