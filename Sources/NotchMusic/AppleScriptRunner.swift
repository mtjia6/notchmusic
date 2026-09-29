import Foundation

/// Runs AppleScript on one serial background queue.
/// NSAppleScript is not safe to run concurrently, and Apple Events block
/// the calling thread until Music replies, so this must never run on main.
final class AppleScriptRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "NotchMusic.AppleScript", qos: .userInitiated)
    private var compiled: [String: NSAppleScript] = [:]

    /// `cache: true` keeps the compiled script around. Use it for fixed sources
    /// (state, controls), not for sources with user text spliced in (search).
    func run(_ source: String, cache: Bool = true) async -> NSAppleEventDescriptor? {
        await withCheckedContinuation { continuation in
            queue.async {
                let script: NSAppleScript
                if cache, let existing = self.compiled[source] {
                    script = existing
                } else {
                    guard let fresh = NSAppleScript(source: source) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    var compileError: NSDictionary?
                    fresh.compileAndReturnError(&compileError)
                    if let compileError {
                        NSLog("NotchMusic: AppleScript compile error: \(compileError)")
                        continuation.resume(returning: nil)
                        return
                    }
                    if cache { self.compiled[source] = fresh }
                    script = fresh
                }

                var error: NSDictionary?
                let result = script.executeAndReturnError(&error)
                if let error {
                    NSLog("NotchMusic: AppleScript error: \(error)")
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Escapes a Swift string so it can be spliced into an AppleScript string literal.
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
