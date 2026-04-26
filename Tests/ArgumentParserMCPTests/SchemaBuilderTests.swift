import Testing
import MCP

@testable import ArgumentParserMCP

@Suite("SchemaBuilder")
struct SchemaBuilderTests {

    // MARK: - Private Properties

    let schemaBuilder = SchemaBuilder()

    // MARK: - toolName

    @Test func toolNameForSimpleSubcommand() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "repeat-phrase"
        )
        #expect(schemaBuilder.toolName(for: command) == "repeat-phrase")
    }

    @Test func toolNameForNestedSubcommand() {
        let command = DumpCommandInfo(
            superCommands: ["root", "group"],
            commandName: "sub-action"
        )
        #expect(schemaBuilder.toolName(for: command) == "group_sub-action")
    }

    @Test func toolNameForRootCommand() {
        let command = DumpCommandInfo(commandName: "my-tool")
        #expect(schemaBuilder.toolName(for: command) == "my-tool")
    }

    // MARK: - shouldInclude

    @Test func excludesHelpArgument() {
        let help = DumpArgumentInfo(
            kind: .flag,
            shouldDisplay: true,
            isOptional: true,
            isRepeating: false,
            preferredName: DumpNameInfo(kind: .long, name: "help")
        )
        #expect(schemaBuilder.shouldInclude(help) == false)
    }

    @Test func excludesVersionArgument() {
        let version = DumpArgumentInfo(
            kind: .flag,
            shouldDisplay: true,
            isOptional: true,
            isRepeating: false,
            preferredName: DumpNameInfo(kind: .long, name: "version")
        )
        #expect(schemaBuilder.shouldInclude(version) == false)
    }

    @Test func excludesHiddenArgument() {
        let hidden = DumpArgumentInfo(
            kind: .option,
            shouldDisplay: false,
            isOptional: true,
            isRepeating: false,
            preferredName: DumpNameInfo(kind: .long, name: "secret")
        )
        #expect(schemaBuilder.shouldInclude(hidden) == false)
    }

    @Test func includesRegularArgument() {
        let regular = DumpArgumentInfo(
            kind: .option,
            shouldDisplay: true,
            isOptional: false,
            isRepeating: false,
            preferredName: DumpNameInfo(kind: .long, name: "output")
        )
        #expect(schemaBuilder.shouldInclude(regular) == true)
    }

    // MARK: - buildTool

    @Test func buildToolWithPositionalArgument() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "greet",
            arguments: [
                DumpArgumentInfo(
                    kind: .positional,
                    shouldDisplay: true,
                    isOptional: false,
                    isRepeating: false,
                    valueName: "name",
                    abstract: "Name to greet."
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Greet someone")

        #expect(tool.name == "greet")
        #expect(tool.description == "Greet someone")

        let schema = tool.inputSchema.objectValue!
        #expect(schema["type"]?.stringValue == "object")

        let properties = schema["properties"]!.objectValue!
        let nameProp = properties["name"]!.objectValue!
        #expect(nameProp["type"]?.stringValue == "string")
        #expect(nameProp["description"]?.stringValue == "Name to greet.")

        let required = schema["required"]!.arrayValue!.map(\.stringValue)
        #expect(required == ["name"])
    }

    @Test func buildToolWithFlag() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "run",
            arguments: [
                DumpArgumentInfo(
                    kind: .flag,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: false,
                    preferredName: DumpNameInfo(kind: .long, name: "verbose"),
                    abstract: "Enable verbose output."
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Run task")
        let properties = tool.inputSchema.objectValue!["properties"]!.objectValue!
        let verbose = properties["verbose"]!.objectValue!

        #expect(verbose["type"]?.stringValue == "boolean")
        #expect(verbose["description"]?.stringValue == "Enable verbose output.")
        #expect(verbose["default"]?.boolValue == false)

        // Flag is optional, so required should be absent
        #expect(tool.inputSchema.objectValue!["required"] == nil)
    }

    @Test func buildToolWithOptionHavingEnumValues() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "export",
            arguments: [
                DumpArgumentInfo(
                    kind: .option,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: false,
                    preferredName: DumpNameInfo(kind: .long, name: "format"),
                    defaultValue: "json",
                    allValues: ["json", "yaml", "csv"],
                    abstract: "Output format."
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Export data")
        let properties = tool.inputSchema.objectValue!["properties"]!.objectValue!
        let format = properties["format"]!.objectValue!

        #expect(format["type"]?.stringValue == "string")
        #expect(format["default"]?.stringValue == "json")

        let enumValues = format["enum"]!.arrayValue!.compactMap(\.stringValue)
        #expect(enumValues == ["json", "yaml", "csv"])
    }

    @Test func buildToolWithRepeatingOption() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "process",
            arguments: [
                DumpArgumentInfo(
                    kind: .option,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: true,
                    preferredName: DumpNameInfo(kind: .long, name: "tag")
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Process items")
        let properties = tool.inputSchema.objectValue!["properties"]!.objectValue!
        let tag = properties["tag"]!.objectValue!

        #expect(tag["type"]?.stringValue == "array")
        #expect(tag["items"]?.objectValue?["type"]?.stringValue == "string")
    }

    @Test func buildToolFiltersHelpAndVersion() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "cmd",
            arguments: [
                DumpArgumentInfo(
                    kind: .flag,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: false,
                    preferredName: DumpNameInfo(kind: .long, name: "help")
                ),
                DumpArgumentInfo(
                    kind: .flag,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: false,
                    preferredName: DumpNameInfo(kind: .long, name: "version")
                ),
                DumpArgumentInfo(
                    kind: .positional,
                    shouldDisplay: true,
                    isOptional: false,
                    isRepeating: false,
                    valueName: "input",
                    abstract: "Input file."
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Cmd")
        let properties = tool.inputSchema.objectValue!["properties"]!.objectValue!

        #expect(properties["help"] == nil)
        #expect(properties["version"] == nil)
        #expect(properties["input"] != nil)
    }

    @Test func buildToolWithNoArguments() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "ping"
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Ping")
        let schema = tool.inputSchema.objectValue!

        #expect(schema["properties"]?.objectValue?.isEmpty == true)
        #expect(schema["required"] == nil)
    }

    @Test func buildToolWithMixedArguments() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "deploy",
            arguments: [
                DumpArgumentInfo(
                    kind: .positional,
                    shouldDisplay: true,
                    isOptional: false,
                    isRepeating: false,
                    valueName: "target",
                    abstract: "Deploy target."
                ),
                DumpArgumentInfo(
                    kind: .option,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: false,
                    preferredName: DumpNameInfo(kind: .long, name: "environment"),
                    defaultValue: "staging"
                ),
                DumpArgumentInfo(
                    kind: .flag,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: false,
                    preferredName: DumpNameInfo(kind: .long, name: "dry-run")
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Deploy")
        let schema = tool.inputSchema.objectValue!
        let properties = schema["properties"]!.objectValue!

        #expect(properties.count == 3)
        #expect(properties["target"]?.objectValue?["type"]?.stringValue == "string")
        #expect(properties["environment"]?.objectValue?["type"]?.stringValue == "string")
        #expect(properties["environment"]?.objectValue?["default"]?.stringValue == "staging")
        #expect(properties["dry-run"]?.objectValue?["type"]?.stringValue == "boolean")
        #expect(properties["dry-run"]?.objectValue?["default"]?.boolValue == false)

        let required = schema["required"]!.arrayValue!.compactMap(\.stringValue)
        #expect(required == ["target"])
    }

    @Test func buildToolFlagDefaultValue() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "cmd",
            arguments: [
                DumpArgumentInfo(
                    kind: .flag,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: false,
                    preferredName: DumpNameInfo(kind: .long, name: "force"),
                    defaultValue: "false"
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Cmd")
        let properties = tool.inputSchema.objectValue!["properties"]!.objectValue!
        let force = properties["force"]!.objectValue!

        #expect(force["default"]?.boolValue == false)
    }

    // MARK: - Type Inference

    @Test func optionWithIntegerDefaultUsesIntegerType() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "run",
            arguments: [
                DumpArgumentInfo(
                    kind: .option,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: false,
                    preferredName: DumpNameInfo(kind: .long, name: "count"),
                    defaultValue: "2"
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Run")
        let count = tool.inputSchema.objectValue!["properties"]!.objectValue!["count"]!.objectValue!

        #expect(count["type"]?.stringValue == "integer")
        #expect(count["default"]?.intValue == 2)
    }

    @Test func optionWithFloatDefaultUsesNumberType() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "scale",
            arguments: [
                DumpArgumentInfo(
                    kind: .option,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: false,
                    preferredName: DumpNameInfo(kind: .long, name: "ratio"),
                    defaultValue: "1.5"
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Scale")
        let ratio = tool.inputSchema.objectValue!["properties"]!.objectValue!["ratio"]!.objectValue!

        #expect(ratio["type"]?.stringValue == "number")
        #expect(ratio["default"]?.doubleValue == 1.5)
    }

    @Test func optionWithBooleanDefaultUsesBooleanType() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "build",
            arguments: [
                DumpArgumentInfo(
                    kind: .option,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: false,
                    preferredName: DumpNameInfo(kind: .long, name: "cached"),
                    defaultValue: "true"
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Build")
        let cached = tool.inputSchema.objectValue!["properties"]!.objectValue!["cached"]!.objectValue!

        #expect(cached["type"]?.stringValue == "boolean")
        #expect(cached["default"]?.boolValue == true)
    }

    @Test func optionWithStringDefaultStaysString() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "deploy",
            arguments: [
                DumpArgumentInfo(
                    kind: .option,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: false,
                    preferredName: DumpNameInfo(kind: .long, name: "environment"),
                    defaultValue: "staging"
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Deploy")
        let env = tool.inputSchema.objectValue!["properties"]!.objectValue!["environment"]!.objectValue!

        #expect(env["type"]?.stringValue == "string")
        #expect(env["default"]?.stringValue == "staging")
    }

    @Test func optionWithoutDefaultStaysString() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "run",
            arguments: [
                DumpArgumentInfo(
                    kind: .option,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: false,
                    preferredName: DumpNameInfo(kind: .long, name: "count")
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Run")
        let count = tool.inputSchema.objectValue!["properties"]!.objectValue!["count"]!.objectValue!

        #expect(count["type"]?.stringValue == "string")
        #expect(count["default"] == nil)
    }

    @Test func optionWithIntegerEnumValuesUsesIntegerType() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "config",
            arguments: [
                DumpArgumentInfo(
                    kind: .option,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: false,
                    preferredName: DumpNameInfo(kind: .long, name: "level"),
                    defaultValue: "1",
                    allValues: ["0", "1", "2", "3"]
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Config")
        let level = tool.inputSchema.objectValue!["properties"]!.objectValue!["level"]!.objectValue!

        #expect(level["type"]?.stringValue == "integer")
        #expect(level["default"]?.intValue == 1)

        let enumValues = level["enum"]!.arrayValue!.compactMap(\.intValue)
        #expect(enumValues == [0, 1, 2, 3])
    }

    @Test func optionWithMixedEnumValuesFallsBackToString() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "config",
            arguments: [
                DumpArgumentInfo(
                    kind: .option,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: false,
                    preferredName: DumpNameInfo(kind: .long, name: "mode"),
                    defaultValue: "auto",
                    allValues: ["auto", "1", "2"]
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Config")
        let mode = tool.inputSchema.objectValue!["properties"]!.objectValue!["mode"]!.objectValue!

        #expect(mode["type"]?.stringValue == "string")
        #expect(mode["default"]?.stringValue == "auto")

        let enumValues = mode["enum"]!.arrayValue!.compactMap(\.stringValue)
        #expect(enumValues == ["auto", "1", "2"])
    }

    @Test func repeatingOptionInheritsInferredItemType() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "ports",
            arguments: [
                DumpArgumentInfo(
                    kind: .option,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: true,
                    preferredName: DumpNameInfo(kind: .long, name: "port"),
                    allValues: ["80", "443", "8080"]
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Ports")
        let port = tool.inputSchema.objectValue!["properties"]!.objectValue!["port"]!.objectValue!

        #expect(port["type"]?.stringValue == "array")
        #expect(port["items"]?.objectValue?["type"]?.stringValue == "integer")

        let enumValues = port["enum"]!.arrayValue!.compactMap(\.intValue)
        #expect(enumValues == [80, 443, 8080])
    }

    @Test func positionalWithNumericDefaultUsesNumberType() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "wait",
            arguments: [
                DumpArgumentInfo(
                    kind: .positional,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: false,
                    valueName: "seconds",
                    defaultValue: "0.25"
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Wait")
        let seconds = tool.inputSchema.objectValue!["properties"]!.objectValue!["seconds"]!.objectValue!

        #expect(seconds["type"]?.stringValue == "number")
        #expect(seconds["default"]?.doubleValue == 0.25)
    }

    @Test func optionWithBooleanEnumAndUnparseableDefaultOmitsDefault() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "build",
            arguments: [
                DumpArgumentInfo(
                    kind: .option,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: false,
                    preferredName: DumpNameInfo(kind: .long, name: "cached"),
                    defaultValue: "yes",
                    allValues: ["true", "false"]
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Build")
        let cached = tool.inputSchema.objectValue!["properties"]!.objectValue!["cached"]!.objectValue!

        #expect(cached["type"]?.stringValue == "boolean")
        #expect(cached["default"] == nil)
    }

    @Test func optionWithIntegerEnumAndUnparseableDefaultOmitsDefault() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "config",
            arguments: [
                DumpArgumentInfo(
                    kind: .option,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: false,
                    preferredName: DumpNameInfo(kind: .long, name: "level"),
                    defaultValue: "auto",
                    allValues: ["0", "1", "2"]
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Config")
        let level = tool.inputSchema.objectValue!["properties"]!.objectValue!["level"]!.objectValue!

        #expect(level["type"]?.stringValue == "integer")
        #expect(level["default"] == nil)
    }

    @Test func enumValuesPreferIntegerOverNumber() {
        let command = DumpCommandInfo(
            superCommands: ["root"],
            commandName: "cmd",
            arguments: [
                DumpArgumentInfo(
                    kind: .option,
                    shouldDisplay: true,
                    isOptional: true,
                    isRepeating: false,
                    preferredName: DumpNameInfo(kind: .long, name: "value"),
                    allValues: ["1", "2", "3"]
                ),
            ]
        )

        let tool = schemaBuilder.buildTool(from: command, description: "Cmd")
        let value = tool.inputSchema.objectValue!["properties"]!.objectValue!["value"]!.objectValue!

        #expect(value["type"]?.stringValue == "integer")

        let enumValues = value["enum"]!.arrayValue!.compactMap(\.intValue)
        #expect(enumValues == [1, 2, 3])
    }
}
