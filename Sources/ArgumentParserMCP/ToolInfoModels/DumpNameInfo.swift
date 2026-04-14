import Foundation

struct DumpNameInfo: Decodable, Sendable {

    let kind: NameKind
    let name: String

    enum NameKind: String, Decodable, Sendable {
        case long
        case short
        case longWithSingleDash
    }
}
