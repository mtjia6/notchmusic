import SwiftUI

// MARK: - Artwork

/// Flat cover used where it's too small for 3D (collapsed notch, peek).
struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
                    .id(ObjectIdentifier(image))
            } else {
                ArtworkPlaceholder(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .animation(.easeOut(duration: 0.25), value: image.map(ObjectIdentifier.init))
    }
}

private struct ArtworkPlaceholder: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.2), Color(white: 0.11)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
        }
    }
}

/// The hero cover: a physical card. It tilts toward the pointer with a
/// specular glint that tracks the light, its shadow shifts the opposite way,
/// and it flips over when the artwork changes.
struct Artwork3DView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat
    let accent: Color
    var breathing = false

    @State private var tilt: CGPoint = .zero          // -1...1 on each axis
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            // Keyed on the image object, so a new cover is a new card that flips in.
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    ArtworkPlaceholder(size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(shape)
            .id(image.map(ObjectIdentifier.init))
            .transition(reduceMotion ? .opacity : .cardFlip)
        }
        .overlay {
            // Glint: a soft highlight positioned where the "light" hits the tilted card.
            shape
                .fill(RadialGradient(colors: [.white.opacity(hovering ? 0.28 : 0), .clear],
                                     center: UnitPoint(x: 0.5 - tilt.x * 0.6, y: 0.5 - tilt.y * 0.6),
                                     startRadius: 0, endRadius: size * 0.8))
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .opacity(breathing ? 0.72 : 1)
        .animation(breathing ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .easeOut(duration: 0.3),
                   value: breathing)
        .rotation3DEffect(.degrees(Double(-tilt.y) * 12), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(Double(tilt.x) * 12), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .scaleEffect(hovering ? 1.04 : 1)
        // Secondary motion: the shadow slides away from the light and grows as the card lifts.
        .shadow(color: accent.opacity(hovering ? 0.5 : 0.32), radius: hovering ? 16 : 11,
                x: -tilt.x * 6, y: 3 + tilt.y * 6)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: tilt)
        .animation(Motion.quick, value: hovering)
        .animation(Motion.standard, value: image.map(ObjectIdentifier.init))
        .onContinuousHover { phase in
            guard !reduceMotion else { return }
            switch phase {
            case .active(let p):
                hovering = true
                tilt = CGPoint(x: (p.x / size - 0.5) * 2, y: (p.y / size - 0.5) * 2)
            case .ended:
                hovering = false
                tilt = .zero
            }
        }
    }
}

// MARK: - Aura

/// Ambient layer: the pre-blurred cover stretched behind the panel, drifting
/// slowly while music plays and holding still when paused. It is masked to
/// stay black along the top edge so the panel still merges into the notch.
struct AuraBackground: View {
    let aura: NSImage?
    let isPlaying: Bool
    let topClearance: CGFloat
    var strength: Double = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let aura {
                    TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !isPlaying || reduceMotion)) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        Image(nsImage: aura)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fill)
                            // Oversized so its edges never enter the panel while it drifts and turns.
                            .frame(width: geo.size.width * 1.5, height: max(geo.size.height * 2, geo.size.width))
                            .scaleEffect(1.1 + 0.06 * sin(t / 3.1))
                            .rotationEffect(.degrees(5 * sin(t / 4.7)))
                            .offset(x: -geo.size.width * 0.2 + 18 * sin(t / 5.3), y: 10 * cos(t / 4.1))
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .opacity(strength)
                    .transition(.opacity)
                    .id(ObjectIdentifier(aura))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: topClearance / max(geo.size.height, 1) * 0.7),
                    .init(color: .black, location: min(1, topClearance / max(geo.size.height, 1) + 0.25)),
                    .init(color: .black.opacity(0.7), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
            // Pool the light behind the cover and let it fall off toward the controls.
            .mask(
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.55), location: 0.5),
                    .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
            )
            .clipped()
            .animation(.easeInOut(duration: 0.6), value: aura.map(ObjectIdentifier.init))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Marquee

/// Single-line text that, only if it doesn't fit, scrolls left, pauses, and
/// loops, with its edges faded instead of hard-clipped.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    @State private var textWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let overflow = textWidth - geo.size.width
            let scrolls = overflow > 1 && !reduceMotion
            Group {
                if scrolls {
                    TimelineView(.animation(minimumInterval: 1.0 / 60)) { ctx in
                        let gap: CGFloat = 36
                        let distance = textWidth + gap
                        let speed: CGFloat = 28                          // points per second
                        let pause: Double = 2.2
                        let cycle = pause + Double(distance / speed)
                        let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
                        let x = t < pause ? 0 : -CGFloat(t - pause) * speed
                        HStack(spacing: gap) { label; label }
                            .offset(x: x)
                    }
                    .frame(width: geo.size.width, alignment: .leading)
                    .mask(
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.04),
                            .init(color: .black, location: 0.9),
                            .init(color: .clear, location: 1),
                        ], startPoint: .leading, endPoint: .trailing)
                    )
                } else {
                    label.frame(width: geo.size.width, alignment: .leading)
                }
            }
            .clipped()
        }
        .frame(height: lineHeight)
        .background(
            label.fixedSize().hidden()
                .background(GeometryReader { g in Color.clear.preference(key: WidthKey.self, value: g.size.width) })
        )
        .onPreferenceChange(WidthKey.self) { textWidth = $0 }
    }

    private var label: some View {
        Text(text).font(font).foregroundStyle(color).lineLimit(1).fixedSize()
    }

    private var lineHeight: CGFloat {
        NSFont.systemFont(ofSize: 15).boundingRectForFont.height
    }

    private struct WidthKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }
}

// MARK: - Equalizer

/// Four bars that dance while playing and settle into a low line when paused.
struct EqualizerBars: View {
    let isPlaying: Bool
    let color: Color
    var barWidth: CGFloat = 3
    var maxHeight: CGFloat = 14

    private let speeds: [Double] = [5.1, 7.3, 4.2, 6.4]
    private let phases: [Double] = [0, 1.7, 3.1, 0.9]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barWidth * 0.8) {
                ForEach(0..<4, id: \.self) { i in
                    // Sum of two sines reads as more organic than one.
                    let v = isPlaying
                        ? 0.5 + 0.3 * sin(t * speeds[i] + phases[i]) + 0.2 * sin(t * speeds[i] * 1.9 + phases[i] * 2)
                        : 0.18
                    Capsule()
                        .fill(LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                        .frame(width: barWidth, height: max(barWidth, maxHeight * v))
                }
            }
            .frame(height: maxHeight)
            .animation(.easeOut(duration: 0.3), value: isPlaying)
        }
    }
}

// MARK: - Buttons

/// Icon button: hover lifts a soft disc behind it, press squashes it, and
/// directional buttons nudge the way they point (anticipation for "next").
struct NotchButton: View {
    let systemName: String
    var size: CGFloat = 16
    var hit: CGFloat = 32
    var nudge: CGFloat = 0
    let action: () -> Void

    @State private var hovering = false
    @State private var taps = 0
    @State private var nudged = false

    var body: some View {
        Button {
            taps += 1
            if nudge != 0 {
                withAnimation(.easeOut(duration: 0.09)) { nudged = true }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.09)) { nudged = false }
            }
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.86))
                .contentTransition(.symbolEffect(.replace.downUp))
                .offset(x: nudged ? nudge : 0)
                .frame(width: hit, height: hit)
                .background(Circle().fill(.white.opacity(hovering ? 0.12 : 0)).scaleEffect(hovering ? 1 : 0.7))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct PillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.25 : 0.14)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

// MARK: - Progress

/// Scrubber. Extrapolates the position every frame from the controller's
/// anchor and seeks on release (not every drag tick, which would spam Music).
/// Hovering thickens the track and reveals a knob; loading shows a shimmer.
struct ProgressBar: View {
    @ObservedObject var music: MusicController
    let accent: Color

    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        let duration = music.track?.duration ?? 0
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !music.isPlaying || dragFraction != nil)) { ctx in
            let current = dragFraction.map { $0 * duration } ?? music.position(at: ctx.date)
            let fraction = duration > 0 ? min(max(current / duration, 0), 1) : 0
            let active = hovering || dragFraction != nil
            HStack(spacing: 10) {
                Text(format(current))
                    .frame(width: 36, alignment: .trailing)
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                            .shimmer(music.isLoading)
                        Capsule()
                            .fill(active ? accent : .white.opacity(0.92))
                            .frame(width: max(0, w * fraction))
                    }
                    .frame(height: active ? 6 : 4)
                    // The knob lives in an overlay so its size never inflates the track.
                    .overlay(alignment: .leading) {
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.4), radius: 3)
                            .frame(width: 11, height: 11)
                            .scaleEffect(active ? 1 : 0.01)
                            .opacity(active ? 1 : 0)
                            .offset(x: w * fraction - 5.5)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in dragFraction = min(max(v.location.x / w, 0), 1) }
                            .onEnded { v in
                                music.seek(to: min(max(v.location.x / w, 0), 1) * duration)
                                dragFraction = nil
                            }
                    )
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: active)
                }
                .frame(height: 16)
                .onHover { h in hovering = h }
                Text("-" + format(max(0, duration - current)))
                    .frame(width: 40, alignment: .leading)
            }
            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func format(_ s: Double) -> String {
        guard s.isFinite else { return "0:00" }
        let total = Int(s.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Skeleton

/// Placeholder row shaped like a search result, shown while results load.
struct SkeletonRow: View {
    let widths: (CGFloat, CGFloat)
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 5) {
                Capsule().frame(width: widths.0, height: 8)
                Capsule().frame(width: widths.1, height: 6).opacity(0.7)
            }
            Spacer()
        }
        .foregroundStyle(.white.opacity(0.08))
        .shimmer(true)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}
