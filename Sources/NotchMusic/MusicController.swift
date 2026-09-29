import AppKit
import Combine

struct Track: Equatable {
    var id: String          // Music's persistent ID (hex string)
    var title: String
    var artist: String
    var album: String
    var duration: Double    // seconds
}

struct SearchResult: Identifiable, Equatable {
    var id: String
    var title: String
    var artist: String

    var matchKey: String { SearchKey.make(title, artist) }
}

/// Owns everything we know about Music.app. All reads/writes go through
/// Apple Events; updates are push-driven by Music's distributed notification.
@MainActor
final class MusicController: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: NSColor = .white
    @Published private(set) var searchResults: [SearchResult] = []
    @Published private(set) var catalogResults: [CatalogSong] = []
    @Published private(set) var isSearching = false
    /// A song was requested and Music is fetching/buffering it. The clock is
    /// held at 0:00 until Music's position actually starts moving.
    @Published private(set) var isLoading = false
    /// Whether the "NotchPlay Link" shortcut is installed (enables one-click catalog play).
    @Published private(set) var canPlayCatalog = false

    // Playback position is stored as an anchor plus the time it was sampled.
    // The UI extrapolates from it every frame instead of polling Music.
    private var positionAnchor: Double = 0
    private var anchorDate = Date()

    private let runner = AppleScriptRunner()
    private var refreshGeneration = 0
    private var artworkTrackID: String?
    private var searchTask: Task<Void, Never>?
    private var resyncTimer: Timer?

    /// Set while a requested song is starting. Catalog songs take ~1.2-1.7 s for
    /// Music to switch and ~1 s more to buffer. Meanwhile we ignore reports about
    /// the *old* track (so the UI doesn't flicker back) and hold the clock at 0
    /// while the new one buffers (so it doesn't tick, then jump back).
    private var pending: (key: String, deadline: Date)?
    /// When Music can't hand us artwork for a catalog track, keep the store's.
    private var optimisticArtKey: String?
    private var artworkCache: [String: NSImage] = [:]

    private nonisolated static let musicBundleID = "com.apple.Music"

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.musicBundleID else { return }
            Task { @MainActor in self?.clear() }
        }
        ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.musicBundleID else { return }
            Task { @MainActor in self?.refresh() }
        }

        refresh()
        checkCatalogShortcut()
    }

    func checkCatalogShortcut() {
        Task {
            let installed = await ShortcutRunner.isInstalled()
            if installed != self.canPlayCatalog { self.canPlayCatalog = installed }
        }
    }

    var isMusicRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.musicBundleID).isEmpty
    }

    func position(at date: Date) -> Double {
        guard let track else { return 0 }
        let p = isPlaying ? positionAnchor + date.timeIntervalSince(anchorDate) : positionAnchor
        return min(max(p, 0), track.duration)
    }

    /// While the panel is expanded, periodically correct drift (e.g. the user
    /// scrubbed inside Music.app, which does not post a notification).
    func setLiveResync(_ on: Bool) {
        resyncTimer?.invalidate()
        resyncTimer = nil
        guard on else { return }
        refresh()
        resyncTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - State

    private static let stateScript = """
    if application "Music" is running then
        tell application "Music"
            set ps to player state as string
            if ps is "stopped" then return {"stopped"}
            try
                set t to current track
                return {ps, name of t, artist of t, album of t, duration of t, player position, persistent ID of t}
            on error
                return {ps}
            end try
        end tell
    else
        return {"notrunning"}
    end if
    """

    func refresh() {
        Task { await refreshNow() }
    }

    /// Awaitable refresh, so pollers can wait for each answer instead of
    /// issuing overlapping requests that would keep superseding each other.
    func refreshNow() async {
        guard isMusicRunning else { clear(); return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let requestedAt = Date()
        guard let d = await runner.run(Self.stateScript) else { return }
        // A newer refresh was issued while this one was in flight; drop it.
        guard generation == refreshGeneration else { return }
        apply(d, sampledAt: requestedAt)
    }

    private func apply(_ d: NSAppleEventDescriptor, sampledAt: Date) {
        let state = d.atIndex(1)?.stringValue ?? "stopped"
        let reportedPosition = d.atIndex(6)?.doubleValue ?? 0
        var buffering = false
        if let pending {
            let key = d.numberOfItems >= 7
                ? SearchKey.make(d.atIndex(2)?.stringValue ?? "", d.atIndex(3)?.stringValue ?? "")
                : nil
            if Date() < pending.deadline {
                if key != pending.key { return }  // still the old track, or mid-switch
                buffering = !(state == "playing" && reportedPosition > 0.05)
            }
            if !buffering { finishLoading() }
        }
        guard d.numberOfItems >= 7 else {
            // Mid-switch, Music briefly reports "playing" with no current track.
            // Only a real stop should blank the notch.
            if state == "stopped" || state == "notrunning" { clear() }
            return
        }
        let newTrack = Track(
            id: d.atIndex(7)?.stringValue ?? "",
            title: d.atIndex(2)?.stringValue ?? "",
            artist: d.atIndex(3)?.stringValue ?? "",
            album: d.atIndex(4)?.stringValue ?? "",
            duration: d.atIndex(5)?.doubleValue ?? 0
        )
        if newTrack != track { track = newTrack }
        let playing = state == "playing" && !buffering
        if playing != isPlaying { isPlaying = playing }
        positionAnchor = buffering ? 0 : reportedPosition
        anchorDate = sampledAt

        if newTrack.id != artworkTrackID {
            artworkTrackID = newTrack.id
            loadArtwork(for: newTrack.id)
        }
    }

    private func clear() {
        refreshGeneration += 1
        finishLoading()
        if track != nil { track = nil }
        if isPlaying { isPlaying = false }
        artwork = nil
        artworkTrackID = nil
        accent = .white
        positionAnchor = 0
    }

    private func loadArtwork(for id: String) {
        Task {
            let d = await runner.run("""
            tell application "Music"
                try
                    return raw data of artwork 1 of current track
                end try
            end tell
            """)
            guard id == self.artworkTrackID, let track = self.track else { return }
            var image = d.flatMap { NSImage(data: $0.data) }

            if image == nil {
                let key = SearchKey.make(track.title, track.artist)
                if key == self.optimisticArtKey { return }  // already showing the store cover
                image = await self.storeArtwork(for: track)
                guard id == self.artworkTrackID else { return }
            }
            let color = await Task.detached(priority: .userInitiated) {
                image.map(ArtworkColor.accent(for:)) ?? .white
            }.value
            guard id == self.artworkTrackID else { return }
            self.artwork = image
            self.accent = color
        }
    }

    /// Streamed tracks have no artwork over AppleScript, so fetch the cover
    /// from the catalog. Cached per song so replays and skips back are instant.
    private func storeArtwork(for track: Track) async -> NSImage? {
        let key = SearchKey.make(track.title, track.artist)
        if let cached = artworkCache[key] { return cached }
        guard let url = await CatalogSearch.artworkURL(title: track.title, artist: track.artist, album: track.album),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data) else { return nil }
        if artworkCache.count > 50 { artworkCache.removeAll() }
        artworkCache[key] = image
        return image
    }

    // MARK: - Controls

    func playPause() {
        // Optimistic: flip immediately so the UI never waits on the round trip.
        positionAnchor = position(at: Date())
        anchorDate = Date()
        isPlaying.toggle()
        send("tell application \"Music\" to playpause")
    }

    func next() { send("tell application \"Music\" to next track") }

    /// `back track` restarts the song if we are a few seconds in, otherwise goes back.
    func previous() { send("tell application \"Music\" to back track") }

    func seek(to seconds: Double) {
        positionAnchor = seconds
        anchorDate = Date()
        objectWillChange.send()
        send("tell application \"Music\" to set player position to \(seconds)", cache: false)
    }

    func play(_ result: SearchResult) {
        beginLoading(key: result.matchKey)
        let id = AppleScriptRunner.escape(result.id)
        send("""
        tell application "Music"
            play (some track of library playlist 1 whose persistent ID is "\(id)")
        end tell
        """, cache: false)
    }

    private func send(_ source: String, cache: Bool = true) {
        guard isMusicRunning || source.contains("play (") else { return }
        Task {
            _ = await runner.run(source, cache: cache)
            self.refresh()
        }
    }

    // MARK: - Search

    /// Searches the library (Apple Events) and the Apple Music catalog (the public
    /// iTunes Search API) in parallel. Library results publish as soon as they
    /// arrive, so a slow network never delays them.
    func search(_ query: String) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            clearSearch()
            return
        }
        isSearching = true
        searchTask = Task {
            // Debounce keystrokes.
            try? await Task.sleep(for: .milliseconds(220))
            if Task.isCancelled { return }

            async let catalog = CatalogSearch.songs(matching: q)
            let library = await searchLibrary(q)
            if Task.isCancelled { return }
            self.searchResults = library

            let songs = (try? await catalog) ?? []
            if Task.isCancelled { return }
            // Songs already in the library are shown (and played) from there.
            let owned = Set(library.map(\.matchKey))
            self.catalogResults = songs.filter { !owned.contains($0.matchKey) }
            self.isSearching = false
        }
    }

    private func searchLibrary(_ q: String) async -> [SearchResult] {
        let source = """
        tell application "Music"
            set res to search library playlist 1 for "\(AppleScriptRunner.escape(q))"
            set out to {}
            set n to count of res
            if n > 30 then set n to 30
            repeat with i from 1 to n
                set t to item i of res
                set end of out to {persistent ID of t, name of t, artist of t}
            end repeat
            return out
        end tell
        """
        guard let d = await runner.run(source, cache: false), d.numberOfItems > 0 else { return [] }
        var results: [SearchResult] = []
        for i in 1...d.numberOfItems {
            guard let row = d.atIndex(i), row.numberOfItems >= 3 else { continue }
            results.append(SearchResult(
                id: row.atIndex(1)?.stringValue ?? "",
                title: row.atIndex(2)?.stringValue ?? "",
                artist: row.atIndex(3)?.stringValue ?? ""
            ))
        }
        return results
    }

    /// Plays a catalog song via the Shortcut if it's installed; otherwise opens
    /// its page in Music (AppleScript alone can't play non-library tracks).
    /// Returns false when it fell back to opening the page.
    @discardableResult
    func play(_ song: CatalogSong) -> Bool {
        guard canPlayCatalog else {
            NSWorkspace.shared.open(song.musicAppURL)
            checkCatalogShortcut()
            return false
        }

        // Stop the old song right away so the click feels answered.
        if isPlaying, let old = track, !old.id.hasPrefix("catalog-") {
            fadeOutAndPause(ifStillPlaying: old.id)
        }

        // Show the song immediately; Music confirms it a second or two later.
        let key = song.matchKey
        beginLoading(key: key)
        refreshGeneration += 1  // drop any in-flight refresh about the old track
        track = Track(id: "catalog-\(song.id)", title: song.title, artist: song.artist,
                      album: "", duration: song.duration)
        artworkTrackID = track?.id
        artwork = nil  // never pair the new title with the old cover
        isPlaying = false
        positionAnchor = 0
        anchorDate = Date()
        loadStoreArtwork(song, key: key)

        Task {
            let ok = await ShortcutRunner.play(link: song.pageURL)
            if !ok {
                NSLog("NotchMusic: shortcut failed; opening the song page instead")
                self.finishLoading()
                NSWorkspace.shared.open(song.musicAppURL)
                self.checkCatalogShortcut()
            }
            self.refresh()
        }
        return true
    }

    // MARK: - Loading

    private func beginLoading(key: String) {
        let deadline = Date().addingTimeInterval(10)
        pending = (key, deadline)
        isLoading = true
        // Music posts no notification when buffered audio starts, so poll
        // briefly (each probe is one cheap Apple Event) until it does.
        Task {
            while let p = self.pending, p.deadline == deadline, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(120))
                await self.refreshNow()
            }
            if let p = self.pending, p.deadline == deadline {
                self.finishLoading()  // gave up waiting; show whatever Music says
                self.refresh()
            }
        }
    }

    private func finishLoading() {
        pending = nil
        if isLoading { isLoading = false }
    }

    /// Quick volume ramp then pause, only if the old track is still current
    /// (so it can never pause the *new* song if Music was unusually fast).
    /// Volume is restored after the pause, while silent.
    private func fadeOutAndPause(ifStillPlaying oldID: String) {
        let id = AppleScriptRunner.escape(oldID)
        Task {
            _ = await runner.run("""
            tell application "Music"
                if player state is not playing then return
                set v to sound volume
                try
                    repeat with i from 1 to 4
                        if persistent ID of current track is not "\(id)" then exit repeat
                        set sound volume to (v * (4 - i) / 4) as integer
                        delay 0.035
                    end repeat
                    if persistent ID of current track is "\(id)" then pause
                end try
                set sound volume to v
            end tell
            """, cache: false)
        }
    }

    private func loadStoreArtwork(_ song: CatalogSong, key: String) {
        guard let url = song.largeArtworkURL else { return }
        let trackID = track?.id
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            self.artworkCache[key] = image
            let color = await Task.detached(priority: .userInitiated) { ArtworkColor.accent(for: image) }.value
            // Still showing this song (optimistically or for real)?
            guard let track = self.track, SearchKey.make(track.title, track.artist) == key
                    || track.id == trackID else { return }
            if self.artwork == nil || track.id == trackID {
                self.artwork = image
                self.accent = color
            }
            self.optimisticArtKey = key
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchResults = []
        catalogResults = []
        isSearching = false
    }
}
