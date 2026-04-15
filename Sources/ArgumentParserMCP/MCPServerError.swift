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
            "Failed to dump help (exit code \(exitCode)): \(stderr)"

        case .invalidDumpHelpOutput:
            "Could not decode --experimental-dump-help output"

        case .commandNotFound(let name):
            "Command '\(name)' not found in CLI tool structure"

        case .unableToDetectCurrentExecutablePath:
            "Unable to detect current executable path"
        }
    }
}
