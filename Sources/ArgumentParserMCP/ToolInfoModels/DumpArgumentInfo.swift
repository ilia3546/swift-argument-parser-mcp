import Foundation

struct DumpArgumentInfo: Decodable, Sendable {

    let kind: ArgumentKind
    let shouldDisplay: Bool
    let isOptional: Bool
    let isRepeating: Bool
    let names: [DumpNameInfo]?
    let preferredName: DumpNameInfo?
    let valueName: String?
    let defaultValue: String?
    let allValues: [String]?
    let abstract: String?
    let discussion: String?

    enum ArgumentKind: String, Decodable, Sendable {
        case positional
        case option
        case flag
    }
}
