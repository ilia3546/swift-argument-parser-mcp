import Foundation

struct DumpCommandInfo: Decodable, Sendable {

    let superCommands: [String]?
    let shouldDisplay: Bool?
    let commandName: String
    let aliases: [String]?
    let abstract: String?
    let discussion: String?
    let defaultSubcommand: String?
    let subcommands: [DumpCommandInfo]?
    let arguments: [DumpArgumentInfo]?

    init(
        superCommands: [String]? = nil,
        shouldDisplay: Bool? = nil,
        commandName: String,
        aliases: [String]? = nil,
        abstract: String? = nil,
        discussion: String? = nil,
        defaultSubcommand: String? = nil,
        subcommands: [DumpCommandInfo]? = nil,
        arguments: [DumpArgumentInfo]? = nil
    ) {
        self.superCommands = superCommands
        self.shouldDisplay = shouldDisplay
        self.commandName = commandName
        self.aliases = aliases
        self.abstract = abstract
        self.discussion = discussion
        self.defaultSubcommand = defaultSubcommand
        self.subcommands = subcommands
        self.arguments = arguments
    }
}
