import SwiftUI

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
            } else {
                LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .animation(.easeOut(duration: 0.25), value: image)
    }
}

/// Four bars that dance while playing and settle when paused.
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
                        .fill(color)
                        .frame(width: barWidth, height: max(barWidth, maxHeight * v))
                }
            }
            .frame(height: maxHeight)
            .animation(.easeOut(duration: 0.3), value: isPlaying)
        }
    }
}

/// Icon button with hover highlight and press feedback.
struct NotchButton: View {
    let systemName: String
    var size: CGFloat = 16
    var hit: CGFloat = 32
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: hit, height: hit)
                .background(Circle().fill(.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Scrubber: extrapolates the position every frame from the controller's
/// anchor, and seeks on release (not on every drag tick, which would spam Music).
struct ProgressBar: View {
    @ObservedObject var music: MusicController
    let accent: Color

    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        let duration = music.track?.duration ?? 0
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !music.isPlaying || dragFraction != nil)) { ctx in
            let current = dragFraction.map { $0 * duration } ?? music.position(at: ctx.date)
            let fraction = duration > 0 ? current / duration : 0
            HStack(spacing: 10) {
                Text(format(current))
                    .frame(width: 38, alignment: .trailing)
                GeometryReader { geo in
                    let active = hovering || dragFraction != nil
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(active ? accent : .white.opacity(0.9))
                            .frame(width: max(0, geo.size.width * fraction))
                    }
                    .frame(height: active ? 7 : 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                dragFraction = min(max(v.location.x / geo.size.width, 0), 1)
                            }
                            .onEnded { v in
                                let f = min(max(v.location.x / geo.size.width, 0), 1)
                                music.seek(to: f * duration)
                                dragFraction = nil
                            }
                    )
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: active)
                }
                .frame(height: 14)
                .onHover { h in hovering = h }
                Text("-" + format(max(0, duration - current)))
                    .frame(width: 42, alignment: .leading)
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func format(_ s: Double) -> String {
        guard s.isFinite else { return "0:00" }
        let total = Int(s.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
