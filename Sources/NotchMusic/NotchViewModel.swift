import AppKit
import SwiftUI

enum NotchMode: Equatable {
    /// `peek`: a brief, non-interactive widening that announces a new song.
    /// `prompterEdit`: writing the script; `prompter`: reading strip under the camera.
    case collapsed, peek, expanded, search, prompterEdit, prompter
}

/// UI state only. Knows the hardware notch size and derives the shape's
/// size for each mode, which the window controller also uses for hit-testing.
@MainActor
final class NotchViewModel: ObservableObject {
    @Published var mode: NotchMode = .collapsed
    @Published var notchSize: CGSize

    /// The concave "flare" where the shape meets the top of the screen.
    static let topFlare: CGFloat = 8

    init(notchSize: CGSize) {
        self.notchSize = notchSize
    }

    /// Body size of the black shape (excluding the top flares).
    func bodySize(hasTrack: Bool) -> CGSize {
        bodySize(for: mode, hasTrack: hasTrack)
    }

    func bodySize(for mode: NotchMode, hasTrack: Bool) -> CGSize {
        switch mode {
        case .collapsed:
            return hasTrack
                ? CGSize(width: notchSize.width + 2 * (notchSize.height + 10), height: notchSize.height)
                : notchSize
        case .peek:
            return CGSize(width: max(notchSize.width + 2 * (notchSize.height + 10) + 70, 330),
                          height: notchSize.height + 42)
        case .expanded:
            return CGSize(width: max(notchSize.width + 300, 500), height: notchSize.height + 160)
        case .search, .prompterEdit:
            return CGSize(width: max(notchSize.width + 300, 500), height: notchSize.height + 320)
        case .prompter:
            return CGSize(width: max(notchSize.width + 300, 500), height: notchSize.height + 240)
        }
    }

    var bottomRadius: CGFloat {
        switch mode {
        case .collapsed: 10
        case .peek: 18
        case .expanded, .search, .prompterEdit: 26
        case .prompter: 22
        }
    }

    /// Largest the shape can get; the window is sized to fit this plus shadow room.
    var maxBodySize: CGSize {
        CGSize(width: max(notchSize.width + 300, 500), height: notchSize.height + 320)
    }
}
