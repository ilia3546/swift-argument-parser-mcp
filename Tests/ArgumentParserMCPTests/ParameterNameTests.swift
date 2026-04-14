import Testing

@testable import ArgumentParserMCP

@Suite("parameterName")
struct ParameterNameTests {

    @Test func usesPreferredNameForOption() {
        let arg = DumpArgumentInfo(
            kind: .option,
            shouldDisplay: true,
            isOptional: true,
            isRepeating: false,
            names: [
                DumpNameInfo(kind: .short, name: "c"),
                DumpNameInfo(kind: .long, name: "count"),
            ],
            preferredName: DumpNameInfo(kind: .long, name: "count")
        )
        #expect(parameterName(for: arg) == "count")
    }

    @Test func fallsBackToFirstLongName() {
        let arg = DumpArgumentInfo(
            kind: .option,
            shouldDisplay: true,
            isOptional: true,
            isRepeating: false,
            names: [
                DumpNameInfo(kind: .short, name: "o"),
                DumpNameInfo(kind: .long, name: "output"),
            ]
        )
        #expect(parameterName(for: arg) == "output")
    }

    @Test func fallsBackToValueNameForOptionWithoutNames() {
        let arg = DumpArgumentInfo(
            kind: .option,
            shouldDisplay: true,
            isOptional: true,
            isRepeating: false,
            valueName: "path"
        )
        #expect(parameterName(for: arg) == "path")
    }

    @Test func returnsUnknownForOptionWithNoInfo() {
        let arg = DumpArgumentInfo(
            kind: .option,
            shouldDisplay: true,
            isOptional: true,
            isRepeating: false
        )
        #expect(parameterName(for: arg) == "unknown")
    }

    @Test func usesPreferredNameForFlag() {
        let arg = DumpArgumentInfo(
            kind: .flag,
            shouldDisplay: true,
            isOptional: true,
            isRepeating: false,
            preferredName: DumpNameInfo(kind: .long, name: "dry-run")
        )
        #expect(parameterName(for: arg) == "dry-run")
    }

    @Test func usesValueNameForPositional() {
        let arg = DumpArgumentInfo(
            kind: .positional,
            shouldDisplay: true,
            isOptional: false,
            isRepeating: false,
            valueName: "filename"
        )
        #expect(parameterName(for: arg) == "filename")
    }

    @Test func returnsArgForPositionalWithoutValueName() {
        let arg = DumpArgumentInfo(
            kind: .positional,
            shouldDisplay: true,
            isOptional: false,
            isRepeating: false
        )
        #expect(parameterName(for: arg) == "arg")
    }
}
