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

    // MARK: - Private Properties

    private let name: String
    private let version: String
    private let commands: [any MCPCommand.Type]
    private let globalArguments: [String]
    private let schemaBuilder = SchemaBuilder()
    private let argumentConverter = ArgumentConverter()
    private let processRunner = ProcessRunner()

    // MARK: - Initializers

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

    // MARK: - Public Methods

    public func start() async throws {
        let executablePath = resolveExecutablePath()

        let dumpResult = try await processRunner.run(
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
            schemaBuilder.buildTool(
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
                schemaBuilder.toolName(for: $0.commandInfo) == params.name
            }) else {
                throw MCPError.invalidParams("Unknown tool: \(params.name)")
            }

            let subcommandPath = buildSubcommandPath(for: reg.commandInfo)
            let cliArgs = argumentConverter.convert(
                arguments: params.arguments ?? [:],
                using: reg.commandInfo.arguments ?? []
            )
            let transformedArgs = reg.commandType.transformArguments(cliArgs)

            let result = try await processRunner.run(
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

    // MARK: - Private Methods

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

// MARK: - CommandRegistration

private struct CommandRegistration: Sendable {
    let commandType: any MCPCommand.Type
    let commandInfo: DumpCommandInfo
}

// MARK: - String+trimmed

private extension String {

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
