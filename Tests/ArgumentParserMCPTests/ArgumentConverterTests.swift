import Testing
import MCP

@testable import ArgumentParserMCP

@Suite("ArgumentConverter")
struct ArgumentConverterTests {

    // MARK: - Flags

    private let argumentConverter = ArgumentConverter()

    // MARK: - Flags

    @Test func convertsFlagTrue() throws {
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

        let result = try argumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["--verbose"])
    }

    @Test func convertsFlagFalse() throws {
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

        let result = try argumentConverter.convert(arguments: args, using: infos)
        #expect(result.isEmpty)
    }

    @Test func skipsMissingFlag() throws {
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

        let result = try argumentConverter.convert(arguments: args, using: infos)
        #expect(result.isEmpty)
    }

    // MARK: - Options

    @Test func convertsStringOption() throws {
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

        let result = try argumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["--output", "/tmp/out.txt"])
    }

    @Test func convertsIntOption() throws {
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

        let result = try argumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["--count", "5"])
    }

    @Test func convertsOptionWithShortName() throws {
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

        let result = try argumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["-n", "3"])
    }

    @Test func convertsRepeatingOption() throws {
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

        let result = try argumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["--tag", "alpha", "--tag", "beta"])
    }

    // MARK: - Positional arguments

    @Test func convertsPositionalArgument() throws {
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

        let result = try argumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["input.txt"])
    }

    @Test func convertsRepeatingPositional() throws {
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

        let result = try argumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["a.txt", "b.txt"])
    }

    // MARK: - Mixed arguments

    @Test func positionalsAppearAfterOptionsAndFlags() throws {
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

        let result = try argumentConverter.convert(arguments: args, using: infos)

        // Flags and options first, then positionals
        #expect(result == ["--include-counter", "--count", "3", "hello"])
    }

    @Test func multiplePositionalsPreserveOrder() throws {
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

        let result = try argumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["src.txt", "dst.txt"])
    }

    // MARK: - Filtering

    @Test func filtersHiddenArguments() throws {
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

        let result = try argumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["world"])
    }

    @Test func filtersHelpArguments() throws {
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

        let result = try argumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["test"])
    }

    // MARK: - Empty input

    @Test func emptyArgumentsProducesEmptyResult() throws {
        let result = try argumentConverter.convert(arguments: [:], using: [])
        #expect(result.isEmpty)
    }

    // MARK: - Name resolution

    @Test func usesLongWithSingleDashFormat() throws {
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

        let result = try argumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["-verbose"])
    }

    // MARK: - Validation: required arguments

    @Test func throwsWhenRequiredOptionMissing() {
        let infos = [
            DumpArgumentInfo(
                kind: .option,
                shouldDisplay: true,
                isOptional: false,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .long, name: "output")
            ),
        ]

        #expect(throws: MCPError.self) {
            try argumentConverter.convert(arguments: [:], using: infos)
        }
    }

    @Test func throwsWhenRequiredPositionalMissing() {
        let infos = [
            DumpArgumentInfo(
                kind: .positional,
                shouldDisplay: true,
                isOptional: false,
                isRepeating: false,
                valueName: "file"
            ),
        ]

        #expect(throws: MCPError.self) {
            try argumentConverter.convert(arguments: [:], using: infos)
        }
    }

    @Test func aggregatesMultipleMissingRequiredArguments() {
        let infos = [
            DumpArgumentInfo(
                kind: .option,
                shouldDisplay: true,
                isOptional: false,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .long, name: "output")
            ),
            DumpArgumentInfo(
                kind: .positional,
                shouldDisplay: true,
                isOptional: false,
                isRepeating: false,
                valueName: "file"
            ),
        ]

        #expect(throws: MCPError.self) {
            try argumentConverter.convert(arguments: [:], using: infos)
        }
    }

    @Test func skipsMissingOptionalOption() throws {
        let infos = [
            DumpArgumentInfo(
                kind: .option,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .long, name: "output")
            ),
        ]

        let result = try argumentConverter.convert(arguments: [:], using: infos)
        #expect(result.isEmpty)
    }

    // MARK: - Validation: enum (allValues) constraints

    @Test func throwsWhenOptionValueNotInAllowedValues() {
        let args: [String: Value] = ["language": .string("fr")]
        let infos = [
            DumpArgumentInfo(
                kind: .option,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .long, name: "language"),
                allValues: ["en", "ru"]
            ),
        ]

        #expect(throws: MCPError.self) {
            try argumentConverter.convert(arguments: args, using: infos)
        }
    }

    @Test func acceptsValueInAllowedValues() throws {
        let args: [String: Value] = ["language": .string("en")]
        let infos = [
            DumpArgumentInfo(
                kind: .option,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .long, name: "language"),
                allValues: ["en", "ru"]
            ),
        ]

        let result = try argumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["--language", "en"])
    }

    @Test func throwsWhenRepeatingOptionElementNotAllowed() {
        let args: [String: Value] = [
            "language": .array([.string("en"), .string("fr")])
        ]
        let infos = [
            DumpArgumentInfo(
                kind: .option,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: true,
                preferredName: DumpNameInfo(kind: .long, name: "language"),
                allValues: ["en", "ru"]
            ),
        ]

        #expect(throws: MCPError.self) {
            try argumentConverter.convert(arguments: args, using: infos)
        }
    }

    @Test func enumComparisonWorksForIntegerValues() throws {
        let args: [String: Value] = ["level": .int(2)]
        let infos = [
            DumpArgumentInfo(
                kind: .option,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .long, name: "level"),
                allValues: ["1", "2", "3"]
            ),
        ]

        let result = try argumentConverter.convert(arguments: args, using: infos)
        #expect(result == ["--level", "2"])
    }

    // MARK: - Validation: type / kind mismatches

    @Test func throwsWhenFlagReceivesNonBool() {
        let args: [String: Value] = ["verbose": .string("true")]
        let infos = [
            DumpArgumentInfo(
                kind: .flag,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .long, name: "verbose")
            ),
        ]

        #expect(throws: MCPError.self) {
            try argumentConverter.convert(arguments: args, using: infos)
        }
    }

    @Test func throwsWhenScalarOptionReceivesArray() {
        let args: [String: Value] = ["output": .array([.string("a")])]
        let infos = [
            DumpArgumentInfo(
                kind: .option,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .long, name: "output")
            ),
        ]

        #expect(throws: MCPError.self) {
            try argumentConverter.convert(arguments: args, using: infos)
        }
    }

    @Test func throwsWhenRepeatingOptionReceivesScalar() {
        let args: [String: Value] = ["tag": .string("alpha")]
        let infos = [
            DumpArgumentInfo(
                kind: .option,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: true,
                preferredName: DumpNameInfo(kind: .long, name: "tag")
            ),
        ]

        #expect(throws: MCPError.self) {
            try argumentConverter.convert(arguments: args, using: infos)
        }
    }

    @Test func throwsWhenScalarOptionReceivesObject() {
        let args: [String: Value] = ["output": .object(["nested": .string("x")])]
        let infos = [
            DumpArgumentInfo(
                kind: .option,
                shouldDisplay: true,
                isOptional: true,
                isRepeating: false,
                preferredName: DumpNameInfo(kind: .long, name: "output")
            ),
        ]

        #expect(throws: MCPError.self) {
            try argumentConverter.convert(arguments: args, using: infos)
        }
    }

    @Test func throwsWhenRepeatingOptionElementIsNotScalar() {
        let args: [String: Value] = [
            "tag": .array([.string("alpha"), .object(["k": .string("v")])])
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

        #expect(throws: MCPError.self) {
            try argumentConverter.convert(arguments: args, using: infos)
        }
    }
}
