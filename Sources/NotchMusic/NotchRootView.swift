import ServiceManagement
import SwiftUI

struct NotchRootView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var music: MusicController
    let setMode: (NotchMode) -> Void

    /// Shared-element space: the small cover in the notch and the big cover
    /// in the panel are the same element, so it travels between the two.
    @Namespace private var ns

    var body: some View {
        let hasTrack = music.track != nil
        let size = vm.bodySize(hasTrack: hasTrack)
        let flare = NotchViewModel.topFlare
        let shape = NotchShape(topRadius: flare, bottomRadius: vm.bottomRadius)
        let open = vm.mode == .expanded || vm.mode == .search

        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(open ? 0.55 : vm.mode == .peek ? 0.3 : 0), radius: 18, y: 8)

            ZStack(alignment: .top) {
                if open {
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
            }
            .frame(width: size.width + 2 * flare, height: size.height, alignment: .top)
            .clipShape(shape)

            // A hairline catching light along the lower edge: the panel reads as
            // a physical slab rather than a flat cut-out.
            shape
                .stroke(LinearGradient(colors: [.clear, .white.opacity(open ? 0.1 : 0)],
                                       startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .frame(width: size.width + 2 * flare, height: size.height)
        .contextMenu { AppMenu() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Motion.morph, value: hasTrack)
        .animation(Motion.morph, value: vm.mode)
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

    var body: some View {
        let accent = Color(nsColor: music.accent)
        VStack(spacing: 0) {
            // Strip beside the camera housing: nothing may sit in the middle.
            HStack {
                EqualizerBars(isPlaying: music.isPlaying, color: accent, barWidth: 2.5, maxHeight: 11)
                    .opacity(music.track == nil ? 0 : 1)
                Spacer()
                NotchButton(systemName: "magnifyingglass", size: 12, hit: 24) { setMode(.search) }
            }
            .frame(height: notchHeight)
            .padding(.horizontal, 26)
            .entrance(3)

            if let track = music.track {
                HStack(spacing: 14) {
                    Artwork3DView(image: music.artwork, size: 64, radius: 13, accent: accent,
                                  breathing: music.isLoading)
                        .matchedGeometryEffect(id: "cover", in: ns)
                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(text: track.title, font: .system(size: 15, weight: .semibold), color: .white)
                        Text(track.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    .id(track.id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)),
                                            removal: .opacity.combined(with: .offset(y: -6))))
                    .entrance(0)
                    Spacer(minLength: 8)
                    HStack(spacing: 2) {
                        NotchButton(systemName: "backward.fill", size: 15, nudge: -3) { music.previous() }
                        NotchButton(systemName: music.isPlaying || music.isLoading ? "pause.fill" : "play.fill",
                                    size: 22, hit: 42) { music.playPause() }
                            .opacity(music.isLoading ? 0.45 : 1)
                            .disabled(music.isLoading)
                        NotchButton(systemName: "forward.fill", size: 15, nudge: 3) { music.next() }
                    }
                    .entrance(1)
                }
                .animation(Motion.standard, value: track.id)
                .animation(Motion.quick, value: music.isLoading)
                .padding(.horizontal, 24)
                .padding(.top, 4)

                ProgressBar(music: music, accent: accent)
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .entrance(2)
            } else {
                HStack(spacing: 14) {
                    Artwork3DView(image: nil, size: 64, radius: 13, accent: .white)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nothing playing")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Search for a song or open Music")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .entrance(0)
                    Spacer()
                    Button("Open Music") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app"))
                    }
                    .buttonStyle(PillStyle())
                    .entrance(1)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Search

private struct SearchContent: View {
    @ObservedObject var music: MusicController
    let notchHeight: CGFloat
    let setMode: (NotchMode) -> Void

    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        let accent = Color(nsColor: music.accent)
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
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Songs, artists, albums", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .tint(accent)
                    .focused($focused)
                    .onSubmit {
                        if let first = music.searchResults.first { play(first) }
                        else if let first = music.catalogResults.first { open(first) }
                    }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(focused ? accent.opacity(0.55) : .white.opacity(0.06), lineWidth: 1))
            )
            .animation(Motion.quick, value: focused)
            .animation(Motion.quick, value: query.isEmpty)
            .padding(.horizontal, 20)
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
                        .foregroundStyle(.white.opacity(0.4))
                        .transition(.opacity)
                } else if query.isEmpty {
                    Text("Your library and Apple Music")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.3))
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
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                thumbnail
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .lineLimit(1)
                Spacer()
                Image(systemName: trailing)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(hovering ? 0.85 : 0))
                    .offset(x: hovering ? 0 : -4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(hovering ? 0.09 : 0)))
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
                    Color.white.opacity(0.08)
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(shape)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 30, height: 30)
                .background(shape.fill(.white.opacity(0.08)))
        }
    }
}

// MARK: - Context menu

private struct AppMenu: View {
    var body: some View {
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
