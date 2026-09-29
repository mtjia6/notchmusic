import AppKit

/// Plays Apple Music catalog songs through a Shortcut.
///
/// Music's AppleScript dictionary can only play tracks already in the library,
/// but the Shortcuts "Play Music" action accepts a catalog link. The bundled
/// "NotchPlay Link" shortcut is just that one action wired to its input, and
/// we drive it with the `shortcuts` CLI.
enum ShortcutRunner {
    static let playShortcutName = "NotchPlay Link"

    /// Whether the user has imported the shortcut. Runs the CLI, so call off main.
    static func isInstalled() async -> Bool {
        let output = await run(["list"])
        return output?.status == 0
            && output!.stdout.split(separator: "\n").contains { $0 == playShortcutName }
    }

    /// Returns true if the shortcut ran successfully.
    static func play(link: URL) async -> Bool {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchmusic-\(UUID().uuidString).txt")
        do {
            try link.absoluteString.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        defer { try? FileManager.default.removeItem(at: file) }
        let output = await run(["run", playShortcutName, "-i", file.path])
        return output?.status == 0
    }

    /// Opens the bundled shortcut so Shortcuts shows its "Add Shortcut" sheet.
    static func install() {
        guard let url = Bundle.main.url(forResource: playShortcutName, withExtension: "shortcut") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func run(_ args: [String]) async -> (status: Int32, stdout: String)? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = args
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                // Drain stdout before waiting: a full pipe would block the child forever.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: (process.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
        }
    }
}
