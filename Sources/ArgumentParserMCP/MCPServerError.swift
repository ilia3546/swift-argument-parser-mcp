import Foundation

/// Errors thrown by ``MCPServer``.
public enum MCPServerError: Error, CustomStringConvertible {

    /// The `--experimental-dump-help` invocation exited with a non-zero status code.
    ///
    /// - Parameters:
    ///   - stderr: The standard error output captured from the failed invocation.
    ///   - exitCode: The process exit code.
    case dumpHelpFailed(stderr: String, exitCode: Int32)

    /// The output of `--experimental-dump-help` could not be decoded as the expected JSON structure.
    case invalidDumpHelpOutput

    /// The command with the given name was not found in the CLI's command tree.
    ///
    /// - Parameter name: The command name that was looked up and not found.
    case commandNotFound(String)

    /// The path of the running executable could not be determined.
    ///
    /// On Darwin this is obtained via `_NSGetExecutablePath`; on Linux via `readlink /proc/self/exe`.
    case unableToDetectCurrentExecutablePath

    public var description: String {
        switch self {
        case .dumpHelpFailed(let stderr, let exitCode):
            Self.dumpHelpFailureDescription(stderr: stderr, exitCode: exitCode)

        case .invalidDumpHelpOutput:
            "Could not decode --experimental-dump-help output"

        case .commandNotFound(let name):
            "Command '\(name)' not found in CLI tool structure"

        case .unableToDetectCurrentExecutablePath:
            "Unable to detect current executable path"
        }
    }

    // The actionable diagnostic from a failing CLI is almost always at the
    // tail of stderr, so when the captured stream is long the leading bytes
    // are dropped from `description`. The full stderr is still available on
    // the case's associated value.
    static let maxStderrCharactersInDescription = 4_000

    private static func dumpHelpFailureDescription(stderr: String, exitCode: Int32) -> String {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Failed to dump help (exit code \(exitCode)) — stderr was empty"
        }

        let totalCount = trimmed.count
        let truncated = totalCount > maxStderrCharactersInDescription
        let body: String
        let header: String
        if truncated {
            let omitted = totalCount - maxStderrCharactersInDescription
            let tail = String(trimmed.suffix(maxStderrCharactersInDescription))
            body = "[… \(omitted) earlier characters truncated]\n\(tail)"
            header = "stderr (\(totalCount) chars total, last \(maxStderrCharactersInDescription) shown):"
        } else {
            body = trimmed
            header = "stderr (\(totalCount) chars):"
        }

        let indented = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")

        return "Failed to dump help (exit code \(exitCode))\n\(header)\n\(indented)"
    }
}
