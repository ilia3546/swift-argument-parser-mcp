import Foundation
import ArgumentParser
import MCP

/// An MCP server that exposes `MCPCommand`-conforming CLI subcommands as tools.
///
/// The server introspects the current executable via `--experimental-dump-help`,
/// builds MCP tool definitions from the parsed argument info, and dispatches
/// incoming tool calls by invoking the same executable with the appropriate subcommand.
///
/// ```swift
/// let server = MCPServer(
///     name: "my-cli",
///     version: "1.0.0",
///     commands: [MyCommand.self]
/// )
/// try await server.start()
/// ```
public struct MCPServer: Sendable {

    private let name: String
    private let version: String
    private let commands: [any MCPCommand.Type]
    private let globalArguments: [String]

    public init(
        name: String,
        version: String,
        commands: [any MCPCommand.Type],
        globalArguments: [String] = []
    ) {
        self.name = name
        self.version = version
        self.commands = commands
        self.globalArguments = globalArguments
    }

    public func start() async throws {
        let executablePath = resolveExecutablePath()

        let dumpResult = try await ProcessRunner.run(
            executablePath: executablePath,
            arguments: ["--experimental-dump-help"]
        )

        guard dumpResult.exitCode == 0 else {
            throw MCPServerError.dumpHelpFailed(
                stderr: dumpResult.stderr,
                exitCode: dumpResult.exitCode
            )
        }

        guard let jsonData = dumpResult.stdout.data(using: .utf8) else {
            throw MCPServerError.invalidDumpHelpOutput
        }

        let toolInfo = try JSONDecoder().decode(DumpHelpOutput.self, from: jsonData)
        let registrations = try buildRegistrations(from: toolInfo.command)

        let tools = registrations.map { reg in
            SchemaBuilder.buildTool(
                from: reg.commandInfo,
                description: reg.commandType.mcpDescription
            )
        }

        let server = Server(
            name: name,
            version: version,
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            guard let reg = registrations.first(where: {
                SchemaBuilder.toolName(for: $0.commandInfo) == params.name
            }) else {
                throw MCPError.invalidParams("Unknown tool: \(params.name)")
            }

            let subcommandPath = buildSubcommandPath(for: reg.commandInfo)
            let cliArgs = ArgumentConverter.convert(
                arguments: params.arguments ?? [:],
                using: reg.commandInfo.arguments ?? []
            )
            let transformedArgs = reg.commandType.transformArguments(cliArgs)

            let result = try await ProcessRunner.run(
                executablePath: executablePath,
                arguments: subcommandPath + transformedArgs + globalArguments
            )

            if result.exitCode != 0 {
                let errorOutput = result.stderr.isEmpty ? result.stdout : result.stderr
                return .init(
                    content: [.text(text: errorOutput.trimmed, annotations: nil, _meta: nil)],
                    isError: true
                )
            }

            let output = result.stdout.trimmed
            return .init(
                content: [.text(text: output.isEmpty ? "(no output)" : output, annotations: nil, _meta: nil)]
            )
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    // MARK: - Private

    private struct CommandRegistration: Sendable {
        let commandType: any MCPCommand.Type
        let commandInfo: DumpCommandInfo
    }

    private func resolveExecutablePath() -> String {
        URL(fileURLWithPath: CommandLine.arguments[0]).standardized.path
    }

    private func buildRegistrations(
        from rootCommand: DumpCommandInfo
    ) throws -> [CommandRegistration] {
        try commands.map { commandType in
            let commandName = commandType._commandName
            guard let info = findCommand(named: commandName, in: rootCommand) else {
                throw MCPServerError.commandNotFound(commandName)
            }
            return CommandRegistration(commandType: commandType, commandInfo: info)
        }
    }

    private func findCommand(
        named name: String,
        in command: DumpCommandInfo
    ) -> DumpCommandInfo? {
        if command.commandName == name {
            return command
        }
        for subcommand in command.subcommands ?? [] {
            if let found = findCommand(named: name, in: subcommand) {
                return found
            }
        }
        return nil
    }

    private func buildSubcommandPath(for command: DumpCommandInfo) -> [String] {
        var path = command.superCommands ?? []
        path.append(command.commandName)
        if !path.isEmpty {
            path.removeFirst()
        }
        return path
    }
}

public enum MCPServerError: Error, CustomStringConvertible {

    case dumpHelpFailed(stderr: String, exitCode: Int32)
    case invalidDumpHelpOutput
    case commandNotFound(String)

    public var description: String {
        switch self {
        case .dumpHelpFailed(let stderr, let exitCode):
            "Failed to dump help (exit code \(exitCode)): \(stderr)"
        case .invalidDumpHelpOutput:
            "Could not decode --experimental-dump-help output"
        case .commandNotFound(let name):
            "Command '\(name)' not found in CLI tool structure"
        }
    }
}

private extension String {

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
