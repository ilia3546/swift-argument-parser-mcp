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

        switch argument.kind {
        case .flag:
            schema["type"] = .string("boolean")

        case .option, .positional:
            if argument.isRepeating {
                schema["type"] = .string("array")
                schema["items"] = .object(["type": .string("string")])
            } else {
                schema["type"] = .string("string")
            }
        }

        if let abstract = argument.abstract {
            schema["description"] = .string(abstract)
        }

        if let allValues = argument.allValues, !allValues.isEmpty {
            schema["enum"] = .array(allValues.map { .string($0) })
        }

        if let defaultValue = argument.defaultValue {
            switch argument.kind {
            case .flag:
                schema["default"] = .bool(defaultValue == "true")

            case .option, .positional:
                schema["default"] = .string(defaultValue)
            }
        }

        return (name, .object(schema))
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
