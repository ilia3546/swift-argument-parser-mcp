import Foundation

// MARK: - MCPProcessClient

/// Test harness that drives a child `demo-cli mcp` process as a JSON-RPC client
/// over stdio. Used by `MCPServerIntegrationTests` to exercise the full
/// `initialize` → `tools/list` → `tools/call` cycle against the real binary.
final class MCPProcessClient: @unchecked Sendable {

    // MARK: - Nested Types

    /// Carries a parsed JSON-RPC response across a task-group boundary.
    /// `[String: Any]` is not `Sendable` under Swift 6 strict concurrency,
    /// so we wrap it explicitly. The dictionary is read-only after parsing.
    private struct ResponseBox: @unchecked Sendable {
        let value: [String: Any]
    }

    /// Thread-safe accumulator for one of the child's output streams.
    /// Writers append, diagnostic snapshots read.
    private actor StreamCapture {
        private var data = Data()
        func append(_ chunk: Data) { data.append(chunk) }
        func snapshot() -> String { String(decoding: data, as: UTF8.self) }
        func bytes() -> Int { data.count }
        func tailHex(count: Int = 16) -> String {
            let suffix = data.suffix(count)
            return suffix.map { String(format: "%02x", $0) }.joined(separator: " ")
        }
    }

    // MARK: - Private Properties

    private let process: Process
    private let stdin: FileHandle
    private let stdout: FileHandle
    private let stderrDrainer: Task<Void, Never>
    private let stderrCapture: StreamCapture
    private let stdoutCapture: StreamCapture
    private var stdoutBuffer = Data()
    private var nextID: Int = 0

    // MARK: - Initializers

    private init(
        process: Process,
        stdin: FileHandle,
        stdout: FileHandle,
        stderrDrainer: Task<Void, Never>,
        stderrCapture: StreamCapture,
        stdoutCapture: StreamCapture
    ) {
        self.process = process
        self.stdin = stdin
        self.stdout = stdout
        self.stderrDrainer = stderrDrainer
        self.stderrCapture = stderrCapture
        self.stdoutCapture = stdoutCapture
    }

    // MARK: - Lifecycle

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

        // Drain stderr (so the server doesn't block on a full pipe buffer)
        // and capture it for diagnostics on timeout / error.
        let stderrHandle = stderrPipe.fileHandleForReading
        let capture = StreamCapture()
        let drainer = Task.detached {
            while true {
                guard let chunk = try? stderrHandle.read(upToCount: 4096),
                      !chunk.isEmpty
                else { return }
                await capture.append(chunk)
            }
        }

        return MCPProcessClient(
            process: process,
            stdin: stdinPipe.fileHandleForWriting,
            stdout: stdoutPipe.fileHandleForReading,
            stderrDrainer: drainer,
            stderrCapture: capture,
            stdoutCapture: StreamCapture()
        )
    }

    func terminate() {
        stderrDrainer.cancel()
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        try? stdin.close()
    }

    // MARK: - JSON-RPC

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
        // `[String: Any]` isn't `Sendable`, so the value is shuttled out of the
        // task group inside an unchecked-Sendable wrapper.
        let box = try await withThrowingTaskGroup(of: ResponseBox.self) { group in
            group.addTask { [self] in
                while true {
                    if let object = consumeJSONObjectFromBuffer() {
                        if let respID = object["id"] as? Int, respID == id {
                            return ResponseBox(value: object)
                        }
                        // Notification or unrelated id; keep reading.
                        continue
                    }
                    try Task.checkCancellation()
                    let chunk = try await readChunk()
                    if chunk.isEmpty {
                        throw MCPClientError.endOfStream(
                            isProcessRunning: process.isRunning,
                            exitCode: process.isRunning ? nil : process.terminationStatus
                        )
                    }
                    await stdoutCapture.append(chunk)
                    stdoutBuffer.append(chunk)
                }
            }
            group.addTask { [self] in
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                // Force-close stdout so the reader's blocking pipe read
                // returns immediately. Without this, group.cancelAll()
                // can't unblock a `FileHandle.read(upToCount:)` running on
                // a dispatch queue, and the task group deadlocks.
                try? stdout.close()
                throw MCPClientError.timeout(
                    method: "id=\(id)",
                    diagnostics: await diagnosticSnapshot()
                )
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
        return box.value
    }

    /// Tries to consume one complete JSON object from the front of the buffer.
    /// Strips a leading `\n`-terminated line first (the canonical NDJSON case),
    /// otherwise falls back to parsing the trimmed remainder. Returns nil if
    /// no complete object is currently parseable. Robust to a missing trailing
    /// newline — we've observed responses arriving without one in CI, even
    /// though swift-sdk's send() appends `0x0A`.
    private func consumeJSONObjectFromBuffer() -> [String: Any]? {
        if let nlIndex = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = Data(stdoutBuffer[stdoutBuffer.startIndex..<nlIndex])
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...nlIndex)
            if line.isEmpty { return nil }
            return try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        }
        var candidate = stdoutBuffer
        while let last = candidate.last, isJSONWhitespace(last) {
            candidate.removeLast()
        }
        guard !candidate.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: candidate) as? [String: Any]
        else { return nil }
        stdoutBuffer.removeAll(keepingCapacity: true)
        return object
    }

    private func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    /// Builds a diagnostic snapshot of the child's state for inclusion in
    /// timeout/EOF errors. Captures stderr (in case the server logged a
    /// failure), the running flag, and the exit code if known.
    private func diagnosticSnapshot() async -> Diagnostics {
        Diagnostics(
            stderr: await stderrCapture.snapshot(),
            stdout: await stdoutCapture.snapshot(),
            stdoutBytes: await stdoutCapture.bytes(),
            stdoutTailHex: await stdoutCapture.tailHex(),
            isProcessRunning: process.isRunning,
            exitCode: process.isRunning ? nil : process.terminationStatus
        )
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

    // MARK: - Executable Path

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
        // Resolve the SwiftPM products dir via the test bundle. Under
        // swift-testing the .xctest bundle isn't always registered in
        // Bundle.allBundles, but Bundle(for:) with a class anchor in the
        // test module reliably returns it.
        return Bundle(for: BundleAnchor.self).bundleURL.deletingLastPathComponent()
#else
        return Bundle.main.bundleURL
#endif
    }
}

/// Class-typed anchor used purely so `Bundle(for:)` can locate the test bundle
/// on macOS. Must be a class because `Bundle(for:)` is defined on `AnyClass`.
private final class BundleAnchor {}

// MARK: - Diagnostics

/// Snapshot of the child process state, attached to errors so timeout
/// failures in CI carry the server's stderr instead of being opaque.
struct Diagnostics: Sendable {
    let stderr: String
    let stdout: String
    let stdoutBytes: Int
    let stdoutTailHex: String
    let isProcessRunning: Bool
    let exitCode: Int32?

    var formatted: String {
        let exit = exitCode.map(String.init) ?? "n/a"
        let tail = stdoutTailHex.isEmpty ? "(empty)" : stdoutTailHex
        return """
        running=\(isProcessRunning) exitCode=\(exit) stdoutBytes=\(stdoutBytes) stdoutTailHex=\(tail)
        stderr=\(format(stderr))
        stdoutRaw=\(format(stdout, trim: false))
        """
    }

    private func format(_ stream: String, trim: Bool = true) -> String {
        let value = trim ? stream.trimmingCharacters(in: .whitespacesAndNewlines) : stream
        return value.isEmpty ? "(empty)" : "\n---\n\(value)\n---"
    }
}

// MARK: - MCPClientError

enum MCPClientError: Error, CustomStringConvertible {

    // MARK: - Cases

    case timeout(method: String, diagnostics: Diagnostics)
    case endOfStream(isProcessRunning: Bool, exitCode: Int32?)
    case executableNotFound(String)
    case missingField(String)
    case wrongType(field: String, expected: String)

    // MARK: - CustomStringConvertible

    var description: String {
        switch self {
        case .timeout(let method, let diagnostics):
            return "Timed out waiting for MCP response (\(method)); \(diagnostics.formatted)"
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

// MARK: - JSON Convenience Accessors

extension Dictionary where Key == String, Value == Any {

    // MARK: - Required Fields

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

    // MARK: - Content Helpers

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
