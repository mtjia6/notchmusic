import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var music: MusicController!
    private var controller: NotchWindowController!
    private var prompter: PrompterModel!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        music = MusicController()
        prompter = PrompterModel()
        controller = NotchWindowController(music: music, prompter: prompter)

        // Menu bar icon, so there's a visible way to quit. New icons go at the
        // left end of the icons, which on a full menu bar is behind the notch;
        // start it near the right instead (points from the screen's right edge).
        // Cmd-dragging it afterwards saves over this default.
        UserDefaults.standard.register(defaults: ["NSStatusItem Preferred Position NotchMusic": 250])
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "NotchMusic"
        statusItem.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "NotchMusic")
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit NotchMusic", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
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
app.setActivationPolicy(.accessory)   // no Dock icon
app.run()
