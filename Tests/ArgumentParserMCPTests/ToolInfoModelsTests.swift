import Foundation
import Testing

@testable import ArgumentParserMCP

@Suite("ToolInfoModels")
struct ToolInfoModelsTests {

    // MARK: - DumpHelpOutput

    @Test func decodesMinimalDumpHelp() throws {
        let json = """
        {
            "serializationVersion": 0,
            "command": {
                "commandName": "my-tool"
            }
        }
        """
        let output = try JSONDecoder().decode(DumpHelpOutput.self, from: Data(json.utf8))

        #expect(output.serializationVersion == 0)
        #expect(output.command.commandName == "my-tool")
        #expect(output.command.abstract == nil)
        #expect(output.command.subcommands == nil)
        #expect(output.command.arguments == nil)
    }

    @Test func decodesFullCommandInfo() throws {
        let json = """
        {
            "serializationVersion": 0,
            "command": {
                "commandName": "root",
                "abstract": "Root command",
                "discussion": "Detailed discussion",
                "shouldDisplay": true,
                "aliases": ["r"],
                "defaultSubcommand": "sub",
                "superCommands": [],
                "subcommands": [
                    {
                        "commandName": "sub",
                        "abstract": "Subcommand",
                        "superCommands": ["root"]
                    }
                ],
                "arguments": [
                    {
                        "kind": "flag",
                        "shouldDisplay": true,
                        "isOptional": true,
                        "isRepeating": false
                    }
                ]
            }
        }
        """
        let output = try JSONDecoder().decode(DumpHelpOutput.self, from: Data(json.utf8))
        let cmd = output.command

        #expect(cmd.commandName == "root")
        #expect(cmd.abstract == "Root command")
        #expect(cmd.discussion == "Detailed discussion")
        #expect(cmd.shouldDisplay == true)
        #expect(cmd.aliases == ["r"])
        #expect(cmd.defaultSubcommand == "sub")
        #expect(cmd.subcommands?.count == 1)
        #expect(cmd.subcommands?.first?.commandName == "sub")
        #expect(cmd.subcommands?.first?.superCommands == ["root"])
        #expect(cmd.arguments?.count == 1)
    }

    // MARK: - DumpArgumentInfo

    @Test func decodesPositionalArgument() throws {
        let json = """
        {
            "kind": "positional",
            "shouldDisplay": true,
            "isOptional": false,
            "isRepeating": false,
            "valueName": "phrase",
            "abstract": "The phrase to repeat."
        }
        """
        let arg = try JSONDecoder().decode(DumpArgumentInfo.self, from: Data(json.utf8))

        #expect(arg.kind == .positional)
        #expect(arg.shouldDisplay == true)
        #expect(arg.isOptional == false)
        #expect(arg.isRepeating == false)
        #expect(arg.valueName == "phrase")
        #expect(arg.abstract == "The phrase to repeat.")
        #expect(arg.names == nil)
        #expect(arg.preferredName == nil)
    }

    @Test func decodesOptionArgument() throws {
        let json = """
        {
            "kind": "option",
            "shouldDisplay": true,
            "isOptional": true,
            "isRepeating": false,
            "names": [
                {"kind": "short", "name": "c"},
                {"kind": "long", "name": "count"}
            ],
            "preferredName": {"kind": "long", "name": "count"},
            "valueName": "count",
            "defaultValue": "2",
            "abstract": "Number of repetitions."
        }
        """
        let arg = try JSONDecoder().decode(DumpArgumentInfo.self, from: Data(json.utf8))

        #expect(arg.kind == .option)
        #expect(arg.isOptional == true)
        #expect(arg.names?.count == 2)
        #expect(arg.names?.first?.kind == .short)
        #expect(arg.names?.first?.name == "c")
        #expect(arg.preferredName?.kind == .long)
        #expect(arg.preferredName?.name == "count")
        #expect(arg.defaultValue == "2")
    }

    @Test func decodesFlagArgument() throws {
        let json = """
        {
            "kind": "flag",
            "shouldDisplay": true,
            "isOptional": true,
            "isRepeating": false,
            "names": [{"kind": "long", "name": "verbose"}],
            "preferredName": {"kind": "long", "name": "verbose"}
        }
        """
        let arg = try JSONDecoder().decode(DumpArgumentInfo.self, from: Data(json.utf8))

        #expect(arg.kind == .flag)
        #expect(arg.preferredName?.name == "verbose")
    }

    @Test func decodesOptionWithEnumValues() throws {
        let json = """
        {
            "kind": "option",
            "shouldDisplay": true,
            "isOptional": true,
            "isRepeating": false,
            "preferredName": {"kind": "long", "name": "format"},
            "allValues": ["json", "yaml", "text"],
            "defaultValue": "json"
        }
        """
        let arg = try JSONDecoder().decode(DumpArgumentInfo.self, from: Data(json.utf8))

        #expect(arg.allValues == ["json", "yaml", "text"])
        #expect(arg.defaultValue == "json")
    }

    @Test func decodesRepeatingArgument() throws {
        let json = """
        {
            "kind": "positional",
            "shouldDisplay": true,
            "isOptional": true,
            "isRepeating": true,
            "valueName": "files"
        }
        """
        let arg = try JSONDecoder().decode(DumpArgumentInfo.self, from: Data(json.utf8))

        #expect(arg.isRepeating == true)
    }

    @Test func decodesNameKinds() throws {
        let longDash = try JSONDecoder().decode(
            DumpNameInfo.self,
            from: Data(#"{"kind":"longWithSingleDash","name":"verbose"}"#.utf8)
        )
        #expect(longDash.kind == .longWithSingleDash)
        #expect(longDash.name == "verbose")
    }
}
