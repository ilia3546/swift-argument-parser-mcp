import Foundation
import Testing

@testable import ArgumentParserMCP

@Suite("StreamMerger")
struct StreamMergerTests {

    // MARK: - Line Interleaving

    @Test func interleavesStdoutAndStderrInArrivalOrder() async {
        let merger = StreamMerger(perStreamCapBytes: .max)

        await merger.append(stream: .stdout, chunk: Data("first stdout\n".utf8))
        await merger.append(stream: .stderr, chunk: Data("first stderr\n".utf8))
        await merger.append(stream: .stdout, chunk: Data("second stdout\n".utf8))

        let snapshot = await merger.finalize()
        let merged = mergedLog(from: snapshot)

        #expect(merged == """
        first stdout
        [stderr] first stderr
        second stdout
        """)
    }

    @Test func splitsMultilineChunkIntoSeparateEntries() async {
        let merger = StreamMerger(perStreamCapBytes: .max)

        await merger.append(stream: .stdout, chunk: Data("line one\nline two\n".utf8))

        let snapshot = await merger.finalize()
        #expect(snapshot.entries.count == 2)
        #expect(String(decoding: snapshot.entries[0].bytes, as: UTF8.self) == "line one\n")
        #expect(String(decoding: snapshot.entries[1].bytes, as: UTF8.self) == "line two\n")
    }

    @Test func partialLineIsHeldUntilNewlineArrives() async {
        let merger = StreamMerger(perStreamCapBytes: .max)

        await merger.append(stream: .stdout, chunk: Data("hel".utf8))
        await merger.append(stream: .stderr, chunk: Data("warning\n".utf8))
        await merger.append(stream: .stdout, chunk: Data("lo\n".utf8))

        let snapshot = await merger.finalize()
        let merged = mergedLog(from: snapshot)

        // The stdout partial "hel" is buffered until the trailing "lo\n" arrives,
        // so the [stderr] line lands first in the merged log.
        #expect(merged == """
        [stderr] warning
        hello
        """)
    }

    @Test func finalizeFlushesUnterminatedPartialLine() async {
        let merger = StreamMerger(perStreamCapBytes: .max)

        await merger.append(stream: .stdout, chunk: Data("no trailing newline".utf8))

        let snapshot = await merger.finalize()
        let merged = mergedLog(from: snapshot)

        #expect(merged == "no trailing newline")
        #expect(snapshot.entries.count == 1)
    }

    @Test func stderrPrefixIsCustomizable() async {
        let merger = StreamMerger(perStreamCapBytes: .max)

        await merger.append(stream: .stdout, chunk: Data("ok\n".utf8))
        await merger.append(stream: .stderr, chunk: Data("oops\n".utf8))

        let snapshot = await merger.finalize()
        let merged = mergedLog(from: snapshot, stderrPrefix: "ERR| ")

        #expect(merged == """
        ok
        ERR| oops
        """)
    }

    // MARK: - Raw Buffers

    @Test func rawBuffersContainAllReceivedBytes() async {
        let merger = StreamMerger(perStreamCapBytes: .max)

        await merger.append(stream: .stdout, chunk: Data("hello\nworld".utf8))
        await merger.append(stream: .stderr, chunk: Data("oops".utf8))

        let snapshot = await merger.finalize()

        #expect(String(decoding: snapshot.stdout, as: UTF8.self) == "hello\nworld")
        #expect(String(decoding: snapshot.stderr, as: UTF8.self) == "oops")
    }

    // MARK: - Truncation

    @Test func truncatesStdoutAtPerStreamCap() async {
        let merger = StreamMerger(perStreamCapBytes: 5)

        await merger.append(stream: .stdout, chunk: Data("ABCDEFGHIJ".utf8))

        let snapshot = await merger.finalize()

        #expect(snapshot.stdoutTruncated == true)
        #expect(snapshot.stderrTruncated == false)
        #expect(snapshot.stdout.count == 5)
        #expect(String(decoding: snapshot.stdout, as: UTF8.self) == "ABCDE")
    }

    @Test func truncatesIndependentlyPerStream() async {
        let merger = StreamMerger(perStreamCapBytes: 3)

        await merger.append(stream: .stdout, chunk: Data("ABCDE".utf8))
        await merger.append(stream: .stderr, chunk: Data("XY".utf8))

        let snapshot = await merger.finalize()

        #expect(snapshot.stdoutTruncated == true)
        #expect(snapshot.stderrTruncated == false)
        #expect(String(decoding: snapshot.stdout, as: UTF8.self) == "ABC")
        #expect(String(decoding: snapshot.stderr, as: UTF8.self) == "XY")
    }

    @Test func dropsChunksAfterCapHit() async {
        let merger = StreamMerger(perStreamCapBytes: 4)

        await merger.append(stream: .stdout, chunk: Data("abcd".utf8))
        await merger.append(stream: .stdout, chunk: Data("efgh".utf8))

        let snapshot = await merger.finalize()

        #expect(snapshot.stdoutTruncated == true)
        #expect(String(decoding: snapshot.stdout, as: UTF8.self) == "abcd")
    }

    // MARK: - Edge Cases

    @Test func emptyChunkIsIgnored() async {
        let merger = StreamMerger(perStreamCapBytes: .max)

        await merger.append(stream: .stdout, chunk: Data())

        let snapshot = await merger.finalize()

        #expect(snapshot.entries.isEmpty)
        #expect(snapshot.stdout.isEmpty)
        #expect(snapshot.stdoutTruncated == false)
    }

    @Test func emptySnapshotProducesEmptyMergedLog() {
        let snapshot = StreamMerger.Snapshot(
            stdout: Data(),
            stderr: Data(),
            entries: [],
            stdoutTruncated: false,
            stderrTruncated: false
        )

        #expect(mergedLog(from: snapshot) == "")
    }
}
