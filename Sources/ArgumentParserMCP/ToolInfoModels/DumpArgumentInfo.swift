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

    init(
        kind: ArgumentKind,
        shouldDisplay: Bool,
        isOptional: Bool,
        isRepeating: Bool,
        names: [DumpNameInfo]? = nil,
        preferredName: DumpNameInfo? = nil,
        valueName: String? = nil,
        defaultValue: String? = nil,
        allValues: [String]? = nil,
        abstract: String? = nil,
        discussion: String? = nil
    ) {
        self.kind = kind
        self.shouldDisplay = shouldDisplay
        self.isOptional = isOptional
        self.isRepeating = isRepeating
        self.names = names
        self.preferredName = preferredName
        self.valueName = valueName
        self.defaultValue = defaultValue
        self.allValues = allValues
        self.abstract = abstract
        self.discussion = discussion
    }

    enum ArgumentKind: String, Decodable, Sendable {
        case positional
        case option
        case flag
    }
}
