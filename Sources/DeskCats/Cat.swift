import AppKit

/// The rectangle a cat may roam in, in overlay-view coordinates.
struct RoamArea {
    var minX: CGFloat
    var maxX: CGFloat
    /// The "floor" the cats walk on, just above the Dock.
    var floor: CGFloat
    /// How far above the floor a cat may wander.
    var ceiling: CGFloat
    /// The whole overlay, for cats being carried around.
    var screen: CGRect

    init(visibleFrame vf: CGRect, screen: CGRect, catScale: CGFloat) {
        let margin = 12 + 40 * catScale
        minX = vf.minX + margin
        maxX = max(minX + 1, vf.maxX - margin)
        floor = vf.minY + 4
        ceiling = max(floor, min(vf.minY + 80, vf.maxY - 120))
        self.screen = screen
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
        /// A quick dash, used when a cat travels to another Space.
        case run
        case loaf, chaseTail, bat, slowBlink, yawn, hop, pounce, scratch
        /// Reaction to being clicked.
        case purr
        /// Being carried by the mouse, then dropping back down.
        case held, falling

        /// Activities the random picker chooses between.
        static let roaming: [Activity] = [
            .walk, .idle, .sit, .sleep, .stretch, .groom,
            .loaf, .chaseTail, .bat, .slowBlink, .yawn, .hop, .pounce, .scratch,
        ]
    }

    let coat: Coat
    /// Per-cat size multiplier so the group isn't uniform.
    let size: CGFloat
    /// The size chosen from the menu (Small, Medium, Large).
    var displayScale: CGFloat = 1
    /// Combined size of this cat on screen.
    var scale: CGFloat { size * displayScale }

    /// Ground point under the cat's middle, in overlay-view coordinates.
    /// While held, it hangs below the cursor instead.
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
    /// How far a held or falling cat swings from its scruff, in radians.
    private(set) var swing: CGFloat = 0

    /// Personality: playful cats chase and pounce more, lazy cats nap more.
    private let energy: Double
    private let laziness: Double
    private var target: CGPoint
    private var walkSpeed: CGFloat = 1
    private let baseSpeed: CGFloat
    private var nextBlink: TimeInterval
    /// Start and length of a hop or pounce.
    private var leapStartX: CGFloat = 0
    private var leapLength: CGFloat = 0
    private var nextSpin: TimeInterval = 0
    private var fallSpeed: CGFloat = 0
    /// Where a dropped cat will land; chosen on the first frame of the fall.
    private var fallTarget: CGFloat?
    private var heldVelocity: CGFloat = 0
    private var swingSpeed: CGFloat = 0
    /// A trip off one side of the screen, toward another Space, and back to `home`.
    private struct Trip {
        /// The spot the cat returns to once it is back on screen.
        var home: CGPoint
        /// +1 heading off the right edge, -1 the left.
        var direction: CGFloat
        var leaving = true
        /// A wander to a neighbouring desktop: the cat comes back in the side it left.
        var excursion = false
        /// How long a wandering cat stays away once it is off screen.
        var away: TimeInterval = 0
    }
    private var trip: Trip?
    /// Seconds the cat hesitates before setting off.
    private var tripDelay: TimeInterval = 0
    private var tripRunning = false

    var activityProgress: CGFloat { CGFloat(min(1, activityTime / activityDuration)) }
    var isHeld: Bool { activity == .held }

    /// Height of the scruff above the ground point when dangling, in cat space.
    static let scruffHeight: CGFloat = 60

    init(coat: Coat, position: CGPoint, activity: Activity, area: RoamArea, displayScale: CGFloat) {
        self.coat = coat
        size = .random(in: 0.88...1.1)
        self.displayScale = displayScale
        self.position = position
        facingRight = Bool.random()
        age = .random(in: 0...100)
        baseSpeed = .random(in: 30...44)
        energy = .random(in: 0.5...1.6)
        laziness = .random(in: 0.5...1.6)
        target = position
        nextBlink = age + .random(in: 1...4)
        begin(activity, area: area)
        // Start part-way through so cats added together don't move in step.
        activityTime = .random(in: 0...(activityDuration * 0.5))
    }

    func update(dt: TimeInterval, area: RoamArea, mouse: CGPoint) {
        age += dt
        activityTime += dt
        updateBlink()
        // A hesitating cat carries on with what it was doing until it sets off.
        if trip != nil, tripDelay > 0 {
            tripDelay -= dt
            if tripDelay <= 0 { startTrip(area: area) }
        }

        switch activity {
        case .walk, .run:
            let dx = target.x - position.x
            let dy = target.y - position.y
            let distance = hypot(dx, dy)
            let step = min(distance, walkSpeed * displayScale * CGFloat(dt))
            if distance > 0.01 {
                position.x += dx / distance * step
                position.y += dy / distance * step
                // Running takes longer strides, but at a much quicker leg cycle.
                legPhase += step * (activity == .run ? 0.13 : 0.2) / scale
            }
            if abs(dx) > 0.5 { facingRight = dx > 0 }
            if let current = trip, tripDelay <= 0 {
                // Off screen: a wandering cat waits out its time away, then comes back.
                if current.leaving, current.excursion, distance < 1 {
                    trip?.away -= dt
                    if current.away <= 0 { enter(area: area) }
                } else if !current.leaving, distance < 1 {
                    trip = nil
                    begin(pickNext(), area: area)
                }
            } else if distance < 1 || activityTime >= activityDuration {
                begin(pickNext(), area: area)
            }
        case .hop, .pounce:
            let start: CGFloat = activity == .pounce ? 0.55 : 0
            let end: CGFloat = activity == .pounce ? 0.85 : 1
            let t = min(max((activityProgress - start) / (end - start), 0), 1)
            position.x = leapStartX + leapLength * t
            if activityTime >= activityDuration { carryOn(area: area) }
        case .chaseTail:
            if age >= nextSpin {
                facingRight.toggle()
                nextSpin = age + .random(in: 0.28...0.45)
            }
            if activityTime >= activityDuration { carryOn(area: area) }
        case .held:
            updateSwing(dt: dt, target: max(-0.7, min(0.7, -heldVelocity * 0.0025)))
            heldVelocity *= 0.85
        case .falling:
            fallSpeed += 1800 * CGFloat(dt)
            position.y -= fallSpeed * CGFloat(dt)
            updateSwing(dt: dt, target: 0)
            // Dropped above the roaming band: fall all the way to the floor.
            let landing = fallTarget ?? (position.y > area.ceiling
                ? area.floor + .random(in: 0...4)
                : area.clamp(position).y)
            fallTarget = landing
            if position.y <= landing {
                position.y = landing
                swing = 0
                land(area: area)
            }
        default:
            if activityTime >= activityDuration { carryOn(area: area) }
        }

        if activity != .held && activity != .falling && (trip == nil || tripDelay > 0) {
            position = area.clamp(position)
        }
        updateLook(dt: dt, mouse: mouse)
    }

    /// Keeps the cat on screen after the display arrangement or size changes.
    func reclamp(to area: RoamArea) {
        guard activity != .held && activity != .falling else { return }
        // A travelling cat may be off screen on purpose; only its spot moves.
        if let current = trip {
            trip?.home = area.clamp(current.home)
            if !current.leaving { target = area.clamp(current.home) }
            return
        }
        position = area.clamp(position)
        target = area.clamp(target)
    }

    // MARK: - Travelling between Spaces

    var isTravelling: Bool { trip != nil }
    var isOnExcursion: Bool { trip?.excursion == true }
    /// Off screen after heading for another Space, ready to come in on the next one.
    var hasLeftForSpace: Bool {
        guard let trip, trip.leaving, !trip.excursion else { return false }
        return activity == .walk || activity == .run ? abs(target.x - position.x) < 1 : false
    }

    /// Heads off the screen edge toward the Space the user moved to, after
    /// hesitating for `delay` seconds. It keeps its spot for when it gets there.
    func setOff(direction: CGFloat, delay: TimeInterval, area: RoamArea) {
        guard activity != .held else { return }
        let alreadyGoing = trip != nil && trip?.excursion == false
        let home = trip?.home ?? area.clamp(position)
        trip = Trip(home: home, direction: direction)
        if !alreadyGoing {
            tripDelay = delay
            tripRunning = Bool.random()
        }
        if tripDelay <= 0 { startTrip(area: area) }
    }

    /// Now and then a cat wanders off to a neighbouring desktop for a while.
    func wander(area: RoamArea) {
        guard trip == nil, Activity.roaming.contains(activity) else { return }
        let direction: CGFloat = Bool.random() ? 1 : -1
        trip = Trip(home: area.clamp(position), direction: direction, excursion: true,
                    away: .random(in: 20...90))
        tripDelay = 0
        tripRunning = Double.random(in: 0...1) < 0.25
        startTrip(area: area)
    }

    /// The user came back to this Space mid-trip: the cat turns around and goes home.
    func comeBack(area: RoamArea) {
        guard let current = trip, current.leaving, !current.excursion else { return }
        trip?.leaving = false
        trip?.direction = -current.direction
        tripDelay = 0
        startTrip(area: area)
    }

    /// Steps in from off screen on the Space it was heading for (or back from a
    /// wander), then walks to its spot.
    func enter(area: RoamArea) {
        guard let current = trip, current.leaving else { return }
        // Moving right, it left through the right edge and comes in through the
        // left one; a wanderer comes back through the edge it left by.
        let fromLeft = current.excursion ? current.direction < 0 : current.direction > 0
        let offset = edgeOffset
        position = CGPoint(x: fromLeft ? area.screen.minX - offset : area.screen.maxX + offset, y: position.y)
        trip?.leaving = false
        trip?.home = area.clamp(current.home)
        tripDelay = 0
        startTrip(area: area)
    }

    /// How far past the edge a cat must be to be fully out of sight.
    private var edgeOffset: CGFloat { 60 * CatView.baseScale * scale }

    private func startTrip(area: RoamArea) {
        guard let trip else { return }
        if trip.leaving {
            let x = trip.direction > 0 ? area.screen.maxX + edgeOffset : area.screen.minX - edgeOffset
            target = CGPoint(x: x, y: position.y)
        } else {
            target = trip.home
        }
        activity = tripRunning ? .run : .walk
        activityTime = 0
        // A wander is an unhurried stroll; following the user is brisker.
        walkSpeed = baseSpeed * (trip.excursion ? (tripRunning ? 2.5 : 1) : (tripRunning ? 4 : 2))
        activityDuration = .infinity
    }

    /// After a pause (petting, say), a travelling cat picks up its trip again.
    private func carryOn(area: RoamArea) {
        if trip != nil, tripDelay <= 0 {
            startTrip(area: area)
        } else {
            begin(pickNext(), area: area)
        }
    }

    // MARK: - Mouse

    /// Picks the cat up so it dangles from the cursor at `scruff`.
    func grab(at scruff: CGPoint) {
        trip = nil
        tripDelay = 0
        activity = .held
        activityTime = 0
        activityDuration = 1
        heldVelocity = 0
        swingSpeed = 0
        position = CGPoint(x: scruff.x, y: scruff.y - Self.scruffHeight * CatView.baseScale * scale)
    }

    func carry(to scruff: CGPoint, dt: TimeInterval, area: RoamArea) {
        let x = min(max(scruff.x, area.screen.minX), area.screen.maxX)
        let y = min(max(scruff.y, area.screen.minY), area.screen.maxY)
        if dt > 0 {
            heldVelocity = heldVelocity * 0.5 + (x - position.x) / CGFloat(dt) * 0.5
        }
        position = CGPoint(x: x, y: y - Self.scruffHeight * CatView.baseScale * scale)
    }

    /// Lets go; the cat drops to the floor band and carries on from there.
    func drop() {
        activity = .falling
        activityTime = 0
        activityDuration = 1
        fallSpeed = 0
        fallTarget = nil
    }

    /// A click without a drag: the cat purrs and shows hearts.
    func pet(area: RoamArea) {
        // A travelling cat stops where it is to purr, then carries on.
        tripDelay = 0
        begin(.purr, area: area)
    }

    // MARK: - State machine

    private func begin(_ activity: Activity, area: RoamArea) {
        self.activity = activity
        activityTime = 0
        switch activity {
        case .walk:
            target = pickTarget(area: area)
            walkSpeed = baseSpeed * (Double.random(in: 0...1) < 0.15 * energy ? 1.8 : 1)
            let distance = hypot(target.x - position.x, target.y - position.y)
            activityDuration = Double(distance / (walkSpeed * displayScale)) + 2
        case .run:
            // Only a trip starts a run; it sets the target and speed itself.
            activityDuration = 1
        case .idle: activityDuration = .random(in: 1.5...5)
        case .sit: activityDuration = .random(in: 4...12)
        case .sleep: activityDuration = .random(in: 15...45)
        case .stretch: activityDuration = .random(in: 2.4...3.2)
        case .groom: activityDuration = .random(in: 3...7)
        case .loaf: activityDuration = .random(in: 8...20)
        case .chaseTail:
            activityDuration = .random(in: 2.5...4.5)
            nextSpin = age + 0.3
        case .bat: activityDuration = .random(in: 2.5...5)
        case .slowBlink: activityDuration = .random(in: 2.2...3)
        case .yawn: activityDuration = .random(in: 1.6...2.2)
        case .scratch: activityDuration = .random(in: 2...3.5)
        case .purr: activityDuration = 2.6
        case .hop, .pounce:
            activityDuration = activity == .hop ? .random(in: 0.6...0.8) : .random(in: 1.8...2.6)
            let reach = (activity == .hop ? CGFloat.random(in: 10...28) : .random(in: 50...90)) * scale
            let direction: CGFloat = facingRight ? 1 : -1
            var end = position.x + direction * reach
            if end < area.minX || end > area.maxX {
                facingRight.toggle()
                end = position.x - direction * reach
            }
            leapStartX = position.x
            leapLength = area.clamp(CGPoint(x: end, y: position.y)).x - position.x
        case .held, .falling: activityDuration = 1
        }
    }

    /// Weighted random choice, shaped by personality and what the cat just did.
    private func pickNext() -> Activity {
        let playful: Set<Activity> = [.walk, .chaseTail, .bat, .hop, .pounce]
        let lazy: Set<Activity> = [.sleep, .loaf, .sit, .slowBlink, .yawn]
        let base: [Activity: Double] = [
            .walk: 5, .idle: 2, .sit: 2.5, .sleep: 1.2, .stretch: 0.8, .groom: 1.5,
            .loaf: 1.5, .chaseTail: 0.7, .bat: 0.9, .slowBlink: 1, .yawn: 0.8,
            .hop: 0.8, .pounce: 0.9, .scratch: 0.8,
        ]
        var weights = Activity.roaming.map { candidate -> (Activity, Double) in
            var w = base[candidate] ?? 0
            if playful.contains(candidate) { w *= energy }
            if lazy.contains(candidate) { w *= laziness }
            if candidate == activity { w *= candidate == .walk ? 0.5 : 0.1 }
            if activity == .sleep || activity == .loaf {
                // Waking up: stretch or yawn first, rarely straight back to sleep.
                switch candidate {
                case .stretch: w *= 6
                case .yawn: w *= 3
                case .sleep, .loaf: w *= 0.2
                default: break
                }
            }
            return (candidate, w)
        }
        weights.shuffle()
        var roll = Double.random(in: 0..<weights.reduce(0) { $0 + $1.1 })
        for (candidate, weight) in weights {
            if roll < weight { return candidate }
            roll -= weight
        }
        return .idle
    }

    private func land(area: RoamArea) {
        // A cat that was carried around usually tidies itself up first.
        let options: [(Activity, Double)] = [(.groom, 3), (.sit, 2), (.idle, 2), (.walk, 1)]
        var roll = Double.random(in: 0..<8)
        for (candidate, weight) in options {
            if roll < weight {
                begin(candidate, area: area)
                return
            }
            roll -= weight
        }
        begin(.idle, area: area)
    }

    private func pickTarget(area: RoamArea) -> CGPoint {
        let reach = CGFloat.random(in: 80...420) * displayScale * (Bool.random() ? 1 : -1)
        var x = position.x + reach
        if x < area.minX || x > area.maxX { x = position.x - reach }
        let wanderUp = Double.random(in: 0...1) < 0.2
        let y = wanderUp
            ? area.floor + .random(in: 12...max(12, area.ceiling - area.floor))
            : area.floor + .random(in: 0...4)
        return area.clamp(CGPoint(x: x, y: y))
    }

    // MARK: - Eyes and swing

    private func updateBlink() {
        if age >= nextBlink {
            blinking = true
            if age >= nextBlink + 0.14 {
                blinking = false
                nextBlink = age + .random(in: 2.5...6)
            }
        }
    }

    /// A damped spring so a carried cat sways like a pendulum.
    private func updateSwing(dt: TimeInterval, target: CGFloat) {
        let t = CGFloat(dt)
        swingSpeed += ((target - swing) * 40 - swingSpeed * 4) * t
        swing += swingSpeed * t
    }

    /// Turns the eyes (and, when resting, the whole cat) toward a nearby cursor.
    private func updateLook(dt: TimeInterval, mouse: CGPoint) {
        let head = CGPoint(x: position.x, y: position.y + 45 * scale)
        let dx = mouse.x - head.x
        let dy = mouse.y - head.y
        let distance = hypot(dx, dy)
        var goal = CGVector(dx: facingRight ? 0.35 : -0.35, dy: 0)
        switch activity {
        case .held, .falling:
            goal = CGVector(dx: 0, dy: -0.5)
        case .bat:
            goal = CGVector(dx: facingRight ? 0.7 : -0.7, dy: 0.5)
        case .sleep, .chaseTail, .hop, .pounce, .run:
            break
        default:
            if distance < 260 * displayScale {
                goal = CGVector(dx: dx / max(distance, 1), dy: dy / max(distance, 1))
                if activity == .idle || activity == .sit || activity == .loaf, abs(dx) > 16 {
                    facingRight = dx > 0
                }
            }
        }
        let k = CGFloat(min(1, dt * 8))
        look = CGVector(dx: look.dx + (goal.dx - look.dx) * k, dy: look.dy + (goal.dy - look.dy) * k)
    }

    // MARK: - Hit testing

    /// The cat's clickable area in overlay coordinates.
    var hitRect: CGRect {
        let local: CGRect
        switch activity {
        case .held, .falling: local = CGRect(x: -18, y: 0, width: 36, height: 78)
        case .sleep, .loaf: local = CGRect(x: -30, y: 0, width: 62, height: 38)
        case .sit, .groom, .bat, .slowBlink, .yawn, .scratch, .purr:
            local = CGRect(x: -24, y: 0, width: 50, height: 60)
        default: local = CGRect(x: -34, y: 0, width: 72, height: 52)
        }
        let s = CatView.baseScale * scale
        let minX = facingRight ? local.minX : -local.maxX
        return CGRect(x: position.x + minX * s, y: position.y + local.minY * s,
                      width: local.width * s, height: local.height * s)
    }
}
