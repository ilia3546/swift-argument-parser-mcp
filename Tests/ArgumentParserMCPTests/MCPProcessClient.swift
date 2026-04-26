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

    /// Thread-safe accumulator for the child's stderr; used to attach the
    /// server's log output to timeout / EOF errors.
    private actor StreamCapture {
        private var data = Data()
        func append(_ chunk: Data) { data.append(chunk) }
        func snapshot() -> String { String(decoding: data, as: UTF8.self) }
    }

    /// One-shot signal raised by the timeout task before it force-closes
    /// stdout. The reader checks it when `availableData` returns empty so
    /// it can report a `.timeout` (with the captured stderr) instead of a
    /// misleading `.endOfStream` — both tasks are racing to throw, and
    /// without this flag whichever one wins changes the error type.
    private actor TimeoutGate {
        private(set) var fired = false
        func fire() { fired = true }
    }

    // MARK: - Private Properties

    private let process: Process
    private let stdin: FileHandle
    private let stdout: FileHandle
    private let stderrDrainer: Task<Void, Never>
    private let stderrCapture: StreamCapture
    private var stdoutBuffer = Data()
    private var nextID: Int = 0

    // MARK: - Initializers

    private init(
        process: Process,
        stdin: FileHandle,
        stdout: FileHandle,
        stderrDrainer: Task<Void, Never>,
        stderrCapture: StreamCapture
    ) {
        self.process = process
        self.stdin = stdin
        self.stdout = stdout
        self.stderrDrainer = stderrDrainer
        self.stderrCapture = stderrCapture
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
            stderrCapture: capture
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
        let gate = TimeoutGate()
        // `[String: Any]` isn't `Sendable`, so the value is shuttled out of the
        // task group inside an unchecked-Sendable wrapper.
        let box = try await withThrowingTaskGroup(of: ResponseBox.self) { group in
            group.addTask { [self] in
                while true {
                    if let object = consumeJSONObjectFromBuffer() {
                        if matchesRequest(object, id: id) {
                            return ResponseBox(value: object)
                        }
                        // Notification or unrelated message; keep reading.
                        continue
                    }
                    try Task.checkCancellation()
                    let chunk = try await readChunk()
                    if chunk.isEmpty {
                        let stderr = await stderrCapture.snapshot()
                        let isRunning = process.isRunning
                        let exitCode = isRunning ? nil : process.terminationStatus
                        if await gate.fired {
                            throw MCPClientError.timeout(
                                method: "id=\(id)",
                                stderr: stderr,
                                isProcessRunning: isRunning,
                                exitCode: exitCode
                            )
                        }
                        throw MCPClientError.endOfStream(
                            stderr: stderr,
                            isProcessRunning: isRunning,
                            exitCode: exitCode
                        )
                    }
                    stdoutBuffer.append(chunk)
                }
            }
            group.addTask { [self] in
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                // Force-close stdout so the reader's blocking pipe read
                // returns immediately. Without this, group.cancelAll() can't
                // unblock a `FileHandle.availableData` running on a dispatch
                // queue and the task group deadlocks. Raise the gate first
                // so the reader, which will likely wake up before this task
                // throws, knows the EOF is artificial.
                await gate.fire()
                try? stdout.close()
                throw MCPClientError.timeout(
                    method: "id=\(id)",
                    stderr: await stderrCapture.snapshot(),
                    isProcessRunning: process.isRunning,
                    exitCode: process.isRunning ? nil : process.terminationStatus
                )
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
        return box.value
    }

    /// Tries to consume one complete JSON object from the front of the buffer.
    /// Prefers a leading `\n`-terminated line (the canonical NDJSON case) and
    /// falls back to parsing the trimmed remainder, so the harness still works
    /// if the trailing newline is absent.
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

    /// Treats `object` as the response to our outstanding request when it
    /// looks like one: it must carry a `result` or `error` member, and (if
    /// it has an `id` we can read) the id must match. Tests are `.serialized`
    /// so there's only ever one outstanding request per client; this lets us
    /// tolerate JSONSerialization yielding NSNumber/Double forms of the id
    /// without breaking the match.
    private func matchesRequest(_ object: [String: Any], id: Int) -> Bool {
        guard object["result"] != nil || object["error"] != nil else {
            return false
        }
        let raw = object["id"]
        if let int = raw as? Int { return int == id }
        if let num = raw as? NSNumber { return num.intValue == id }
        if let dbl = raw as? Double { return Int(dbl) == id }
        if let str = raw as? String, let parsed = Int(str) { return parsed == id }
        return true
    }

    private func readChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async { [stdout] in
                // FileHandle.availableData blocks only until the first byte
                // arrives and then returns whatever is currently buffered.
                // FileHandle.read(upToCount:) on macOS waits for the full
                // requested count or EOF on a pipe — for a small response
                // with a 4 KiB ask, that means we'd block until the writer
                // closed the stream.
                let data = stdout.availableData
                continuation.resume(returning: data)
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

// MARK: - MCPClientError

enum MCPClientError: Error, CustomStringConvertible {

    // MARK: - Cases

    case timeout(method: String, stderr: String, isProcessRunning: Bool, exitCode: Int32?)
    case endOfStream(stderr: String, isProcessRunning: Bool, exitCode: Int32?)
    case executableNotFound(String)
    case missingField(String)
    case wrongType(field: String, expected: String)

    // MARK: - CustomStringConvertible

    var description: String {
        switch self {
        case .timeout(let method, let stderr, let running, let code):
            let exit = code.map(String.init) ?? "n/a"
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stderrSection = trimmed.isEmpty ? "(empty)" : "\n---\n\(trimmed)\n---"
            return """
            Timed out waiting for MCP response (\(method)); running=\(running) exitCode=\(exit)
            stderr=\(stderrSection)
            """
        case .endOfStream(let stderr, let running, let code):
            let exit = code.map(String.init) ?? "n/a"
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stderrSection = trimmed.isEmpty ? "(empty)" : "\n---\n\(trimmed)\n---"
            return """
            Server closed stdout (running=\(running), exitCode=\(exit))
            stderr=\(stderrSection)
            """
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
