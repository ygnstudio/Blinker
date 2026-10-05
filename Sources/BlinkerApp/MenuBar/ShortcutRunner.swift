import Foundation

/// Runs a user-named Shortcut through the CLI. Blinker has no idea what a
/// shortcut does; the panel only learns success or a user-facing failure.
struct ShortcutRunner: Sendable {
    enum Failure: Error, Equatable {
        /// No shortcut with that name exists in the Shortcuts app.
        case notFound
        /// The shortcut did not finish within the timeout.
        case timedOut
        /// Non-zero exit; carries trimmed stderr for display.
        case failed(String)
    }

    private let timeout: TimeInterval

    init(timeout: TimeInterval = 60) {
        self.timeout = timeout
    }

    /// Completion always fires on the main queue.
    func run(_ name: String, completion: @escaping @Sendable (Result<Void, Failure>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.runSync(name)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func runSync(_ name: String) -> Result<Void, Failure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        do {
            try process.run()
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return .failure(.timedOut)
        }
        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        return Self.classify(status: process.terminationStatus,
                             stderr: String(bytes: data, encoding: .utf8) ?? "")
    }

    /// Pure for tests: the CLI reports a missing shortcut on stderr.
    static func classify(status: Int32, stderr: String) -> Result<Void, Failure> {
        guard status != 0 else { return .success(()) }
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.localizedCaseInsensitiveContains("not found") {
            return .failure(.notFound)
        }
        return .failure(.failed(message.isEmpty ? "exit \(status)" : message))
    }
}
