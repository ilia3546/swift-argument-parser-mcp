import Foundation

struct DumpHelpOutput: Decodable, Sendable {

    let serializationVersion: Int
    let command: DumpCommandInfo
}
