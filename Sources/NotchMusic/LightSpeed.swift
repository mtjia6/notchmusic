import SwiftUI

/// "Light speed" background: thin streaks radiating from the camera notch,
/// each drawn three times with a slight angular offset (blue, warm, white core)
/// for a chromatic-aberration fringe, added onto the panel with plus-lighter
/// blending. Streaks lengthen as they travel outward (perspective) and fade in
/// near the origin and out at the edges. They stream while music plays and
/// hold still when paused.
struct LightSpeedField: View {
    let origin: UnitPoint
    let isPlaying: Bool
    var intensity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Ray {
        let angle: Double
        let speed: Double
        let offset: Double
        let length: Double
        let width: CGFloat
        let brightness: Double
    }

    /// Fixed seed: the pattern is the same every launch and never "jumps".
    private static let rays: [Ray] = {
        var rng = SplitMix64(seed: 0x9E3779B97F4A7C15)
        return (0..<110).map { _ in
            Ray(angle: rng.next(in: 0..<(2 * .pi)),
                speed: rng.next(in: 0.05..<0.14),
                offset: rng.next(in: 0..<1),
                length: rng.next(in: 0.12..<0.4),
                width: CGFloat(rng.next(in: 0.5..<1.5)),
                brightness: rng.next(in: 0.35..<1))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying || reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let o = CGPoint(x: size.width * origin.x, y: size.height * origin.y)
                // Far enough to reach the farthest corner.
                let reach = hypot(max(o.x, size.width - o.x), max(o.y, size.height - o.y))
                gc.blendMode = .plusLighter
                for ray in Self.rays {
                    let d = (t * ray.speed + ray.offset).truncatingRemainder(dividingBy: 1)
                    let r0 = reach * (0.06 + d * d * 1.05)           // accelerates outward
                    let r1 = r0 + reach * ray.length * (0.35 + d)     // lengthens with distance
                    let alpha = sin(d * .pi) * ray.brightness * intensity
                    guard alpha > 0.02 else { continue }
                    for (dAngle, color, w) in [(-0.006, Color(red: 0.35, green: 0.6, blue: 1), 1.6),
                                               (0.006, Color(red: 1, green: 0.62, blue: 0.3), 1.6),
                                               (0.0, Color.white, 0.7)] {
                        let a = ray.angle + dAngle
                        let start = CGPoint(x: o.x + cos(a) * r0, y: o.y + sin(a) * r0)
                        let end = CGPoint(x: o.x + cos(a) * r1, y: o.y + sin(a) * r1)
                        var p = Path()
                        p.move(to: start)
                        p.addLine(to: end)
                        // Fades in and out along its length, so each streak has soft ends.
                        let grad = Gradient(colors: [color.opacity(0), color.opacity(alpha * 0.55), color.opacity(0)])
                        gc.stroke(p, with: .linearGradient(grad, startPoint: start, endPoint: end),
                                  lineWidth: ray.width * w)
                    }
                }
            }
        }
        .allowsHitTesting(false)
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
