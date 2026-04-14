import MCP

final class ArgumentConverter: Sendable {

    // MARK: - Private Properties

    private let schemaBuilder = SchemaBuilder()

    // MARK: - Internal Methods

    func convert(
        arguments: [String: Value],
        using argInfos: [DumpArgumentInfo]
    ) -> [String] {
        let filtered = argInfos.filter { schemaBuilder.shouldInclude($0) }

        var cliArgs: [String] = []
        var positionalArgs: [(index: Int, value: String)] = []

        for (index, argInfo) in filtered.enumerated() {
            let name = parameterName(for: argInfo)
            guard let value = arguments[name] else { continue }

            switch argInfo.kind {
            case .flag:
                if case .bool(let boolVal) = value, boolVal {
                    cliArgs.append(cliName(for: argInfo))
                }

            case .option:
                if argInfo.isRepeating, let arrayVal = value.arrayValue {
                    for element in arrayVal {
                        cliArgs.append(cliName(for: argInfo))
                        cliArgs.append(stringValue(from: element))
                    }
                } else {
                    cliArgs.append(cliName(for: argInfo))
                    cliArgs.append(stringValue(from: value))
                }

            case .positional:
                if argInfo.isRepeating, let arrayVal = value.arrayValue {
                    for (offset, element) in arrayVal.enumerated() {
                        positionalArgs.append((index: index + offset, value: stringValue(from: element)))
                    }
                } else {
                    positionalArgs.append((index: index, value: stringValue(from: value)))
                }
            }
        }

        positionalArgs.sort { $0.index < $1.index }
        cliArgs.append(contentsOf: positionalArgs.map(\.value))

        return cliArgs
    }

    // MARK: - Private Methods

    private func cliName(for argument: DumpArgumentInfo) -> String {
        if let preferred = argument.preferredName {
            return formattedName(preferred)
        }
        if let first = argument.names?.first {
            return formattedName(first)
        }
        return "--\(argument.valueName ?? "unknown")"
    }

    private func formattedName(_ nameInfo: DumpNameInfo) -> String {
        switch nameInfo.kind {
        case .long:
            return "--\(nameInfo.name)"
        case .short:
            return "-\(nameInfo.name)"
        case .longWithSingleDash:
            return "-\(nameInfo.name)"
        }
    }

    private func stringValue(from value: Value) -> String {
        switch value {
        case .string(let s): s
        case .int(let i): String(i)
        case .double(let d): String(d)
        case .bool(let b): String(b)
        default: String(describing: value)
        }
    }
}
