import ServiceManagement
import SwiftUI

struct NotchRootView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var music: MusicController
    let setMode: (NotchMode) -> Void

    private let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)

    var body: some View {
        let hasTrack = music.track != nil
        let size = vm.bodySize(hasTrack: hasTrack)
        let flare = NotchViewModel.topFlare
        let shape = NotchShape(topRadius: flare, bottomRadius: vm.bottomRadius)

        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(vm.mode == .collapsed ? 0 : 0.55), radius: 18, y: 8)

            // Each mode's content is laid out at its *final* size and revealed
            // by the animating clip, so text never re-wraps mid-animation.
            ZStack(alignment: .top) {
                switch vm.mode {
                case .collapsed:
                    CollapsedContent(music: music, notchSize: vm.notchSize)
                        .frame(size: vm.bodySize(for: .collapsed, hasTrack: hasTrack))
                        .transition(.opacity.animation(.easeOut(duration: 0.2)))
                case .expanded:
                    ExpandedContent(music: music, notchHeight: vm.notchSize.height, setMode: setMode)
                        .frame(size: vm.bodySize(for: .expanded, hasTrack: hasTrack))
                        .transition(reveal)
                case .search:
                    SearchContent(music: music, notchHeight: vm.notchSize.height, setMode: setMode)
                        .frame(size: vm.bodySize(for: .search, hasTrack: hasTrack))
                        .transition(reveal)
                }
            }
            .frame(width: size.width + 2 * flare, height: size.height, alignment: .top)
            .clipShape(shape)
        }
        .frame(width: size.width + 2 * flare, height: size.height)
        .contextMenu { AppMenu() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(spring, value: hasTrack)
        .animation(spring, value: vm.mode)
        .environment(\.colorScheme, .dark)
    }

    private var reveal: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
                .combined(with: .offset(y: -6))
                .animation(.spring(response: 0.4, dampingFraction: 0.85).delay(0.05)),
            removal: .opacity.animation(.easeIn(duration: 0.12))
        )
    }
}

private extension View {
    func frame(size: CGSize) -> some View { frame(width: size.width, height: size.height) }
}

// MARK: - Collapsed

private struct CollapsedContent: View {
    @ObservedObject var music: MusicController
    let notchSize: CGSize

    var body: some View {
        if music.track != nil {
            let wing = notchSize.height + 10
            HStack(spacing: 0) {
                ArtworkView(image: music.artwork, size: notchSize.height - 12, radius: 5)
                    .frame(width: wing)
                Spacer(minLength: notchSize.width)
                EqualizerBars(isPlaying: music.isPlaying, color: Color(nsColor: music.accent),
                              barWidth: 2.5, maxHeight: notchSize.height * 0.4)
                    .frame(width: wing)
            }
            .padding(.horizontal, NotchViewModel.topFlare)
        }
    }
}

// MARK: - Expanded

private struct ExpandedContent: View {
    @ObservedObject var music: MusicController
    let notchHeight: CGFloat
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

            if let track = music.track {
                HStack(spacing: 14) {
                    ArtworkView(image: music.artwork, size: 62, radius: 12)
                        .shadow(color: accent.opacity(0.35), radius: 12, y: 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(track.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .lineLimit(1)
                    .id(track.id)
                    .transition(.opacity.combined(with: .offset(y: 4)))
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        NotchButton(systemName: "backward.fill", size: 15) { music.previous() }
                        NotchButton(systemName: music.isPlaying ? "pause.fill" : "play.fill", size: 22, hit: 40) {
                            music.playPause()
                        }
                        NotchButton(systemName: "forward.fill", size: 15) { music.next() }
                    }
                }
                .animation(.easeOut(duration: 0.25), value: track.id)
                .padding(.horizontal, 26)
                .padding(.top, 6)

                ProgressBar(music: music, accent: accent)
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
            } else {
                HStack(spacing: 14) {
                    ArtworkView(image: nil, size: 62, radius: 12)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nothing playing")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Search your library or open Music")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Button("Open Music") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app"))
                    }
                    .buttonStyle(PillStyle())
                }
                .padding(.horizontal, 26)
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
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
        VStack(spacing: 0) {
            HStack {
                Text("Search")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                NotchButton(systemName: "xmark", size: 11, hit: 24) { setMode(.expanded) }
            }
            .frame(height: notchHeight)
            .padding(.horizontal, 26)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Songs, artists, albums", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .focused($focused)
                    .onSubmit {
                        if let first = music.searchResults.first { play(first) }
                        else if let first = music.catalogResults.first { open(first) }
                    }
                if music.isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.09)))
            .padding(.horizontal, 20)
            .padding(.top, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !music.searchResults.isEmpty {
                        SectionHeader(title: "In your library")
                        ForEach(music.searchResults) { r in
                            ResultRow(title: r.title, artist: r.artist, art: nil, trailing: "play.fill") { play(r) }
                        }
                    }
                    if !music.catalogResults.isEmpty {
                        HStack {
                            SectionHeader(title: "Apple Music")
                            Spacer()
                            if !music.canPlayCatalog {
                                Button("Enable one-click play") { ShortcutRunner.install() }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color(nsColor: music.accent))
                                    .padding(.top, 10)
                                    .padding(.horizontal, 10)
                            }
                        }
                        ForEach(music.catalogResults) { song in
                            ResultRow(title: song.title, artist: song.artist, art: song.artworkURL,
                                      trailing: music.canPlayCatalog ? "play.fill" : "arrow.up.forward") { open(song) }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            .overlay {
                if music.searchResults.isEmpty && music.catalogResults.isEmpty
                    && !music.isSearching && !query.isEmpty {
                    Text("No matches")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
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
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}

private struct ResultRow: View {
    let title: String
    let artist: String
    let art: URL?
    let trailing: String
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
                    .foregroundStyle(.white.opacity(hovering ? 0.8 : 0))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(hovering ? 0.09 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
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
