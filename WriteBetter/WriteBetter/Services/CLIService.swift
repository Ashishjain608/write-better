import Foundation

/// Runs a rewrite through a locally installed, signed-in agent CLI (`claude` or `codex`),
/// so it is billed to that CLI's subscription instead of an API key.
///
/// Each request is one non-interactive run in a fresh temp directory: tools off, no
/// session saved. The prompt goes in on stdin, the answer comes back on stdout in one
/// piece (no token streaming), stderr is kept only to explain a failure.
nonisolated struct CLIService: AIService {
    let provider: AIProvider
    let modelID: String
    let effort: String

    /// Effort levels both CLIs accept (`claude --effort`, codex `model_reasoning_effort`).
    static let efforts = ["low", "medium", "high", "xhigh", "max"]
    /// A rewrite is an easy task and the user is waiting on a hotkey: fast by default.
    static let defaultEffort = "low"

    // MARK: Locating the binary

    static func binaryName(for provider: AIProvider) -> String {
        provider == .codex ? "codex" : "claude"
    }

    /// The CLI's absolute path, or `nil` when it isn't installed.
    ///
    /// An app opened from Finder gets a bare PATH, so the usual install locations are
    /// checked as well.
    // ponytail: fixed dir list, misses nvm/asdf installs; resolve via a login shell if that bites.
    static func executable(for provider: AIProvider) -> URL? {
        let home = NSHomeDirectory()
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let dirs = path + ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin",
                           "\(home)/.claude/local", "\(home)/.npm-global/bin", "\(home)/.bun/bin",
                           "\(home)/.volta/bin"]
        let name = binaryName(for: provider)
        return dirs.lazy
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    // MARK: Arguments

    /// Command-line arguments for one rewrite. The prompt itself goes on stdin.
    func arguments(for improvement: ImprovementRequest) -> [String] {
        switch provider {
        case .codex:
            // codex exec has no system-prompt flag; the rules lead the stdin prompt instead.
            return ["exec", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only",
                    "--color", "never", "--model", modelID,
                    "-c", "model_reasoning_effort=\"\(effort)\"", "-"]
        default:
            // --safe-mode skips the user's hooks, plugins and CLAUDE.md but keeps the
            // subscription login (--bare would demand an API key).
            return ["-p", "--safe-mode", "--tools", "", "--no-session-persistence",
                    "--output-format", "text", "--model", modelID, "--effort", effort,
                    "--system-prompt", improvement.systemPrompt]
        }
    }

    func stdinPrompt(for improvement: ImprovementRequest) -> String {
        provider == .codex
            ? improvement.systemPrompt + "\n\n" + improvement.userPrompt
            : improvement.userPrompt
    }

    // MARK: AIService

    func improveTextStream(request improvement: ImprovementRequest) -> AsyncThrowingStream<String, Error> {
        let process = Process()
        let cancelled = CancelFlag()
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { _ in cancelled.set(); Self.stop(process) }
            guard !improvement.isEmpty else { continuation.finish(throwing: AIServiceError.emptyInput); return }
            let arguments = arguments(for: improvement)
            let input = stdinPrompt(for: improvement)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let output = try run(process, cancelled: cancelled, arguments: arguments, stdin: input)
                    var text = output
                    while text.hasSuffix("\n") { text.removeLast() }
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw AIServiceError.api("\(provider.shortName) returned no text. Try again, or pick another model.")
                    }
                    continuation.yield(text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// No API key to check: "valid" means the CLI is installed and signed in.
    func validateKey() async -> Result<Void, AIServiceError> {
        let args = provider == .codex ? ["login", "status"] : ["auth", "status"]
        let process = Process()
        return await withCheckedContinuation { done in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    _ = try run(process, arguments: args, stdin: "")
                    done.resume(returning: .success(()))
                } catch let error as AIServiceError {
                    done.resume(returning: .failure(error))
                } catch {
                    done.resume(returning: .failure(.api(error.localizedDescription)))
                }
            }
        }
    }

    // MARK: Process

    /// Runs the CLI to completion and returns stdout. Blocking: call off the main thread.
    ///
    /// stdin and stderr go through files in a throwaway directory (which is also the
    /// working directory), so no pipe can fill up and deadlock.
    private func run(_ process: Process, cancelled: CancelFlag = CancelFlag(), arguments: [String], stdin: String) throws -> String {
        guard let executable = Self.executable(for: provider) else { throw AIServiceError.missingKey(provider) }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("WriteBetter-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let inURL = dir.appendingPathComponent("stdin.txt")
        let errURL = dir.appendingPathComponent("stderr.txt")
        try Data(stdin.utf8).write(to: inURL)
        fm.createFile(atPath: errURL.path, contents: nil)

        var environment = ProcessInfo.processInfo.environment
        // A Node-based install finds `node` next to itself.
        environment["PATH"] = ([executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin",
                                environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        let stdout = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = dir
        process.standardInput = try FileHandle(forReadingFrom: inURL)
        process.standardOutput = stdout
        process.standardError = try FileHandle(forWritingTo: errURL)

        let timeout = DispatchWorkItem { Self.stop(process) }
        DispatchQueue.global().asyncAfter(deadline: .now() + Constants.overallTimeout, execute: timeout)
        defer { timeout.cancel() }

        try process.run()
        // esc can land between stream creation and launch, when stop() found nothing to kill.
        if cancelled.value { Self.stop(process) }
        let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        // Our own terminate(): the timeout fired, or the request was cancelled (and then
        // nobody is listening for this error).
        if process.terminationReason == .uncaughtSignal { throw AIServiceError.timedOut }
        guard process.terminationStatus == 0 else {
            let err = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
            throw AIServiceError.api(Self.failureMessage(stderr: err, stdout: out, provider: provider,
                                                         status: process.terminationStatus))
        }
        return out
    }

    /// SIGTERM now, SIGKILL after 2s if it is still running: a CLI that ignores TERM (or a
    /// grandchild holding stdout open) would otherwise hang the read and leave a zombie
    /// after esc. Safe to call before launch (does nothing) or after exit.
    static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    /// Last meaningful line the CLI printed, which is where both put their error.
    static func failureMessage(stderr: String, stdout: String, provider: AIProvider, status: Int32) -> String {
        let line = (stderr + "\n" + stdout).split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        return line.map { "\(provider.shortName): \($0)" } ?? "\(provider.shortName) exited with code \(status)."
    }
}

/// Set when the consumer goes away, so a run that hasn't launched yet can abort.
nonisolated final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func set() { lock.lock(); flag = true; lock.unlock() }
}
