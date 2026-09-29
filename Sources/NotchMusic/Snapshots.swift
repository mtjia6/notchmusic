import AppKit
import SwiftUI

/// `NotchMusic --snapshot <dir>` renders every state to PNGs with sample data
/// and exits. Lets the design be reviewed without screen-recording access.
@MainActor
enum Snapshots {
    static func render(to dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cover = await firstCatalogCover("duffel bag joeboy")
        let music = MusicController()
        let track = Track(id: "demo", title: "Duffel Bag", artist: "Joeboy",
                          album: "Body & Soul", duration: 176)
        let notch = CGSize(width: 185, height: 32)
        let prompter = PrompterModel()
        prompter.script = "Hey everyone, thanks for joining. Today I want to walk you through what we built this week, why it matters, and what comes next.\n\nFirst, the notch player."

        let library = [SearchResult(id: "1", title: "Raindance", artist: "Dave & Tems"),
                       SearchResult(id: "2", title: "Sprinter", artist: "Dave & Central Cee")]
        let catalog = ((try? await CatalogSearch.songs(matching: "dave")) ?? []).prefix(5)

        let savedDark = UserDefaults.standard.bool(forKey: "darkPanel")
        defer { UserDefaults.standard.set(savedDark, forKey: "darkPanel") }
        for (name, mode, dark) in [("1-collapsed", NotchMode.collapsed, false), ("2-peek", .peek, false),
                                   ("3-expanded", .expanded, false), ("4-search", .search, false),
                                   ("5-expanded-dark", .expanded, true),
                                   ("6-prompter-edit", .prompterEdit, false), ("7-prompter", .prompter, false)] {
            UserDefaults.standard.set(dark, forKey: "darkPanel")
            music.debugSetState(track: track, artwork: cover, playing: true, position: 71,
                                library: library, catalog: Array(catalog))
            let vm = NotchViewModel(notchSize: notch)
            vm.mode = mode
            let view = NotchRootView(vm: vm, music: music, prompter: prompter, setMode: { _ in })
                .environment(\.isSnapshot, true)
                .frame(width: 600, height: notch.height + 360)
                .background(Color(white: 0.55))   // stand-in desktop, so the black shape is visible
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
    }

    private static func firstCatalogCover(_ q: String) async -> NSImage? {
        guard let song = try? await CatalogSearch.songs(matching: q).first, let u = song.largeArtworkURL,
              let (d, _) = try? await URLSession.shared.data(from: u) else { return nil }
        return NSImage(data: d)
    }
}
