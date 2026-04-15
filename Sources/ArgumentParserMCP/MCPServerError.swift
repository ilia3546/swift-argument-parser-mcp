import Foundation

public enum MCPServerError: Error, CustomStringConvertible {

    case dumpHelpFailed(stderr: String, exitCode: Int32)
    case invalidDumpHelpOutput
    case commandNotFound(String)
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
