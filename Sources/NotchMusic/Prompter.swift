import SwiftUI

struct Script: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var body: String

    /// Tab label: the given title, else the script's first line, else a placeholder.
    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { return t }
        let first = body.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? "Untitled" : String(first.prefix(22))
    }
}

/// Scripts shown under the camera, one per tab. Persisted as JSON in
/// UserDefaults so they survive relaunches.
@MainActor
final class PrompterModel: ObservableObject {
    @Published var scripts: [Script] { didSet { save() } }
    @Published var selectedID: UUID { didSet { save() } }
    @Published var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: "prompterFontSize") }
    }

    static let sizeRange: ClosedRange<Double> = 13...32
    private static let scriptsKey = "prompterScripts"
    private static let selectedKey = "prompterSelected"

    init() {
        let d = UserDefaults.standard
        var loaded = d.data(forKey: Self.scriptsKey)
            .flatMap { try? JSONDecoder().decode([Script].self, from: $0) } ?? []
        if loaded.isEmpty {
            // First run with tabs: carry over the single script from before.
            loaded = [Script(title: "", body: d.string(forKey: "prompterScript") ?? "")]
        }
        scripts = loaded
        let saved = d.string(forKey: Self.selectedKey).flatMap(UUID.init(uuidString:))
        selectedID = loaded.contains { $0.id == saved } ? saved! : loaded[0].id
        fontSize = d.object(forKey: "prompterFontSize") as? Double ?? 20
    }

    private func save() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(scripts) { d.set(data, forKey: Self.scriptsKey) }
        d.set(selectedID.uuidString, forKey: Self.selectedKey)
    }

    private var selectedIndex: Int { scripts.firstIndex { $0.id == selectedID } ?? 0 }
    var selected: Script { scripts[selectedIndex] }

    var hasScript: Bool { !selected.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Two-way bindings into the selected script, for the editor fields.
    var titleBinding: Binding<String> {
        Binding(get: { self.selected.title }, set: { self.scripts[self.selectedIndex].title = $0 })
    }
    var bodyBinding: Binding<String> {
        Binding(get: { self.selected.body }, set: { self.scripts[self.selectedIndex].body = $0 })
    }

    func select(_ id: UUID) { selectedID = id }

    func add() {
        let s = Script(title: "", body: "")
        scripts.append(s)
        selectedID = s.id
    }

    /// Deletes the selected script; there is always at least one tab.
    func deleteSelected() {
        let i = selectedIndex
        if scripts.count == 1 {
            scripts[0] = Script(title: "", body: "")
            selectedID = scripts[0].id
            return
        }
        scripts.remove(at: i)
        selectedID = scripts[min(i, scripts.count - 1)].id
    }

    func selectNext() { selectedID = scripts[(selectedIndex + 1) % scripts.count].id }
    func selectPrevious() { selectedID = scripts[(selectedIndex - 1 + scripts.count) % scripts.count].id }

    func larger() { fontSize = min(Self.sizeRange.upperBound, fontSize + 2) }
    func smaller() { fontSize = max(Self.sizeRange.lowerBound, fontSize - 2) }
}

// MARK: - Tabs

/// One pill per script. The selection highlight slides between pills
/// (a shared element), so switching reads as moving, not blinking.
struct ScriptTabs: View {
    @ObservedObject var model: PrompterModel
    var canAdd = false
    @Namespace private var ns
    @Environment(\.palette) private var palette
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        // Offscreen snapshots can't draw AppKit scroll views; lay out flat there.
        if isSnapshot {
            pills.frame(maxWidth: .infinity, alignment: .leading).frame(height: 26)
        } else {
            ScrollView(.horizontal) { pills }
                .scrollIndicators(.never)
                .frame(height: 26)
        }
    }

    private var pills: some View {
            HStack(spacing: 4) {
                ForEach(model.scripts) { script in
                    let selected = script.id == model.selectedID
                    Button {
                        withAnimation(Motion.standard) { model.select(script.id) }
                    } label: {
                        Text(script.displayTitle)
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(selected ? palette.onAccent : palette.inkSecondary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background {
                                if selected {
                                    Capsule().fill(palette.ink).matchedGeometryEffect(id: "tab", in: ns)
                                } else {
                                    Capsule().fill(palette.wash)
                                }
                            }
                    }
                    .buttonStyle(PressScaleStyle())
                }
                if canAdd {
                    NotchButton(systemName: "plus", size: 10, hit: 24) {
                        withAnimation(Motion.standard) { model.add() }
                    }
                }
            }
            .padding(.horizontal, 1)
    }
}

// MARK: - Editor

struct PrompterEditView: View {
    @ObservedObject var model: PrompterModel
    let notchHeight: CGFloat
    let setMode: (NotchMode) -> Void
    @Environment(\.palette) private var palette
    @FocusState private var bodyFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                NotchButton(systemName: "chevron.left", size: 11, hit: 24, nudge: -2) { setMode(.expanded) }
                Text("Scripts")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.inkSecondary)
                Spacer()
            }
            .frame(height: notchHeight)
            .padding(.horizontal, 22)

            ScriptTabs(model: model, canAdd: true)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .entrance(0)

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    TextField("Name (optional)", text: model.titleBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    NotchButton(systemName: "trash", size: 10, hit: 22) {
                        withAnimation(Motion.standard) { model.deleteSelected() }
                    }
                    .help("Delete this script")
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Rectangle().fill(palette.ink.opacity(0.1)).frame(height: 1).padding(.horizontal, 12)

                ZStack(alignment: .topLeading) {
                    if model.selected.body.isEmpty {
                        Text("Paste or type your script")
                            .font(.system(size: 14))
                            .foregroundStyle(palette.inkTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: model.bodyBinding)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.ink)
                        .scrollContentBackground(.hidden)
                        .focused($bodyFocused)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .id(model.selectedID)   // fresh editor (and scroll position) per script
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(palette.ink.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(palette.ink.opacity(bodyFocused ? 0.35 : 0.12), lineWidth: 1))
            )
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .entrance(1)

            HStack(spacing: 18) {
                LabeledSlider(title: "Text size", value: $model.fontSize, range: PrompterModel.sizeRange)
                Button {
                    setMode(.prompter)
                } label: {
                    Label("Show", systemImage: "text.below.photo")
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
            .padding(.vertical, 12)
            .entrance(2)
        }
        .onKeyPress(.escape) { setMode(.expanded); return .handled }
        .task {
            try? await Task.sleep(for: .milliseconds(60))
            bodyFocused = true
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

// MARK: - Showing

/// The selected script in a strip directly under the camera, so reading it
/// keeps your eyes near the lens. Tabs switch scripts; the text scrolls like
/// a normal document (trackpad, wheel); nothing moves on its own.
struct PrompterView: View {
    @ObservedObject var model: PrompterModel
    let notchHeight: CGFloat
    let edit: () -> Void
    let close: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        VStack(spacing: 0) {
            // Controls live in the wings beside the camera housing.
            HStack(spacing: 2) {
                NotchButton(systemName: "pencil", size: 11, hit: 24) { edit() }
                Spacer()
                NotchButton(systemName: "textformat.size.smaller", size: 10, hit: 24) { model.smaller() }
                NotchButton(systemName: "textformat.size.larger", size: 11, hit: 24) { model.larger() }
                NotchButton(systemName: "xmark", size: 10, hit: 24) { close() }
            }
            .frame(height: notchHeight)
            .padding(.horizontal, 14)

            if model.scripts.count > 1 {
                ScriptTabs(model: model)
                    .padding(.horizontal, 22)
                    .padding(.top, 6)
            }

            ScrollView {
                scriptText
            }
            .scrollDisabled(isSnapshot)
            .overlay { if isSnapshot { scriptText.frame(maxHeight: .infinity, alignment: .top) } }
            .id(model.selectedID)   // each script opens at its top
            .transition(.opacity)
            .scrollIndicators(.automatic)
            .mask(
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.4), location: 0),
                    .init(color: .black, location: 0.05),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
            .padding(.horizontal, 26)
            .padding(.bottom, 8)
            .animation(Motion.standard, value: model.fontSize)
            .animation(Motion.quick, value: model.selectedID)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.leftArrow) { withAnimation(Motion.standard) { model.selectPrevious() }; return .handled }
        .onKeyPress(.rightArrow) { withAnimation(Motion.standard) { model.selectNext() }; return .handled }
        .onKeyPress(.escape) { edit(); return .handled }
        .task {
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
    }

    private var scriptText: some View {
        Text(model.selected.body)
            .font(.system(size: model.fontSize, weight: .semibold))
            .lineSpacing(model.fontSize * 0.28)
            .foregroundStyle(.white)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 24)
    }
}
