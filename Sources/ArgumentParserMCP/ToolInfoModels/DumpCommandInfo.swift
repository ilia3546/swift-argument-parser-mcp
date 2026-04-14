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
}
