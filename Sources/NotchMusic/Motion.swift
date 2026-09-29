import SwiftUI

/// The app's motion identity. One signature spring for anything that changes
/// shape, three durations for everything else. Premium personality: springs
/// are critically damped enough that nothing visibly overshoots.
enum Motion {
    /// Shape morphs and the shared cover moving between states.
    static let morph = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// Hover, press: must feel instant.
    static let quick = Animation.easeOut(duration: 0.14)
    /// Content entering.
    static let standard = Animation.spring(response: 0.34, dampingFraction: 0.9)
    /// Exits are shorter than entrances and accelerate away.
    static let exit = Animation.easeIn(duration: 0.12)
    /// Delay between staggered siblings; total cascade stays under 200 ms.
    static let stagger: Double = 0.035
}

// MARK: - Entrance cascade

/// Rise + fade + de-blur on appear, delayed by `index * Motion.stagger`.
/// Used for the pieces inside a panel, which are not individually inserted
/// (only their parent is), so a plain transition would never fire for them.
struct Entrance: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSnapshot) private var isSnapshot

    func body(content: Content) -> some View {
        let visible = shown || isSnapshot
        return content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 7)
            .blur(radius: visible || reduceMotion ? 0 : 4)
            .onAppear {
                withAnimation(Motion.standard.delay(0.06 + Double(index) * Motion.stagger)) { shown = true }
            }
    }
}

extension View {
    func entrance(_ index: Int) -> some View { modifier(Entrance(index: index)) }
}

// MARK: - Card flip

/// Half of a card flip. The outgoing view turns to 90° (edge-on, invisible),
/// the incoming one turns in from -90°, so together they read as one card.
struct FlipModifier: ViewModifier {
    let angle: Double
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .opacity(abs(angle) >= 89 ? 0 : 1)
    }
}

extension AnyTransition {
    static var cardFlip: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FlipModifier(angle: -90), identity: FlipModifier(angle: 0))
                .animation(.easeOut(duration: 0.24).delay(0.2)),
            removal: .modifier(active: FlipModifier(angle: 90), identity: FlipModifier(angle: 0))
                .animation(.easeIn(duration: 0.2))
        )
    }
}

// MARK: - Shimmer

/// A band of light sweeping across the view: the loading state, in place of
/// a spinner, so the element keeps the shape of what it's loading.
struct Shimmer: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                    GeometryReader { geo in
                        let period = 1.3
                        let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                        let band = geo.size.width * 0.45
                        LinearGradient(colors: [.clear, palette.isLight ? palette.accent.opacity(0.5)
                                                                        : .white.opacity(reduceMotion ? 0.12 : 0.55), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: band)
                            .offset(x: reduceMotion ? geo.size.width / 2 - band / 2
                                                     : -band + (geo.size.width + band) * t)
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
    }
}

extension View {
    func shimmer(_ active: Bool) -> some View { modifier(Shimmer(active: active)) }
}

// MARK: - Snapshot flag

private struct SnapshotKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True when rendering offscreen with ImageRenderer, where onAppear-driven
    /// entrances never run; they render in their final state instead.
    var isSnapshot: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
}
