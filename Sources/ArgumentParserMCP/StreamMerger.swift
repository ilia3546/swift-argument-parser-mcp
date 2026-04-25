import Foundation

/// Captures stdout and stderr from a subprocess concurrently, preserving
/// best-effort line-arrival ordering across the two streams.
///
/// The arrival order is approximate: read-side timestamps depend on pipe
/// buffering in the kernel and on the child process's own line/block
/// buffering. It is "what a developer would see in a terminal", not
/// the exact write order at the source.
actor StreamMerger {

    // MARK: - Nested Types

    enum Stream: Sendable {
        case stdout
        case stderr
    }

    struct Entry: Sendable {
        let stream: Stream
        let bytes: Data
    }

    struct Snapshot: Sendable {
        let stdout: Data
        let stderr: Data
        let entries: [Entry]
        let stdoutTruncated: Bool
        let stderrTruncated: Bool
    }

    // MARK: - Private Properties

    private let perStreamCapBytes: Int
    private var stdoutBytes = Data()
    private var stderrBytes = Data()
    private var stdoutPartial = Data()
    private var stderrPartial = Data()
    private var entries: [Entry] = []
    private var stdoutTruncated = false
    private var stderrTruncated = false

    // MARK: - Initializers

    init(perStreamCapBytes: Int) {
        self.perStreamCapBytes = perStreamCapBytes
    }

    // MARK: - Internal Methods

    func append(stream: Stream, chunk: Data) {
        guard !chunk.isEmpty else { return }

        let accepted = clip(chunk: chunk, stream: stream)
        guard !accepted.isEmpty else { return }

        switch stream {
        case .stdout:
            stdoutBytes.append(accepted)
            stdoutPartial.append(accepted)
            extractLines(stream: .stdout)
        case .stderr:
            stderrBytes.append(accepted)
            stderrPartial.append(accepted)
            extractLines(stream: .stderr)
        }
    }

    func finalize() -> Snapshot {
        if !stdoutPartial.isEmpty {
            entries.append(Entry(stream: .stdout, bytes: stdoutPartial))
            stdoutPartial.removeAll()
        }
        if !stderrPartial.isEmpty {
            entries.append(Entry(stream: .stderr, bytes: stderrPartial))
            stderrPartial.removeAll()
        }
        return Snapshot(
            stdout: stdoutBytes,
            stderr: stderrBytes,
            entries: entries,
            stdoutTruncated: stdoutTruncated,
            stderrTruncated: stderrTruncated
        )
    }

    // MARK: - Private Methods

    private func clip(chunk: Data, stream: Stream) -> Data {
        let currentCount: Int
        switch stream {
        case .stdout: currentCount = stdoutBytes.count
        case .stderr: currentCount = stderrBytes.count
        }

        if currentCount >= perStreamCapBytes {
            markTruncated(stream)
            return Data()
        }

        let remaining = perStreamCapBytes - currentCount
        if chunk.count <= remaining {
            return chunk
        }

        markTruncated(stream)
        return chunk.prefix(remaining)
    }

    private func markTruncated(_ stream: Stream) {
        switch stream {
        case .stdout: stdoutTruncated = true
        case .stderr: stderrTruncated = true
        }
    }

    private func extractLines(stream: Stream) {
        switch stream {
        case .stdout:
            extractLines(buffer: &stdoutPartial, stream: .stdout)
        case .stderr:
            extractLines(buffer: &stderrPartial, stream: .stderr)
        }
    }

    private func extractLines(buffer: inout Data, stream: Stream) {
        while let nlIndex = buffer.firstIndex(of: 0x0A) {
            let lineRange = buffer.startIndex...nlIndex
            entries.append(Entry(stream: stream, bytes: Data(buffer[lineRange])))
            buffer.removeSubrange(lineRange)
        }
    }
}

/// Renders an interleaved log from a ``StreamMerger/Snapshot`` for human
/// consumption. Lines that came from stderr are prefixed (default `[stderr] `)
/// so the agent can still tell them apart in the merged form.
func mergedLog(
    from snapshot: StreamMerger.Snapshot,
    stderrPrefix: String = "[stderr] "
) -> String {
    var output = ""
    for entry in snapshot.entries {
        let line = String(decoding: entry.bytes, as: UTF8.self)
        let lineWithoutTrailingNewline: String =
            line.hasSuffix("\n") ? String(line.dropLast()) : line

        switch entry.stream {
        case .stdout:
            output.append(lineWithoutTrailingNewline)
        case .stderr:
            output.append(stderrPrefix)
            output.append(lineWithoutTrailingNewline)
        }
        output.append("\n")
    }
    if output.hasSuffix("\n") {
        output.removeLast()
    }
    return output
}
