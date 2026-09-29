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
    @Environment(\.palette) private var palette
    var body: some View {
        ZStack {
            LinearGradient(colors: palette.isLight ? [Color(white: 0.88), Color(white: 0.8)]
                                                   : [Color(white: 0.2), Color(white: 0.11)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(palette.inkTertiary)
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
    @Environment(\.palette) private var palette
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
        .overlay(shape.strokeBorder(palette.ink.opacity(0.08), lineWidth: 0.5))
        .opacity(breathing ? 0.72 : 1)
        .animation(breathing ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .easeOut(duration: 0.3),
                   value: breathing)
        .rotation3DEffect(.degrees(Double(-tilt.y) * 12), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(Double(tilt.x) * 12), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .scaleEffect(hovering ? 1.04 : 1)
        // Secondary motion: the shadow slides away from the light and grows as the card lifts.
        .shadow(color: accent.opacity(palette.isLight ? (hovering ? 0.45 : 0.3) : (hovering ? 0.5 : 0.32)),
                radius: hovering ? 18 : 12,
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
    enum Style { case plain, glass, solid }

    let systemName: String
    var size: CGFloat = 16
    var hit: CGFloat = 32
    var nudge: CGFloat = 0
    var style: Style = .plain
    let action: () -> Void

    @State private var hovering = false
    @State private var nudged = false
    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            if nudge != 0 {
                withAnimation(.easeOut(duration: 0.09)) { nudged = true }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.09)) { nudged = false }
            }
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(glyphColor)
                .contentTransition(.symbolEffect(.replace.downUp))
                .offset(x: nudged ? nudge : 0)
                .frame(width: hit, height: hit)
                .background(disc)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
    }

    private var glyphColor: Color {
        switch style {
        case .solid: palette.onAccent
        case .glass: palette.ink
        case .plain: palette.ink.opacity(hovering ? 1 : 0.82)
        }
    }

    @ViewBuilder private var disc: some View {
        switch style {
        case .plain:
            Circle().fill(palette.wash.opacity(hovering ? 1.6 : 0)).scaleEffect(hovering ? 1 : 0.7)
        case .glass:
            Circle()
                .fill(palette.ink.opacity(hovering ? 0.26 : 0.16))
                .overlay(Circle().strokeBorder(palette.ink.opacity(0.3), lineWidth: 0.75))
        case .solid:
            Circle()
                .fill(palette.accent)
                .scaleEffect(hovering ? 1.05 : 1)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
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
    @Environment(\.palette) private var palette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(palette.wash.opacity(configuration.isPressed ? 2.4 : 1.6)))
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
    @Environment(\.palette) private var palette

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
                        Capsule().fill(palette.ink.opacity(palette.isLight ? 0.1 : 0.14))
                            .shimmer(music.isLoading)
                        Capsule()
                            .fill(active || palette.isLight ? accent : palette.ink.opacity(0.92))
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
            .foregroundStyle(palette.inkTertiary)
        }
    }

    private func format(_ s: Double) -> String {
        guard s.isFinite else { return "0:00" }
        let total = Int(s.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Wave progress

/// Progress as a wave: the played part is a bright line, the rest faint, with
/// a glowing dot at the playhead. The wave ripples while playing (the music is
/// moving) and relaxes toward a flatter line when paused. Drag to seek.
struct WaveProgress: View {
    @ObservedObject var music: MusicController

    @State private var dragFraction: Double?
    @State private var hovering = false
    @State private var amplitude: CGFloat = 1
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let duration = music.track?.duration ?? 0
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !music.isPlaying && dragFraction == nil)) { ctx in
            let now = ctx.date
            let current = dragFraction.map { $0 * duration } ?? music.position(at: now)
            let fraction = duration > 0 ? min(max(current / duration, 0), 1) : 0
            let phase = reduceMotion ? 0 : now.timeIntervalSinceReferenceDate * 2.2
            VStack(spacing: 6) {
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    let played = w * fraction
                    let wave = WaveShape(phase: phase, amplitude: amplitude * (hovering ? 1.25 : 1))
                    ZStack(alignment: .leading) {
                        wave.stroke(palette.ink.opacity(0.32), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                            .mask(Rectangle().padding(.leading, played))
                        wave.stroke(palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .mask(alignment: .leading) { Rectangle().frame(width: played) }
                            .shadow(color: palette.ink.opacity(0.5), radius: 3)
                            .shimmer(music.isLoading)
                        Circle()
                            .fill(palette.ink)
                            .frame(width: hovering || dragFraction != nil ? 11 : 8)
                            .shadow(color: palette.ink.opacity(0.9), radius: 5)
                            .position(x: played, y: wave.y(at: played, width: w, height: h))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in dragFraction = min(max(v.location.x / w, 0), 1) }
                            .onEnded { v in
                                music.seek(to: min(max(v.location.x / w, 0), 1) * duration)
                                dragFraction = nil
                            }
                    )
                }
                .frame(height: 22)
                .onHover { h in withAnimation(Motion.quick) { hovering = h } }

                HStack {
                    Text(format(current))
                    Spacer()
                    Text("-" + format(max(0, duration - current)))
                }
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(palette.inkSecondary)
            }
        }
        .onAppear { amplitude = music.isPlaying ? 1 : 0.35 }
        .onChange(of: music.isPlaying) { _, playing in
            withAnimation(.easeInOut(duration: 0.6)) { amplitude = playing ? 1 : 0.35 }
        }
    }

    private func format(_ s: Double) -> String {
        guard s.isFinite else { return "0:00" }
        let total = Int(s.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Two summed sines under an envelope that tapers to zero at both ends, so the
/// line starts and finishes flat instead of being cut off mid-swing.
struct WaveShape: Shape {
    var phase: Double
    var amplitude: CGFloat

    var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
    }

    func y(at x: CGFloat, width: CGFloat, height: CGFloat) -> CGFloat {
        guard width > 0 else { return height / 2 }
        let u = Double(x / width)
        let envelope = sin(u * .pi)                           // 0 at the ends, 1 in the middle
        let v = 0.65 * sin(u * 2 * .pi * 5.5 - phase) + 0.35 * sin(u * 2 * .pi * 9.2 - phase * 1.6 + 1.3)
        return height / 2 + CGFloat(v * envelope) * (height / 2 - 2) * amplitude
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let step: CGFloat = 2
        var x: CGFloat = 0
        p.move(to: CGPoint(x: 0, y: y(at: 0, width: rect.width, height: rect.height)))
        while x <= rect.width {
            p.addLine(to: CGPoint(x: x, y: y(at: x, width: rect.width, height: rect.height)))
            x += step
        }
        return p
    }
}

// MARK: - Glass

/// Real behind-window blur (the desktop shows through, frosted), masked to the
/// notch silhouette. `maskImage` is the documented way to shape an
/// NSVisualEffectView; it is regenerated on every layout so it follows the
/// frame while the panel morphs.
struct GlassBackground: NSViewRepresentable {
    var bottomRadius: CGFloat

    func makeNSView(context: Context) -> ShapedEffectView {
        let v = ShapedEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .vibrantLight)
        return v
    }

    func updateNSView(_ v: ShapedEffectView, context: Context) {
        v.bottomRadius = bottomRadius
    }

    final class ShapedEffectView: NSVisualEffectView {
        var bottomRadius: CGFloat = 26 { didSet { if bottomRadius != oldValue { updateMask() } } }

        override func layout() {
            super.layout()
            updateMask()
        }

        private func updateMask() {
            let size = bounds.size
            guard size.width > 0, size.height > 0 else { return }
            let radius = bottomRadius
            maskImage = NSImage(size: size, flipped: true) { rect in
                let path = NotchShape(topRadius: NotchViewModel.topFlare, bottomRadius: radius).path(in: rect)
                NSColor.black.setFill()
                NSBezierPath(cgPath: path.cgPath).fill()
                return true
            }
        }
    }
}

// MARK: - Skeleton

/// Placeholder row shaped like a search result, shown while results load.
struct SkeletonRow: View {
    let widths: (CGFloat, CGFloat)
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 5) {
                Capsule().frame(width: widths.0, height: 8)
                Capsule().frame(width: widths.1, height: 6).opacity(0.7)
            }
            Spacer()
        }
        .foregroundStyle(palette.ink.opacity(0.07))
        .shimmer(true)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

// MARK: - Glow

/// Light around the notch: a blue-to-green gradient in two
/// angular gradients turning in opposite directions, so the colors flow into
/// each other instead of spinning as one rigid ring. Wide blurred halo plus a
/// thin rim. Flows while playing, holds dim when paused, absent with nothing
/// loaded. Optionally tinted from the cover instead.
struct NotchGlow<S: Shape>: View {
    let shape: S
    /// nil = rainbow; otherwise hues around the cover color.
    let accent: NSColor?
    let isPlaying: Bool
    let hasTrack: Bool
    var intensity: Double = 1
    @State private var clock = RayClock()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var rainbow: [Color] { [
        Color(red: 0.16, green: 0.42, blue: 1.0),    // blue
        Color(red: 0.22, green: 0.66, blue: 1.0),    // sky
        Color(red: 0.13, green: 0.86, blue: 0.93),   // cyan
        Color(red: 0.2, green: 0.9, blue: 0.62),     // aqua green
        Color(red: 0.36, green: 0.86, blue: 0.36),   // green
        Color(red: 0.13, green: 0.78, blue: 0.8),    // teal
        Color(red: 0.16, green: 0.42, blue: 1.0),    // back to blue, seamless
    ] }

    var body: some View {
        let colors = accent.map(Self.spectrum(from:)) ?? Self.rainbow
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { ctx in
            let t = clock.advance(to: ctx.date, targetSpeed: isPlaying ? 1 : 0.3)
            let a = AngularGradient(colors: colors, center: .center, angle: .degrees(t * 45))
            let b = AngularGradient(colors: colors.reversed(), center: .center, angle: .degrees(-t * 28 + 90))
            ZStack {
                shape.stroke(a, lineWidth: 12).blur(radius: 16)
                shape.stroke(b, lineWidth: 8).blur(radius: 10).opacity(0.6)
                shape.stroke(a, lineWidth: 2.5).blur(radius: 2)
            }
        }
        .opacity(hasTrack ? (isPlaying ? intensity : intensity * 0.6) : 0)
        .animation(.easeInOut(duration: 0.6), value: isPlaying)
        .animation(.easeInOut(duration: 0.6), value: hasTrack)
        .allowsHitTesting(false)
    }

    /// Accent plus two neighbouring hues, so the glow shimmers rather than
    /// being a flat single-color outline.
    static func spectrum(from accent: NSColor) -> [Color] {
        guard let c = accent.usingColorSpace(.deviceRGB) else { return [.white, .white] }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        let sat = max(s, 0.55), bri = max(b, 0.85)
        func hue(_ d: CGFloat) -> Color {
            Color(nsColor: NSColor(hue: (h + d + 1).truncatingRemainder(dividingBy: 1), saturation: sat, brightness: bri, alpha: 1))
        }
        let base = Color(nsColor: NSColor(hue: h, saturation: sat, brightness: bri, alpha: 1))
        return [base, hue(0.09), .white.opacity(0.9), hue(-0.09), base]
    }
}
