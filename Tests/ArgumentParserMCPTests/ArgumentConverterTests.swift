import Testing
import MCP

@testable import ArgumentParserMCP

@Suite("ArgumentConverter")
struct ArgumentConverterTests {

    // MARK: - Flags

    @Test func convertsFlagTrue() {
        let args: [String: Value] = ["verbose": .bool(true)]
        let infos = [
            DumpArgumentInfo(
                kind: .flag,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .long, name: "verbose")
            ),
        ]

        let result = ArgumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["--verbose"])
    }

    @Test func convertsFlagFalse() {
        let args: [String: Value] = ["verbose": .bool(false)]
        let infos = [
            DumpArgumentInfo(
                kind: .flag,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .long, name: "verbose")
            ),
        ]

        let result = ArgumentConverter.convert(arguments: args, using: infos)
        #expect(result.isEmpty)
    }

    @Test func skipsMissingFlag() {
        let args: [String: Value] = [:]
        let infos = [
            DumpArgumentInfo(
                kind: .flag,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .long, name: "verbose")
            ),
        ]

        let result = ArgumentConverter.convert(arguments: args, using: infos)
        #expect(result.isEmpty)
    }

    // MARK: - Options

    @Test func convertsStringOption() {
        let args: [String: Value] = ["output": .string("/tmp/out.txt")]
        let infos = [
            DumpArgumentInfo(
                kind: .option,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .long, name: "output")
            ),
        ]

        let result = ArgumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["--output", "/tmp/out.txt"])
    }

    @Test func convertsIntOption() {
        let args: [String: Value] = ["count": .int(5)]
        let infos = [
            DumpArgumentInfo(
                kind: .option,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .long, name: "count")
            ),
        ]

        let result = ArgumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["--count", "5"])
    }

    @Test func convertsOptionWithShortName() {
        let args: [String: Value] = ["n": .string("3")]
        let infos = [
            DumpArgumentInfo(
                kind: .option,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .short, name: "n")
            ),
        ]

        let result = ArgumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["-n", "3"])
    }

    @Test func convertsRepeatingOption() {
        let args: [String: Value] = [
            "tag": .array([.string("alpha"), .string("beta")])
        ]
        let infos = [
            DumpArgumentInfo(
                kind: .option,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: true,
                preferredName: DumpNameInfo(kind: .long, name: "tag")
            ),
        ]

        let result = ArgumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["--tag", "alpha", "--tag", "beta"])
    }

    // MARK: - Positional arguments

    @Test func convertsPositionalArgument() {
        let args: [String: Value] = ["file": .string("input.txt")]
        let infos = [
            DumpArgumentInfo(
                kind: .positional,
                shouldDisplay: true,
                isOptional: false,
                isRepeating: false,
                valueName: "file"
            ),
        ]

        let result = ArgumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["input.txt"])
    }

    @Test func convertsRepeatingPositional() {
        let args: [String: Value] = [
            "files": .array([.string("a.txt"), .string("b.txt")])
        ]
        let infos = [
            DumpArgumentInfo(
                kind: .positional,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: true,
                valueName: "files"
            ),
        ]

        let result = ArgumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["a.txt", "b.txt"])
    }

    // MARK: - Mixed arguments

    @Test func positionalsAppearAfterOptionsAndFlags() {
        let args: [String: Value] = [
            "phrase": .string("hello"),
            "count": .string("3"),
            "include-counter": .bool(true),
        ]
        let infos = [
            DumpArgumentInfo(
                kind: .flag,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .long, name: "include-counter")
            ),
            DumpArgumentInfo(
                kind: .option,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .long, name: "count")
            ),
            DumpArgumentInfo(
                kind: .positional,
                shouldDisplay: true,
                isOptional: false,
                isRepeating: false,
                valueName: "phrase"
            ),
        ]

        let result = ArgumentConverter.convert(arguments: args, using: infos)

        // Flags and options first, then positionals
        #expect(result == ["--include-counter", "--count", "3", "hello"])
    }

    @Test func multiplePositionalsPreserveOrder() {
        let args: [String: Value] = [
            "source": .string("src.txt"),
            "destination": .string("dst.txt"),
        ]
        let infos = [
            DumpArgumentInfo(
                kind: .positional,
                shouldDisplay: true,
                isOptional: false,
                isRepeating: false,
                valueName: "source"
            ),
            DumpArgumentInfo(
                kind: .positional,
                shouldDisplay: true,
                isOptional: false,
                isRepeating: false,
                valueName: "destination"
            ),
        ]

        let result = ArgumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["src.txt", "dst.txt"])
    }

    // MARK: - Filtering

    @Test func filtersHiddenArguments() {
        let args: [String: Value] = [
            "name": .string("world"),
            "secret": .string("hidden"),
        ]
        let infos = [
            DumpArgumentInfo(
                kind: .positional,
                shouldDisplay: true,
                isOptional: false,
                isRepeating: false,
                valueName: "name"
            ),
            DumpArgumentInfo(
                kind: .option,
                shouldDisplay: false,
                isOptional: true,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .long, name: "secret")
            ),
        ]

        let result = ArgumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["world"])
    }

    @Test func filtersHelpArguments() {
        let args: [String: Value] = [
            "name": .string("test"),
            "help": .bool(true),
        ]
        let infos = [
            DumpArgumentInfo(
                kind: .positional,
                shouldDisplay: true,
                isOptional: false,
                isRepeating: false,
                valueName: "name"
            ),
            DumpArgumentInfo(
                kind: .flag,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .long, name: "help")
            ),
        ]

        let result = ArgumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["test"])
    }

    // MARK: - Empty input

    @Test func emptyArgumentsProducesEmptyResult() {
        let result = ArgumentConverter.convert(arguments: [:], using: [])
        #expect(result.isEmpty)
    }

    // MARK: - Name resolution

    @Test func usesLongWithSingleDashFormat() {
        let args: [String: Value] = ["verbose": .bool(true)]
        let infos = [
            DumpArgumentInfo(
                kind: .flag,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .longWithSingleDash, name: "verbose")
            ),
        ]

        let result = ArgumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["-verbose"])
    }
}
