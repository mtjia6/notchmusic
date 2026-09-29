import SwiftUI

/// "Light speed" background: thin streaks radiating from the camera notch.
/// Each streak is a soft bloom, blue and warm fringes offset by a hair of
/// angle (chromatic aberration), and a hot white core, all added onto the
/// panel with plus-lighter blending so overlaps brighten like light does.
/// Streaks lengthen as they travel outward (perspective), fade at both ends,
/// and twinkle as they pass. Always moving: full speed while music plays,
/// easing down to a slow drift when paused.
struct LightSpeedField: View {
    let origin: UnitPoint
    let isPlaying: Bool
    var intensity: Double = 1
    @State private var clock = RayClock()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Ray {
        let angle: Double
        let speed: Double
        let offset: Double
        let length: Double
        let width: CGFloat
        let brightness: Double
        let twinkle: Double
    }

    /// Fixed seed: the pattern is the same every launch and never "jumps".
    private static let rays: [Ray] = {
        var rng = SplitMix64(seed: 0x9E3779B97F4A7C15)
        return (0..<110).map { _ in
            Ray(angle: rng.next(in: 0..<(2 * .pi)),
                speed: rng.next(in: 0.05..<0.14),
                offset: rng.next(in: 0..<1),
                length: rng.next(in: 0.12..<0.4),
                width: CGFloat(rng.next(in: 0.6..<1.6)),
                brightness: rng.next(in: 0.45..<1),
                twinkle: rng.next(in: 0..<(2 * .pi)))
        }
    }()

    private static let fringes: [(dAngle: Double, color: Color, width: CGFloat, alpha: Double)] = [
        (0, Color(red: 0.55, green: 0.75, blue: 1), 5, 0.18),           // bloom
        (-0.007, Color(red: 0.25, green: 0.55, blue: 1), 1.8, 0.95),    // blue fringe
        (0.007, Color(red: 1, green: 0.58, blue: 0.2), 1.8, 0.9),       // warm fringe
        (0, .white, 0.8, 1),                                            // hot core
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { ctx in
            Canvas { gc, size in
                let t = clock.advance(to: ctx.date, targetSpeed: isPlaying ? 1 : 0.3)
                let now = ctx.date.timeIntervalSinceReferenceDate
                let o = CGPoint(x: size.width * origin.x, y: size.height * origin.y)
                // Far enough to reach the farthest corner.
                let reach = hypot(max(o.x, size.width - o.x), max(o.y, size.height - o.y))
                gc.blendMode = .plusLighter
                for ray in Self.rays {
                    let d = (t * ray.speed + ray.offset).truncatingRemainder(dividingBy: 1)
                    let r0 = reach * (0.06 + d * d * 1.05)           // accelerates outward
                    let r1 = r0 + reach * ray.length * (0.35 + d)     // lengthens with distance
                    let flare = 0.75 + 0.25 * sin(now * 3.1 + ray.twinkle)
                    let alpha = sin(d * .pi) * ray.brightness * flare * intensity
                    guard alpha > 0.02 else { continue }
                    for f in Self.fringes {
                        let a = ray.angle + f.dAngle
                        let start = CGPoint(x: o.x + cos(a) * r0, y: o.y + sin(a) * r0)
                        let end = CGPoint(x: o.x + cos(a) * r1, y: o.y + sin(a) * r1)
                        var p = Path()
                        p.move(to: start)
                        p.addLine(to: end)
                        // Brightest just past the middle, soft at both ends.
                        let peak = f.color.opacity(min(1, alpha * f.alpha))
                        let grad = Gradient(stops: [.init(color: f.color.opacity(0), location: 0),
                                                    .init(color: peak, location: 0.6),
                                                    .init(color: f.color.opacity(0), location: 1)])
                        gc.stroke(p, with: .linearGradient(grad, startPoint: start, endPoint: end),
                                  style: StrokeStyle(lineWidth: ray.width * f.width, lineCap: .round))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Integrates time at a variable speed, so slowing down on pause eases the
/// streaks instead of making them jump (t * speed would teleport them).
final class RayClock {
    private var last: Date?
    private var phase: Double = 0
    private var speed: Double = 1

    func advance(to date: Date, targetSpeed: Double) -> Double {
        let dt = last.map { min(date.timeIntervalSince($0), 0.1) } ?? 0
        last = date
        speed += (targetSpeed - speed) * min(1, dt * 2.5)   // ~0.4 s ease toward target
        phase += dt * speed
        return phase
    }
}

/// Small deterministic RNG so the ray layout is stable across launches.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func next(in range: Range<Double>) -> Double {
        range.lowerBound + Double(next() >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
    }
}
