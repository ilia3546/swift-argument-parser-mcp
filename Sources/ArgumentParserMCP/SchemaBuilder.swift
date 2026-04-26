import MCP

final class SchemaBuilder: Sendable {

    // MARK: - Internal

    func buildTool(
        from command: DumpCommandInfo,
        description: String
    ) -> Tool {
        let arguments = (command.arguments ?? []).filter { shouldInclude($0) }

        var properties: [String: Value] = [:]
        var required: [Value] = []

        for argument in arguments {
            let (name, schema) = propertySchema(for: argument)
            properties[name] = schema
            if !argument.isOptional {
                required.append(.string(name))
            }
        }

        var schemaFields: [String: Value] = [
            "type": .string("object"),
            "properties": .object(properties),
        ]

        if !required.isEmpty {
            schemaFields["required"] = .array(required)
        }

        return Tool(
            name: toolName(for: command),
            description: description,
            inputSchema: .object(schemaFields)
        )
    }

    func toolName(for command: DumpCommandInfo) -> String {
        var parts = command.superCommands ?? []
        parts.append(command.commandName)
        if parts.count > 1 {
            parts.removeFirst()
        }
        return parts.joined(separator: "_")
    }

    func shouldInclude(_ argument: DumpArgumentInfo) -> Bool {
        guard argument.shouldDisplay else { return false }

        if let preferred = argument.preferredName {
            if preferred.name == "help" || preferred.name == "version" {
                return false
            }
        }
        return true
    }

    // MARK: - Private

    func propertySchema(for argument: DumpArgumentInfo) -> (String, Value) {
        let name = parameterName(for: argument)
        var schema: [String: Value] = [:]

        let inferredType = inferType(for: argument)

        switch argument.kind {
        case .flag:
            schema["type"] = .string("boolean")

        case .option, .positional:
            if argument.isRepeating {
                schema["type"] = .string("array")
                schema["items"] = .object(["type": .string(inferredType.schemaTypeName)])
            } else {
                schema["type"] = .string(inferredType.schemaTypeName)
            }
        }

        if let abstract = argument.abstract {
            schema["description"] = .string(abstract)
        }

        if let enumValues = enumValues(for: argument, type: inferredType) {
            schema["enum"] = .array(enumValues)
        }

        switch argument.kind {
        case .flag:
            schema["default"] = .bool(argument.defaultValue == "true")

        case .option, .positional:
            if let defaultValue = defaultSchemaValue(for: argument, type: inferredType) {
                schema["default"] = defaultValue
            }
        }

        return (name, .object(schema))
    }

    func inferType(for argument: DumpArgumentInfo) -> InferredType {
        if argument.kind == .flag {
            return .boolean
        }

        if let allValues = argument.allValues, !allValues.isEmpty {
            return uniformType(of: allValues) ?? .string
        }

        if let defaultValue = argument.defaultValue {
            return scalarType(of: defaultValue) ?? .string
        }

        return .string
    }

    private func enumValues(for argument: DumpArgumentInfo, type: InferredType) -> [Value]? {
        guard let allValues = argument.allValues, !allValues.isEmpty else { return nil }
        return allValues.map { schemaValue(from: $0, as: type) ?? .string($0) }
    }

    private func defaultSchemaValue(for argument: DumpArgumentInfo, type: InferredType) -> Value? {
        guard let raw = argument.defaultValue else { return nil }
        return schemaValue(from: raw, as: type)
    }

    private func schemaValue(from raw: String, as type: InferredType) -> Value? {
        switch type {
        case .integer:
            return Int(raw).map { .int($0) }
        case .number:
            return Double(raw).map { .double($0) }
        case .boolean:
            if raw == "true" { return .bool(true) }
            if raw == "false" { return .bool(false) }
            return nil
        case .string:
            return .string(raw)
        }
    }

    private func uniformType(of values: [String]) -> InferredType? {
        if values.allSatisfy({ Int($0) != nil }) { return .integer }
        if values.allSatisfy({ Double($0) != nil }) { return .number }
        if values.allSatisfy({ $0 == "true" || $0 == "false" }) { return .boolean }
        return nil
    }

    private func scalarType(of value: String) -> InferredType? {
        if Int(value) != nil { return .integer }
        if Double(value) != nil { return .number }
        if value == "true" || value == "false" { return .boolean }
        return nil
    }
}

enum InferredType: Sendable {
    case string
    case integer
    case number
    case boolean

    var schemaTypeName: String {
        switch self {
        case .string: return "string"
        case .integer: return "integer"
        case .number: return "number"
        case .boolean: return "boolean"
        }
    }
}

func parameterName(for argument: DumpArgumentInfo) -> String {
    switch argument.kind {
    case .option, .flag:
        if let preferred = argument.preferredName {
            return preferred.name
        }
        if let longName = argument.names?.first(where: { $0.kind == .long }) {
            return longName.name
        }
        return argument.valueName ?? "unknown"

    case .positional:
        return argument.valueName ?? "arg"
    }
}
