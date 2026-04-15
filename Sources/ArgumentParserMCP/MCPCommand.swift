import ArgumentParser

/// A protocol that marks `ParsableCommand` types for exposure as MCP tools.
///
/// Conform your existing `ParsableCommand` to `MCPCommand` and register it
/// with `MCPServer` to make it available to AI agents via the Model Context Protocol.
///
/// ```swift
/// struct RepeatPhrase: ParsableCommand, MCPCommand {
///     @Argument var phrase: String
///     mutating func run() throws { print(phrase) }
/// }
/// ```
public protocol MCPCommand: ParsableCommand {

    /// Custom MCP tool description. When `nil`, the command's `abstract + \n + discussion` is used.
    static var mcpDescription: String { get }

    /// Intercept and transform CLI arguments before execution.
    ///
    /// Override this method to add, remove, or modify arguments passed to the CLI.
    /// The `arguments` array contains only the command's own arguments (without the subcommand path).
    ///
    /// ```swift
    /// extension MyCommand: MCPCommand {
    ///     static func transformArguments(_ arguments: [String]) -> [String] {
    ///         arguments + ["--verbose"]
    ///     }
    /// }
    /// ```
    static func transformArguments(_ arguments: [String]) -> [String]
}

extension MCPCommand {

    public static var mcpDescription: String {
        [configuration.abstract, configuration.discussion]
            .compactMap({ $0 })
            .joined(separator: "\n")
    }

    public static func transformArguments(_ arguments: [String]) -> [String] {
        arguments
    }
}
