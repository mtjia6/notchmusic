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

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar
app.run()
