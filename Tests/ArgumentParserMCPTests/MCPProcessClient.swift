import Foundation

/// Test harness that drives a child `demo-cli mcp` process as a JSON-RPC client
/// over stdio. Used by `MCPServerIntegrationTests` to exercise the full
/// `initialize` → `tools/list` → `tools/call` cycle against the real binary.
final class MCPProcessClient: @unchecked Sendable {

    private let process: Process
    private let stdin: FileHandle
    private let stdout: FileHandle
    private let stderrDrainer: Task<Void, Never>
    private var stdoutBuffer = Data()
    private var nextID: Int = 0

    private init(
        process: Process,
        stdin: FileHandle,
        stdout: FileHandle,
        stderrDrainer: Task<Void, Never>
    ) {
        self.process = process
        self.stdin = stdin
        self.stdout = stdout
        self.stderrDrainer = stderrDrainer
    }

    /// Spawns `demo-cli mcp` and wires up stdin/stdout pipes for JSON-RPC.
    static func launch() throws -> MCPProcessClient {
        let process = Process()
        process.executableURL = try demoCLIURL()
        process.arguments = ["mcp"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Drain stderr so the server doesn't block on a full pipe buffer.
        let stderrHandle = stderrPipe.fileHandleForReading
        let drainer = Task.detached {
            while true {
                guard let chunk = try? stderrHandle.read(upToCount: 4096),
                      !chunk.isEmpty
                else { return }
            }
        }

        return MCPProcessClient(
            process: process,
            stdin: stdinPipe.fileHandleForWriting,
            stdout: stdoutPipe.fileHandleForReading,
            stderrDrainer: drainer
        )
    }

    /// Performs the MCP `initialize` request and `notifications/initialized`
    /// follow-up. Returns the server's `result` object.
    @discardableResult
    func initializeHandshake() async throws -> [String: Any] {
        let response = try await send(
            method: "initialize",
            params: [
                "protocolVersion": "2025-11-25",
                "capabilities": [String: Any](),
                "clientInfo": [
                    "name": "ArgumentParserMCP-integration-tests",
                    "version": "1.0",
                ],
            ]
        )
        let result = try response.requireResult()
        try notify(method: "notifications/initialized")
        return result
    }

    /// Sends a JSON-RPC request and waits for the matching response envelope.
    func send(
        method: String,
        params: Any? = nil,
        timeout: TimeInterval = 15
    ) async throws -> [String: Any] {
        nextID += 1
        let id = nextID
        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
        ]
        if let params {
            message["params"] = params
        }
        try writeMessage(message)
        return try await readMessage(matchingID: id, timeout: timeout)
    }

    /// Sends a JSON-RPC notification (no response expected).
    func notify(method: String, params: Any? = nil) throws {
        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
        ]
        if let params {
            message["params"] = params
        }
        try writeMessage(message)
    }

    func terminate() {
        stderrDrainer.cancel()
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        try? stdin.close()
    }

    // MARK: - I/O

    private func writeMessage(_ message: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: message)
        try stdin.write(contentsOf: data)
        try stdin.write(contentsOf: Data([0x0A]))
    }

    private func readMessage(
        matchingID id: Int,
        timeout: TimeInterval
    ) async throws -> [String: Any] {
        try await withThrowingTaskGroup(of: [String: Any].self) { group in
            group.addTask { [self] in
                while true {
                    let line = try await readLine()
                    if line.isEmpty { continue }
                    guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any]
                    else { continue }
                    if let respID = object["id"] as? Int, respID == id {
                        return object
                    }
                    // Notifications or unrelated IDs are ignored.
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw MCPClientError.timeout(method: "id=\(id)")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func readLine() async throws -> Data {
        while true {
            if let nlIndex = stdoutBuffer.firstIndex(of: 0x0A) {
                let line = Data(stdoutBuffer[stdoutBuffer.startIndex..<nlIndex])
                stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...nlIndex)
                return line
            }
            try Task.checkCancellation()
            let chunk = try await readChunk()
            if chunk.isEmpty {
                throw MCPClientError.endOfStream(
                    isProcessRunning: process.isRunning,
                    exitCode: process.isRunning ? nil : process.terminationStatus
                )
            }
            stdoutBuffer.append(chunk)
        }
    }

    private func readChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async { [stdout] in
                do {
                    let chunk = try stdout.read(upToCount: 4096) ?? Data()
                    continuation.resume(returning: chunk)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Locating the built executable

    private static func demoCLIURL() throws -> URL {
        let directory = productsDirectory
        let url = directory.appendingPathComponent("demo-cli")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPClientError.executableNotFound(url.path)
        }
        return url
    }

    private static var productsDirectory: URL {
#if os(macOS)
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        return Bundle.main.bundleURL.deletingLastPathComponent()
#else
        return Bundle.main.bundleURL
#endif
    }
}

enum MCPClientError: Error, CustomStringConvertible {
    case timeout(method: String)
    case endOfStream(isProcessRunning: Bool, exitCode: Int32?)
    case executableNotFound(String)
    case missingField(String)
    case wrongType(field: String, expected: String)

    var description: String {
        switch self {
        case .timeout(let method):
            return "Timed out waiting for MCP response (\(method))"
        case .endOfStream(let running, let code):
            return "Server closed stdout (running=\(running), exitCode=\(String(describing: code)))"
        case .executableNotFound(let path):
            return "demo-cli executable not found at \(path); make sure `swift build` produced it"
        case .missingField(let key):
            return "Missing field '\(key)' in MCP response"
        case .wrongType(let field, let expected):
            return "Field '\(field)' has wrong type, expected \(expected)"
        }
    }
}

// MARK: - JSON convenience accessors

extension Dictionary where Key == String, Value == Any {

    func requireResult() throws -> [String: Any] {
        try requireObject(at: "result")
    }

    func requireObject(at key: String) throws -> [String: Any] {
        guard let raw = self[key] else {
            throw MCPClientError.missingField(key)
        }
        guard let value = raw as? [String: Any] else {
            throw MCPClientError.wrongType(field: key, expected: "object")
        }
        return value
    }

    func requireArray(at key: String) throws -> [[String: Any]] {
        guard let raw = self[key] else {
            throw MCPClientError.missingField(key)
        }
        guard let value = raw as? [[String: Any]] else {
            throw MCPClientError.wrongType(field: key, expected: "[object]")
        }
        return value
    }

    func requireString(at key: String) throws -> String {
        guard let raw = self[key] else {
            throw MCPClientError.missingField(key)
        }
        guard let value = raw as? String else {
            throw MCPClientError.wrongType(field: key, expected: "string")
        }
        return value
    }

    /// Returns the text of the first `{"type": "text", "text": "..."}` content
    /// block in a `tools/call` result, with surrounding whitespace trimmed.
    func firstTextContent() throws -> String {
        let content = try requireArray(at: "content")
        guard let first = content.first else {
            throw MCPClientError.missingField("content[0]")
        }
        let text = try first.requireString(at: "text")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
