import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var music: MusicController!
    private var controller: NotchWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        music = MusicController()
        controller = NotchWindowController(music: music)
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    Task { @MainActor in
        await Snapshots.render(to: dir)
        exit(0)
    }
    RunLoop.main.run()
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar
app.run()
