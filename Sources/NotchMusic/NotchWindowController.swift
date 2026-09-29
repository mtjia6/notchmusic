import AppKit
import Combine
import SwiftUI

/// Borderless panel that floats above the menu bar. `canBecomeKey` is needed so
/// the search field can take keyboard input; `.nonactivatingPanel` means that
/// doing so does not steal activation from the app you were using.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchWindowController {
    private let panel: NotchPanel
    private let vm: NotchViewModel
    private let music: MusicController
    private var screen: NSScreen
    private var monitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()
    private var pendingModeChange: DispatchWorkItem?
    private var peekEnd: DispatchWorkItem?

    /// Extra room around the largest shape for its drop shadow.
    private let shadowPad: CGFloat = 40

    init(music: MusicController) {
        self.music = music
        let screen = Self.pickScreen()
        self.screen = screen
        self.vm = NotchViewModel(notchSize: Self.notchSize(of: screen))

        panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar + 8   // above the menu bar and its extras
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true

        let root = NotchRootView(vm: vm, music: music) { [weak self] mode in
            self?.setMode(mode)
        }
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host

        layout()
        panel.orderFrontRegardless()

        installMonitors()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screenChanged() }
        }

        // Announce song changes with a peek. Keyed on title+artist, so the
        // optimistic catalog track being replaced by Music's real one (same
        // song, different ID) does not peek twice.
        music.$track
            .map { $0.map { SearchKey.make($0.title, $0.artist) } }
            .removeDuplicates()
            .sink { [weak self] key in
                guard key != nil else { return }
                DispatchQueue.main.async { self?.peek() }
            }
            .store(in: &cancellables)

        vm.$mode
            .removeDuplicates()
            .sink { [weak self] mode in self?.music.setLiveResync(mode != .collapsed) }
            .store(in: &cancellables)
    }

    // MARK: - Geometry

    /// Prefer the built-in display with a notch; otherwise the main screen.
    private static func pickScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// On notched Macs the menu bar is split by the camera housing: the two
    /// "auxiliary" areas are the usable strips on either side, so the notch is
    /// whatever width is left between them.
    private static func notchSize(of screen: NSScreen) -> CGSize {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0 {
            let width = screen.frame.width - left.width - right.width
            return CGSize(width: width, height: screen.safeAreaInsets.top)
        }
        // No notch: draw a notch-sized pill in the menu bar.
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return CGSize(width: 190, height: max(menuBar, 24))
    }

    private var notchCenterX: CGFloat {
        if let left = screen.auxiliaryTopLeftArea, screen.safeAreaInsets.top > 0 {
            return left.maxX + vm.notchSize.width / 2
        }
        return screen.frame.midX
    }

    private func layout() {
        let body = vm.maxBodySize
        let width = body.width + 2 * NotchViewModel.topFlare + 2 * shadowPad
        let height = body.height + shadowPad
        let frame = NSRect(
            x: notchCenterX - width / 2,
            y: screen.frame.maxY - height,
            width: width, height: height
        )
        panel.setFrame(frame, display: true)
    }

    private func screenChanged() {
        screen = Self.pickScreen()
        vm.notchSize = Self.notchSize(of: screen)
        layout()
    }

    /// Screen-space rect of the black shape in its current mode.
    private func shapeRect(margin: CGFloat = 0) -> NSRect {
        let body = vm.bodySize(hasTrack: music.track != nil)
        let w = body.width + 2 * NotchViewModel.topFlare
        return NSRect(
            x: notchCenterX - w / 2 - margin,
            y: screen.frame.maxY - body.height - margin,
            width: w + 2 * margin,
            height: body.height + margin
        )
    }

    // MARK: - Hover & clicks

    private func installMonitors() {
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        // Global monitors see events headed to other apps; local ones see ours.
        // Mouse (unlike keyboard) global monitors need no Accessibility permission.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moveMask, handler: { [weak self] _ in
            Task { @MainActor in self?.mouseMoved() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: moveMask, handler: { [weak self] e in
            Task { @MainActor in self?.mouseMoved() }
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            // A click anywhere outside our panel dismisses it.
            Task { @MainActor in self?.setMode(.collapsed) }
        }) { monitors.append(m) }
    }

    private func mouseMoved() {
        let p = NSEvent.mouseLocation
        // Generous margin while collapsed so the tiny notch is easy to hit;
        // a little slack while expanded so grazing the edge doesn't close it.
        let collapsedLike = vm.mode == .collapsed || vm.mode == .peek
        let inside = shapeRect(margin: collapsedLike ? 6 : 12).contains(p)
        panel.ignoresMouseEvents = !inside

        switch (vm.mode, inside) {
        case (.collapsed, true), (.peek, true):
            schedule(.expanded, after: 0.06)
        case (.collapsed, false), (.peek, false):
            cancelPending()
        case (.expanded, false):
            schedule(.collapsed, after: 0.28)
        case (.expanded, true), (.search, true):
            cancelPending()
        case (.search, false):
            break // search stays open until Esc or an outside click
        }
    }

    private func schedule(_ mode: NotchMode, after delay: TimeInterval) {
        guard pendingModeChange == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingModeChange = nil
            self?.setMode(mode)
        }
        pendingModeChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPending() {
        pendingModeChange?.cancel()
        pendingModeChange = nil
    }

    private func peek() {
        guard vm.mode == .collapsed else { return }
        setMode(.peek)
        peekEnd?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.vm.mode == .peek else { return }
            self.setMode(.collapsed)
        }
        peekEnd = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: work)
    }

    func setMode(_ mode: NotchMode) {
        cancelPending()
        guard vm.mode != mode else { return }
        if mode == .expanded && (vm.mode == .collapsed || vm.mode == .peek) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        withAnimation(Motion.morph) {
            vm.mode = mode
        }
        if mode == .search {
            panel.makeKey()
        } else {
            music.clearSearch()
        }
        if mode == .collapsed || mode == .peek {
            panel.ignoresMouseEvents = !shapeRect(margin: 6).contains(NSEvent.mouseLocation)
        }
    }
}
