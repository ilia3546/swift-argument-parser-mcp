import Foundation

struct DumpHelpOutput: Decodable, Sendable {

    var serializationVersion: Int
    var command: DumpCommandInfo
}

struct DumpCommandInfo: Decodable, Sendable {

    var superCommands: [String]?
    var shouldDisplay: Bool?
    var commandName: String
    var aliases: [String]?
    var abstract: String?
    var discussion: String?
    var defaultSubcommand: String?
    var subcommands: [DumpCommandInfo]?
    var arguments: [DumpArgumentInfo]?
}

struct DumpArgumentInfo: Decodable, Sendable {

    var kind: ArgumentKind
    var shouldDisplay: Bool
    var isOptional: Bool
    var isRepeating: Bool
    var names: [DumpNameInfo]?
    var preferredName: DumpNameInfo?
    var valueName: String?
    var defaultValue: String?
    var allValues: [String]?
    var abstract: String?
    var discussion: String?

    enum ArgumentKind: String, Decodable, Sendable {
        case positional
        case option
        case flag
    }
}

struct DumpNameInfo: Decodable, Sendable {

    var kind: NameKind
    var name: String

    enum NameKind: String, Decodable, Sendable {
        case long
        case short
        case longWithSingleDash
    }
}
