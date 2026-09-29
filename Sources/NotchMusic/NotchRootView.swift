import ServiceManagement
import SwiftUI

struct NotchRootView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var music: MusicController
    let setMode: (NotchMode) -> Void

    /// Shared-element space: the small cover in the notch and the big cover
    /// in the panel are the same element, so it travels between the two.
    @Namespace private var ns
    @AppStorage("darkPanel") private var darkPanel = false
    @AppStorage("albumGlow") private var albumGlow = false

    var body: some View {
        let hasTrack = music.track != nil
        let size = vm.bodySize(hasTrack: hasTrack)
        let flare = NotchViewModel.topFlare
        let shape = NotchShape(topRadius: flare, bottomRadius: vm.bottomRadius)
        let open = vm.mode == .expanded || vm.mode == .search
        let glass = open && !darkPanel
        let palette = glass ? Palette.glass : Palette.dark(accent: music.accent)

        ZStack(alignment: .top) {
            // Glow first, so it sits behind the body and only spills outside it.
            NotchGlow(shape: shape, accent: albumGlow ? music.accent : nil, isPlaying: music.isPlaying,
                      hasTrack: hasTrack, intensity: 1)

            // Body: black always underneath; the light surface fades in over it
            // as the notch opens, so the morph reads as "the notch blooms white".
            shape.fill(Color.black)
                .shadow(color: .black.opacity(open ? 0.35 : vm.mode == .peek ? 0.3 : 0), radius: 22, y: 10)
            GlassSurface(shape: shape, bottomRadius: vm.bottomRadius)
                .opacity(glass ? 1 : 0)

            ZStack(alignment: .top) {
                if open {
                    // Light pouring out of the camera notch.
                    LightSpeedField(origin: UnitPoint(x: 0.5, y: vm.notchSize.height / 2 / max(size.height, 1)),
                                    isPlaying: music.isPlaying, intensity: glass ? 0.9 : 1)
                        .transition(.opacity.animation(.easeOut(duration: 0.5)))
                }
                if open && !glass {
                    // Quieter behind the search list, where text needs the contrast.
                    AuraBackground(aura: music.aura, isPlaying: music.isPlaying,
                                   topClearance: vm.notchSize.height,
                                   strength: vm.mode == .search ? 0.28 : 0.55)
                        .transition(.opacity.animation(.easeOut(duration: 0.4)))
                }

                // Each mode's content is laid out at its *final* size and revealed
                // by the animating clip, so text never re-wraps mid-animation.
                switch vm.mode {
                case .collapsed:
                    CollapsedContent(music: music, notchSize: vm.notchSize, ns: ns)
                        .frame(size: vm.bodySize(for: .collapsed, hasTrack: hasTrack))
                        .transition(.opacity.animation(Motion.exit))
                case .peek:
                    PeekContent(music: music, notchSize: vm.notchSize, ns: ns)
                        .frame(size: vm.bodySize(for: .peek, hasTrack: hasTrack))
                        .transition(.opacity.animation(Motion.exit))
                case .expanded:
                    ExpandedContent(music: music, notchHeight: vm.notchSize.height, ns: ns, setMode: setMode)
                        .frame(size: vm.bodySize(for: .expanded, hasTrack: hasTrack))
                        .transition(.opacity.animation(Motion.exit))
                case .search:
                    SearchContent(music: music, notchHeight: vm.notchSize.height, setMode: setMode)
                        .frame(size: vm.bodySize(for: .search, hasTrack: hasTrack))
                        .transition(.opacity.animation(Motion.exit))
                }

                // On the light card the camera housing sits in a black cutout,
                // slightly larger than the hardware notch so it reads as a
                // deliberate frame instead of a mismatched edge.
                UnevenRoundedRectangle(bottomLeadingRadius: 11, bottomTrailingRadius: 11, style: .continuous)
                    .fill(Color.black)
                    .frame(width: vm.notchSize.width + 8, height: vm.notchSize.height + 4)
                    .opacity(glass ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .frame(width: size.width + 2 * flare, height: size.height, alignment: .top)
            .clipShape(shape)
            .environment(\.palette, palette)

            // A hairline along the edge: the panel reads as a physical slab.
            shape
                .stroke(Color.white.opacity(glass ? 0.38 : open ? 0.1 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .frame(width: size.width + 2 * flare, height: size.height)
        .contextMenu { AppMenu(darkPanel: $darkPanel, albumGlow: $albumGlow) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Motion.morph, value: hasTrack)
        .animation(Motion.morph, value: vm.mode)
        .animation(.easeInOut(duration: 0.3), value: darkPanel)
        .environment(\.colorScheme, .dark)
    }
}

private extension View {
    func frame(size: CGSize) -> some View { frame(width: size.width, height: size.height) }
}

// MARK: - Collapsed

private struct CollapsedContent: View {
    @ObservedObject var music: MusicController
    let notchSize: CGSize
    let ns: Namespace.ID

    var body: some View {
        if music.track != nil {
            NotchWings(music: music, notchSize: notchSize, ns: ns)
        }
    }
}

/// Cover in the left wing, equalizer in the right: the notch-height strip
/// shared by the collapsed and peek states.
private struct NotchWings: View {
    @ObservedObject var music: MusicController
    let notchSize: CGSize
    let ns: Namespace.ID

    var body: some View {
        let wing = notchSize.height + 10
        HStack(spacing: 0) {
            ArtworkView(image: music.artwork, size: notchSize.height - 12, radius: 6)
                .matchedGeometryEffect(id: "cover", in: ns)
                .opacity(music.isLoading ? 0.6 : 1)
                .frame(width: wing)
            Spacer(minLength: notchSize.width)
            EqualizerBars(isPlaying: music.isPlaying, color: Color(nsColor: music.accent),
                          barWidth: 2.5, maxHeight: notchSize.height * 0.4)
                .frame(width: wing)
        }
        .frame(height: notchSize.height)
        .padding(.horizontal, NotchViewModel.topFlare)
    }
}

// MARK: - Peek

/// Shown for a moment when the song changes while collapsed.
private struct PeekContent: View {
    @ObservedObject var music: MusicController
    let notchSize: CGSize
    let ns: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            NotchWings(music: music, notchSize: notchSize, ns: ns)
            if let track = music.track {
                VStack(spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(track.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .lineLimit(1)
                .padding(.horizontal, 28)
                .entrance(0)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Expanded

private struct ExpandedContent: View {
    @ObservedObject var music: MusicController
    let notchHeight: CGFloat
    let ns: Namespace.ID
    let setMode: (NotchMode) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            // Strip beside the camera housing: nothing may sit in the middle.
            HStack {
                EqualizerBars(isPlaying: music.isPlaying, color: palette.ink, barWidth: 2.5, maxHeight: 11)
                    .opacity(music.track == nil ? 0 : 0.9)
                Spacer()
                NotchButton(systemName: "magnifyingglass", size: 12, hit: 26) { setMode(.search) }
            }
            .frame(height: notchHeight)
            .padding(.horizontal, 24)
            .entrance(3)

            if let track = music.track {
                HStack(alignment: .center, spacing: 14) {
                    Artwork3DView(image: music.artwork, size: 64, radius: 14, accent: .black,
                                  breathing: music.isLoading)
                        .matchedGeometryEffect(id: "cover", in: ns)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(music.isLoading ? "Loading" : music.isPlaying ? "Now Playing" : "Paused")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.inkSecondary)
                            .contentTransition(.opacity)
                        MarqueeText(text: track.title, font: .system(size: 24, weight: .medium), color: palette.ink)
                            .frame(height: 30)
                        Text(track.artist)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.inkSecondary)
                            .lineLimit(1)
                    }
                    .id(track.id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)),
                                            removal: .opacity.combined(with: .offset(y: -6))))
                    .entrance(0)

                    Spacer(minLength: 10)

                    HStack(spacing: 10) {
                        NotchButton(systemName: "backward.fill", size: 11, hit: 32, nudge: -2, style: .glass) {
                            music.previous()
                        }
                        NotchButton(systemName: music.isPlaying || music.isLoading ? "pause.fill" : "play.fill",
                                    size: 15, hit: 44, style: .solid) { music.playPause() }
                            .opacity(music.isLoading ? 0.6 : 1)
                            .disabled(music.isLoading)
                        NotchButton(systemName: "forward.fill", size: 11, hit: 32, nudge: 2, style: .glass) {
                            music.next()
                        }
                    }
                    .entrance(1)
                }
                .animation(Motion.standard, value: track.id)
                .animation(Motion.quick, value: music.isLoading)
                .animation(Motion.quick, value: music.isPlaying)
                .padding(.horizontal, 22)
                .padding(.top, 8)

                // Inset glass tray holding the wave, like a recessed control strip.
                WaveProgress(music: music)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(palette.ink.opacity(0.1))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(palette.ink.opacity(0.28), lineWidth: 0.75))
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .entrance(2)
            } else {
                HStack(spacing: 14) {
                    Artwork3DView(image: nil, size: 64, radius: 14, accent: .black)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nothing playing")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(palette.ink)
                        Text("Search for a song or open Music")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.inkSecondary)
                    }
                    .entrance(0)
                    Spacer()
                    Button("Open Music") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app"))
                    }
                    .buttonStyle(PillStyle())
                    .entrance(1)
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Frosted glass body: real behind-window blur, a faint dark tint so white
/// text holds up on bright wallpapers, and a light sheen from the top-left.
/// Offscreen snapshots can't capture the blur, so they get a stand-in.
private struct GlassSurface: View {
    let shape: NotchShape
    let bottomRadius: CGFloat
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        ZStack {
            if isSnapshot {
                shape.fill(LinearGradient(colors: [Color(red: 0.62, green: 0.68, blue: 0.76),
                                                   Color(red: 0.55, green: 0.6, blue: 0.68)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            } else {
                GlassBackground(bottomRadius: bottomRadius)
            }
            shape.fill(Color.black.opacity(0.12))
            shape.fill(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0)],
                                      startPoint: .topLeading, endPoint: .center))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Search

private struct SearchContent: View {
    @ObservedObject var music: MusicController
    let notchHeight: CGFloat
    let setMode: (NotchMode) -> Void

    @State private var query = ""
    @Environment(\.palette) private var palette
    @FocusState private var focused: Bool

    var body: some View {
        let accent = palette.accent
        VStack(spacing: 0) {
            HStack {
                NotchButton(systemName: "chevron.left", size: 11, hit: 24, nudge: -2) { setMode(.expanded) }
                Spacer()
            }
            .frame(height: notchHeight)
            .padding(.horizontal, 22)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.ink.opacity(0.5))
                TextField("Songs, artists, albums", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.ink)
                    .tint(accent)
                    .focused($focused)
                    .onSubmit {
                        if let first = music.searchResults.first { play(first) }
                        else if let first = music.catalogResults.first { open(first) }
                    }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(palette.ink.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.ink.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(focused ? accent.opacity(0.55) : palette.ink.opacity(0.06), lineWidth: 1))
            )
            .animation(Motion.quick, value: focused)
            .animation(Motion.quick, value: query.isEmpty)
            .padding(.horizontal, 20)
            .padding(.top, 10)   // clear the camera cutout
            .entrance(0)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if music.isSearching && music.searchResults.isEmpty && music.catalogResults.isEmpty {
                        ForEach(0..<4, id: \.self) { i in
                            SkeletonRow(widths: ([150, 120, 170, 135][i], [90, 70, 105, 80][i]))
                        }
                        .padding(.top, 8)
                        .transition(.opacity)
                    }
                    if !music.searchResults.isEmpty {
                        SectionHeader(title: "In your library")
                        ForEach(Array(music.searchResults.enumerated()), id: \.element.id) { i, r in
                            ResultRow(title: r.title, artist: r.artist, art: nil, trailing: "play.fill",
                                      index: i) { play(r) }
                        }
                    }
                    if !music.catalogResults.isEmpty {
                        HStack(alignment: .lastTextBaseline) {
                            SectionHeader(title: "Apple Music")
                            Spacer()
                            if !music.canPlayCatalog {
                                Button("Enable one-click play") { ShortcutRunner.install() }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(accent)
                                    .padding(.horizontal, 10)
                            }
                        }
                        ForEach(Array(music.catalogResults.enumerated()), id: \.element.id) { i, song in
                            ResultRow(title: song.title, artist: song.artist, art: song.artworkURL,
                                      trailing: music.canPlayCatalog ? "play.fill" : "arrow.up.forward",
                                      index: music.searchResults.count + i) { open(song) }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .scrollIndicators(.never)
            .mask(
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                       .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay {
                if music.searchResults.isEmpty && music.catalogResults.isEmpty
                    && !music.isSearching && !query.isEmpty {
                    Text("No matches for \u{201C}\(query)\u{201D}")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.ink.opacity(0.4))
                        .transition(.opacity)
                } else if query.isEmpty {
                    Text("Your library and Apple Music")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.ink.opacity(0.3))
                        .transition(.opacity)
                }
            }
            .animation(Motion.quick, value: music.isSearching)
        }
        .onChange(of: query) { _, q in music.search(q) }
        .onKeyPress(.escape) { setMode(.expanded); return .handled }
        .task {
            // The panel becomes key in the same runloop turn; focus after it has.
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
    }

    private func play(_ r: SearchResult) {
        music.play(r)
        setMode(.expanded)
    }

    private func open(_ song: CatalogSong) {
        // If it fell back to opening the page, Music comes forward; get out of the way.
        setMode(music.play(song) ? .expanded : .collapsed)
    }
}

private struct SectionHeader: View {
    let title: String
    @Environment(\.palette) private var palette
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.ink.opacity(0.4))
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 3)
    }
}

private struct ResultRow: View {
    let title: String
    let artist: String
    let art: URL?
    let trailing: String
    let index: Int
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                thumbnail
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.ink)
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.ink.opacity(0.5))
                }
                .lineLimit(1)
                Spacer()
                Image(systemName: trailing)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.ink.opacity(hovering ? 0.85 : 0))
                    .offset(x: hovering ? 0 : -4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.ink.opacity(hovering ? 0.09 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
        // Micro cascade, capped so a long list never takes more than ~200 ms.
        .entrance(min(index, 5))
    }

    @ViewBuilder private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        if let art {
            AsyncImage(url: art, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    palette.ink.opacity(0.08)
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(shape)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 12))
                .foregroundStyle(palette.ink.opacity(0.45))
                .frame(width: 30, height: 30)
                .background(shape.fill(palette.ink.opacity(0.08)))
        }
    }
}

// MARK: - Context menu

private struct AppMenu: View {
    @Binding var darkPanel: Bool
    @Binding var albumGlow: Bool

    var body: some View {
        Toggle("Dark Panel", isOn: $darkPanel)
        Toggle("Glow in Album Color", isOn: $albumGlow)
        Button(SMAppService.mainApp.status == .enabled ? "✓ Launch at Login" : "Launch at Login") {
            let service = SMAppService.mainApp
            do {
                if service.status == .enabled { try service.unregister() } else { try service.register() }
            } catch {
                NSLog("NotchMusic: login item error: \(error)")
            }
        }
        Divider()
        Button("Quit NotchMusic") { NSApp.terminate(nil) }
    }
}
