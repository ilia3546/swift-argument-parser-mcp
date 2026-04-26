import Foundation
import ArgumentParser
import MCP

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

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
    private let instructions: String?
    private let isStrict: Bool
    private let commands: [any MCPCommand.Type]
    private let globalArguments: [String]
    private let outputCapBytes: Int
    private let schemaBuilder = SchemaBuilder()
    private let argumentConverter = ArgumentConverter()
    private let processRunner = ProcessRunner()

    // MARK: - Initializers

    /// Creates a new ``MCPServer``.
    ///
    /// - Parameters:
    ///   - name: The server name exposed to MCP clients.
    ///   - version: The server version string exposed to MCP clients.
    ///   - commands: The ``MCPCommand``-conforming types to register as MCP tools.
    ///   - instructions: Optional guidance passed to MCP clients at the server level,
    ///     such as usage hints or context about the available tools.
    ///   - isStrict: When `true`, the underlying MCP server uses strict protocol validation.
    ///     Defaults to `false`.
    ///   - globalArguments: Arguments appended to every subprocess invocation.
    ///     Use this to pass flags such as `--verbose` or `--config-path` to all commands.
    ///   - outputCapBytes: Maximum number of bytes captured per stream (stdout / stderr)
    ///     for tool-call results. Output beyond the cap is dropped and the result's
    ///     `stdoutTruncated` / `stderrTruncated` fields are set. Defaults to 256 KiB.
    public init(
        name: String,
        version: String,
        commands: [any MCPCommand.Type],
        instructions: String? = nil,
        isStrict: Bool = false,
        globalArguments: [String] = [],
        outputCapBytes: Int = 256 * 1024
    ) {
        self.name = name
        self.version = version
        self.commands = commands
        self.instructions = instructions
        self.isStrict = isStrict
        self.globalArguments = globalArguments
        self.outputCapBytes = outputCapBytes
    }

    // MARK: - Public Methods

    /// Starts the MCP server and blocks until the connection is closed.
    ///
    /// On startup the server performs the following steps:
    /// 1. Resolves the path of the running binary using a platform-native API
    ///    (`_NSGetExecutablePath` on Darwin, `/proc/self/exe` on Linux).
    /// 2. Introspects the CLI by invoking the binary with `--experimental-dump-help`
    ///    and parsing the resulting JSON.
    /// 3. Builds an MCP ``Tool`` definition for every registered ``MCPCommand``,
    ///    generating a JSON Schema `inputSchema` from its arguments, options, and flags.
    /// 4. Listens for `tools/list` and `tools/call` requests over stdio.
    ///
    /// When a tool is called the server converts the JSON arguments back to CLI arguments
    /// and invokes the appropriate subcommand as a child process, returning its stdout as
    /// the tool result (or stderr on non-zero exit).
    ///
    /// - Throws: ``MCPServerError/unableToDetectCurrentExecutablePath`` if the path of the
    ///   running binary cannot be determined.
    /// - Throws: ``MCPServerError/dumpHelpFailed(stderr:exitCode:)`` if the
    ///   `--experimental-dump-help` invocation exits with a non-zero status.
    /// - Throws: ``MCPServerError/invalidDumpHelpOutput`` if the help output cannot be decoded.
    /// - Throws: ``MCPServerError/commandNotFound(_:)`` if a registered command is not
    ///   present in the CLI's command tree.
    public func start() async throws {
        let executablePath = try resolveExecutablePath()

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
            instructions: instructions,
            capabilities: Server.Capabilities(
                tools: Server.Capabilities.Tools(listChanged: false)
            ),
            configuration: isStrict ? .strict : .default
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: tools)
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
                arguments: subcommandPath + transformedArgs + globalArguments,
                perStreamCapBytes: outputCapBytes
            )

            return makeCallToolResult(from: result)
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    // MARK: - Private Methods

    private func resolveExecutablePath() throws -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
#if canImport(Darwin)
        var pathLength = UInt32(buffer.count)
        guard _NSGetExecutablePath(&buffer, &pathLength) == 0 else {
            throw MCPServerError.unableToDetectCurrentExecutablePath
        }
#else
        let length = readlink("/proc/self/exe", &buffer, buffer.count - 1)
        guard length > 0 else {
            throw MCPServerError.unableToDetectCurrentExecutablePath
        }
        buffer[Int(length)] = 0
#endif
        let endIndex = buffer.firstIndex(of: 0) ?? buffer.endIndex
        return buffer[..<endIndex].withUnsafeBytes { String(decoding: $0, as: UTF8.self) }
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

// MARK: - Result formatting

func makeCallToolResult(from result: ProcessRunner.Result) -> CallTool.Result {
    let trimmedLog = result.mergedLog.trimmingCharacters(in: .whitespacesAndNewlines)
    let textBlock = trimmedLog.isEmpty ? "(no output)" : trimmedLog

    let structured: Value? = .object([
        "stdout": .string(result.stdout),
        "stderr": .string(result.stderr),
        "exitCode": .int(Int(result.exitCode)),
        "terminationReason": .string(result.terminationReason.rawValue),
        "stdoutTruncated": .bool(result.stdoutTruncated),
        "stderrTruncated": .bool(result.stderrTruncated),
        "durationMs": .int(result.durationMs),
    ])

    let isError = result.terminationReason != .exit || result.exitCode != 0

    return CallTool.Result(
        content: [.text(text: textBlock, annotations: nil, _meta: nil)],
        structuredContent: structured,
        isError: isError
    )
}
