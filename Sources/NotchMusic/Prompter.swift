import SwiftUI

/// Teleprompter state. The scroll offset is advanced by a clock inside the
/// view's timeline rather than published, so scrolling never re-renders the
/// rest of the UI 60 times a second.
@MainActor
final class PrompterModel: ObservableObject {
    @Published var script: String {
        didSet { UserDefaults.standard.set(script, forKey: "prompterScript") }
    }
    /// Points per second.
    @Published var speed: Double {
        didSet { UserDefaults.standard.set(speed, forKey: "prompterSpeed") }
    }
    @Published var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: "prompterFontSize") }
    }
    @Published private(set) var isRunning = false
    @Published private(set) var countdownEnd: Date?

    static let speedRange: ClosedRange<Double> = 15...160
    static let sizeRange: ClosedRange<Double> = 16...36

    private(set) var offset: CGFloat = 0
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0
    private var lastTick: Date?

    init() {
        let d = UserDefaults.standard
        script = d.string(forKey: "prompterScript") ?? ""
        speed = d.object(forKey: "prompterSpeed") as? Double ?? 42
        fontSize = d.object(forKey: "prompterFontSize") as? Double ?? 24
    }

    var hasScript: Bool { !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Scroll range: the last line may rise to the reading line, no further.
    private var maxOffset: CGFloat { max(0, contentHeight - fontSize * 1.6) }

    func start() {
        offset = 0
        lastTick = nil
        countdownEnd = Date().addingTimeInterval(3)
        isRunning = true
    }

    func toggle() {
        if isRunning {
            isRunning = false
            countdownEnd = nil
        } else {
            if offset >= maxOffset { offset = 0 }   // finished: play again from the top
            lastTick = nil
            isRunning = true
        }
    }

    func restart() { start() }

    func stop() {
        isRunning = false
        countdownEnd = nil
    }

    func faster() { speed = min(Self.speedRange.upperBound, speed * 1.2) }
    func slower() { speed = max(Self.speedRange.lowerBound, speed / 1.2) }

    /// Manual scrolling (scroll wheel), works paused or running.
    func nudge(_ dy: CGFloat) {
        offset = min(max(0, offset + dy), maxOffset)
        objectWillChange.send()   // repaint even when paused (timeline not ticking)
    }

    /// Called once per frame from the view. Returns the offset to draw.
    func tick(_ now: Date) -> CGFloat {
        defer { lastTick = now }
        guard isRunning else { return offset }
        if let end = countdownEnd {
            if now < end { return offset }
            DispatchQueue.main.async { self.countdownEnd = nil }
        }
        let dt = lastTick.map { min(now.timeIntervalSince($0), 0.1) } ?? 0
        offset = min(offset + CGFloat(dt * speed), maxOffset)
        if offset >= maxOffset && contentHeight > 0 {
            // Reached the end. Publishing from inside a view update is not
            // allowed, so defer it.
            DispatchQueue.main.async { self.isRunning = false }
        }
        return offset
    }
}

// MARK: - Editor

struct PrompterEditView: View {
    @ObservedObject var model: PrompterModel
    let notchHeight: CGFloat
    let setMode: (NotchMode) -> Void
    @Environment(\.palette) private var palette
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                NotchButton(systemName: "chevron.left", size: 11, hit: 24, nudge: -2) { setMode(.expanded) }
                Text("Teleprompter")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.inkSecondary)
                Spacer()
            }
            .frame(height: notchHeight)
            .padding(.horizontal, 22)

            ZStack(alignment: .topLeading) {
                if model.script.isEmpty {
                    Text("Paste or type your script")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.inkTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $model.script)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.ink)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(palette.ink.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(palette.ink.opacity(focused ? 0.35 : 0.12), lineWidth: 1))
            )
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .entrance(0)

            HStack(spacing: 18) {
                LabeledSlider(title: "Speed", value: $model.speed, range: PrompterModel.speedRange)
                LabeledSlider(title: "Size", value: $model.fontSize, range: PrompterModel.sizeRange)
                Button {
                    model.start()
                    setMode(.prompter)
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.onAccent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(palette.accent))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!model.hasScript)
                .opacity(model.hasScript ? 1 : 0.4)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .entrance(1)
        }
        .onKeyPress(.escape) { setMode(.expanded); return .handled }
        .task {
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(palette.inkTertiary)
            Slider(value: $value, in: range)
                .controlSize(.small)
                .tint(palette.accent)
        }
    }
}

// MARK: - Prompting

/// The reading strip under the camera. Text scrolls up past a reading line
/// placed just below the notch, so the eyes stay close to the lens; lines
/// fade above and below it.
struct PrompterView: View {
    @ObservedObject var model: PrompterModel
    let notchHeight: CGFloat
    let exit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Controls live in the wings beside the camera housing.
            HStack(spacing: 2) {
                NotchButton(systemName: model.isRunning ? "pause.fill" : "play.fill", size: 11, hit: 24) {
                    model.toggle()
                }
                NotchButton(systemName: "arrow.counterclockwise", size: 11, hit: 24) { model.restart() }
                Spacer()
                NotchButton(systemName: "tortoise.fill", size: 10, hit: 24) { model.slower() }
                NotchButton(systemName: "hare.fill", size: 10, hit: 24) { model.faster() }
                NotchButton(systemName: "xmark", size: 10, hit: 24) { exit() }
            }
            .frame(height: notchHeight)
            .padding(.horizontal, 14)

            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !model.isRunning)) { ctx in
                    let offset = model.tick(ctx.date)
                    Text(model.script)
                        .font(.system(size: model.fontSize, weight: .semibold))
                        .lineSpacing(model.fontSize * 0.3)
                        .foregroundStyle(.white)
                        .frame(width: geo.size.width, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { g in
                            Color.clear
                                .onAppear { model.contentHeight = g.size.height }
                                .onChange(of: g.size.height) { _, h in model.contentHeight = h }
                        })
                        .offset(y: 8 - offset)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
                .onAppear { model.viewportHeight = geo.size.height }
            }
            .clipped()
            .mask(
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.35), location: 0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.4),
                    .init(color: .black.opacity(0.35), location: 0.75),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
            .padding(.horizontal, 26)
            .padding(.bottom, 10)
            .overlay { countdown }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.space) { model.toggle(); return .handled }
        .onKeyPress(.upArrow) { model.faster(); return .handled }
        .onKeyPress(.downArrow) { model.slower(); return .handled }
        .onKeyPress(.escape) { exit(); return .handled }
        .task {
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
    }

    @ViewBuilder private var countdown: some View {
        if let end = model.countdownEnd {
            TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                let n = Int(ceil(end.timeIntervalSince(ctx.date)))
                if n > 0 {
                    Text("\(n)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(Motion.standard, value: n)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.75))
                }
            }
            .transition(.opacity)
        }
    }
}
