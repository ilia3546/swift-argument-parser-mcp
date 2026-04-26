import MCP

final class ArgumentConverter: Sendable {

    // MARK: - Private Properties

    private let schemaBuilder = SchemaBuilder()

    // MARK: - Internal Methods

    func convert(
        arguments: [String: Value],
        using argInfos: [DumpArgumentInfo]
    ) throws -> [String] {
        let filtered = argInfos.filter { schemaBuilder.shouldInclude($0) }

        try validate(arguments: arguments, filtered: filtered)

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
                        cliArgs.append(try stringValue(from: element, argumentName: name))
                    }
                } else {
                    cliArgs.append(cliName(for: argInfo))
                    cliArgs.append(try stringValue(from: value, argumentName: name))
                }

            case .positional:
                if argInfo.isRepeating, let arrayVal = value.arrayValue {
                    for (offset, element) in arrayVal.enumerated() {
                        positionalArgs.append((index: index + offset, value: try stringValue(from: element, argumentName: name)))
                    }
                } else {
                    positionalArgs.append((index: index, value: try stringValue(from: value, argumentName: name)))
                }
            }
        }

        positionalArgs.sort { $0.index < $1.index }
        cliArgs.append(contentsOf: positionalArgs.map(\.value))

        return cliArgs
    }

    // MARK: - Validation

    private func validate(
        arguments: [String: Value],
        filtered: [DumpArgumentInfo]
    ) throws {
        var missingRequired: [String] = []

        for argInfo in filtered {
            let name = parameterName(for: argInfo)
            guard let value = arguments[name] else {
                if !argInfo.isOptional {
                    missingRequired.append(name)
                }
                continue
            }

            switch argInfo.kind {
            case .flag:
                guard case .bool = value else {
                    throw MCPError.invalidParams(
                        "Argument '\(name)' expects a boolean flag, got \(typeName(of: value))"
                    )
                }

            case .option, .positional:
                if argInfo.isRepeating {
                    guard let elements = value.arrayValue else {
                        throw MCPError.invalidParams(
                            "Argument '\(name)' expects an array, got \(typeName(of: value))"
                        )
                    }
                    for element in elements {
                        try requireScalar(element, argumentName: name)
                        try requireAllowedValue(element, argInfo: argInfo, argumentName: name)
                    }
                } else {
                    try requireScalar(value, argumentName: name)
                    try requireAllowedValue(value, argInfo: argInfo, argumentName: name)
                }
            }
        }

        if !missingRequired.isEmpty {
            let names = missingRequired.map { "'\($0)'" }.joined(separator: ", ")
            throw MCPError.invalidParams("Missing required argument(s): \(names)")
        }
    }

    private func requireScalar(_ value: Value, argumentName: String) throws {
        switch value {
        case .string, .int, .double, .bool:
            return
        default:
            throw MCPError.invalidParams(
                "Argument '\(argumentName)' expects a scalar value (string, integer, number, or boolean), got \(typeName(of: value))"
            )
        }
    }

    private func requireAllowedValue(
        _ value: Value,
        argInfo: DumpArgumentInfo,
        argumentName: String
    ) throws {
        guard let allowed = argInfo.allValues, !allowed.isEmpty else { return }
        let asString = try stringValue(from: value, argumentName: argumentName)
        guard allowed.contains(asString) else {
            let allowedList = allowed.map { "'\($0)'" }.joined(separator: ", ")
            throw MCPError.invalidParams(
                "Argument '\(argumentName)' value '\(asString)' is not one of the allowed values: \(allowedList)"
            )
        }
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

    private func stringValue(from value: Value, argumentName: String) throws -> String {
        switch value {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        default:
            throw MCPError.invalidParams(
                "Unsupported value for argument '\(argumentName)': \(typeName(of: value))"
            )
        }
    }

    private func typeName(of value: Value) -> String {
        switch value {
        case .string: return "string"
        case .int: return "integer"
        case .double: return "number"
        case .bool: return "boolean"
        case .array: return "array"
        case .object: return "object"
        default: return "unsupported"
        }
    }
}
