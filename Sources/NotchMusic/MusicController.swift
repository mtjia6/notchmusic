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
    @Published private(set) var isSearching = false

    // Playback position is stored as an anchor plus the time it was sampled.
    // The UI extrapolates from it every frame instead of polling Music.
    private var positionAnchor: Double = 0
    private var anchorDate = Date()

    private let runner = AppleScriptRunner()
    private var refreshGeneration = 0
    private var artworkTrackID: String?
    private var searchTask: Task<Void, Never>?
    private var resyncTimer: Timer?

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
        guard isMusicRunning else { clear(); return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let requestedAt = Date()
        Task {
            guard let d = await runner.run(Self.stateScript) else { return }
            // A newer refresh was issued while this one was in flight; drop it.
            guard generation == self.refreshGeneration else { return }
            self.apply(d, sampledAt: requestedAt)
        }
    }

    private func apply(_ d: NSAppleEventDescriptor, sampledAt: Date) {
        let state = d.atIndex(1)?.stringValue ?? "stopped"
        guard d.numberOfItems >= 7 else {
            clear()
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
        let playing = state == "playing"
        if playing != isPlaying { isPlaying = playing }
        positionAnchor = d.atIndex(6)?.doubleValue ?? 0
        anchorDate = sampledAt

        if newTrack.id != artworkTrackID {
            artworkTrackID = newTrack.id
            loadArtwork(for: newTrack.id)
        }
    }

    private func clear() {
        refreshGeneration += 1
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
            guard id == self.artworkTrackID else { return }
            let image = d.flatMap { NSImage(data: $0.data) }
            let color = await Task.detached(priority: .userInitiated) {
                image.map(ArtworkColor.accent(for:)) ?? .white
            }.value
            guard id == self.artworkTrackID else { return }
            self.artwork = image
            self.accent = color
        }
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

    // MARK: - Search (library only)

    func search(_ query: String) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            // Debounce keystrokes.
            try? await Task.sleep(for: .milliseconds(220))
            if Task.isCancelled { return }
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
            let d = await runner.run(source, cache: false)
            if Task.isCancelled { return }
            var results: [SearchResult] = []
            if let d, d.numberOfItems > 0 {
                for i in 1...d.numberOfItems {
                    guard let row = d.atIndex(i), row.numberOfItems >= 3 else { continue }
                    results.append(SearchResult(
                        id: row.atIndex(1)?.stringValue ?? "",
                        title: row.atIndex(2)?.stringValue ?? "",
                        artist: row.atIndex(3)?.stringValue ?? ""
                    ))
                }
            }
            self.searchResults = results
            self.isSearching = false
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchResults = []
        isSearching = false
    }
}
