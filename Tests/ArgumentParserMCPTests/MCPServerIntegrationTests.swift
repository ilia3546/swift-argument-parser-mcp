import Testing

/// End-to-end MCP protocol tests.
///
/// These tests spawn the built `demo-cli` binary with the `mcp` subcommand,
/// drive it as a JSON-RPC client over stdio, and assert that the
/// `initialize` → `tools/list` → `tools/call` cycle behaves correctly.
/// They cover the wiring inside `MCPServer.start()` that unit tests on
/// `SchemaBuilder` / `ArgumentConverter` cannot reach: executable
/// resolution, `--experimental-dump-help` introspection, JSON-RPC
/// dispatch, subprocess invocation, and result formatting.
@Suite("MCP Server Integration", .serialized)
struct MCPServerIntegrationTests {

    // MARK: - initialize

    @Test func initializeReturnsServerInfo() async throws {
        let client = try MCPProcessClient.launch()
        defer { client.terminate() }

        let result = try await client.initializeHandshake()

        let serverInfo = try result.requireObject(at: "serverInfo")
        #expect(serverInfo["name"] as? String == "demo-cli")
        // `protocolVersion` should be one of the spec-listed dates;
        // we only check that the server echoes a non-empty string.
        let version = try result.requireString(at: "protocolVersion")
        #expect(!version.isEmpty)
    }

    // MARK: - tools/list

    @Test func toolsListIncludesEveryRegisteredCommand() async throws {
        let client = try MCPProcessClient.launch()
        defer { client.terminate() }
        _ = try await client.initializeHandshake()

        let response = try await client.send(method: "tools/list")
        let tools = try response.requireResult().requireArray(at: "tools")
        let names = try tools.map { try $0.requireString(at: "name") }.sorted()

        #expect(names == [
            "deploy",
            "echo",
            "fail",
            "flood",
            "greet",
            "math_add",
            "math_multiply",
            "noisy",
            "repeat-phrase",
            "sleep",
            "tag",
        ])
    }

    @Test func toolsListExposesInputSchemas() async throws {
        let client = try MCPProcessClient.launch()
        defer { client.terminate() }
        _ = try await client.initializeHandshake()

        let response = try await client.send(method: "tools/list")
        let tools = try response.requireResult().requireArray(at: "tools")

        let echoTool = try #require(tools.first { ($0["name"] as? String) == "echo" })
        let echoSchema = try echoTool.requireObject(at: "inputSchema")
        #expect(echoSchema["type"] as? String == "object")

        let echoProps = try echoSchema.requireObject(at: "properties")
        let wordsProp = try echoProps.requireObject(at: "words")
        #expect(wordsProp["type"] as? String == "array")

        let greetTool = try #require(tools.first { ($0["name"] as? String) == "greet" })
        let greetSchema = try greetTool.requireObject(at: "inputSchema")
        let required = greetSchema["required"] as? [String] ?? []
        #expect(required.contains("name"))
    }

    // MARK: - tools/call: happy paths

    @Test func callsEchoToolAndReceivesJoinedOutput() async throws {
        let client = try MCPProcessClient.launch()
        defer { client.terminate() }
        _ = try await client.initializeHandshake()

        let response = try await client.send(
            method: "tools/call",
            params: [
                "name": "echo",
                "arguments": ["words": ["hello", "world"]],
            ]
        )

        let result = try response.requireResult()
        #expect(result["isError"] as? Bool == false)

        let text = try result.firstTextContent()
        #expect(text == "hello world")

        let structured = try result.requireObject(at: "structuredContent")
        #expect(structured["exitCode"] as? Int == 0)
        #expect(structured["terminationReason"] as? String == "exit")
        #expect(structured["stdout"] as? String == "hello world\n")
    }

    @Test func callsNestedSubcommandViaUnderscoreToolName() async throws {
        let client = try MCPProcessClient.launch()
        defer { client.terminate() }
        _ = try await client.initializeHandshake()

        let response = try await client.send(
            method: "tools/call",
            params: [
                "name": "math_add",
                "arguments": ["numbers": [1.5, 2.5, 4.0]],
            ]
        )

        let result = try response.requireResult()
        #expect(result["isError"] as? Bool == false)
        let text = try result.firstTextContent()
        // Allow both "8.0" and "8" depending on Double formatting.
        #expect(text.hasPrefix("8"))
    }

    @Test func passesRepeatingOptionMultipleTimes() async throws {
        let client = try MCPProcessClient.launch()
        defer { client.terminate() }
        _ = try await client.initializeHandshake()

        let response = try await client.send(
            method: "tools/call",
            params: [
                "name": "tag",
                "arguments": [
                    "tag": ["alpha", "beta"],
                    "message": "hello",
                ],
            ]
        )

        let text = try response.requireResult().firstTextContent()
        #expect(text == "[alpha] [beta] hello")
    }

    @Test func passesEnumOptionAndFlag() async throws {
        let client = try MCPProcessClient.launch()
        defer { client.terminate() }
        _ = try await client.initializeHandshake()

        let response = try await client.send(
            method: "tools/call",
            params: [
                "name": "greet",
                "arguments": [
                    "name": "Ada",
                    "language": "es",
                    "shout": true,
                ],
            ]
        )

        let text = try response.requireResult().firstTextContent()
        #expect(text == "HOLA, ADA!")
    }

    @Test func appliesTransformArgumentsForDeployCommand() async throws {
        let client = try MCPProcessClient.launch()
        defer { client.terminate() }
        _ = try await client.initializeHandshake()

        let response = try await client.send(
            method: "tools/call",
            params: [
                "name": "deploy",
                "arguments": ["environment": "production"],
            ]
        )

        let result = try response.requireResult()
        #expect(result["isError"] as? Bool == false)
        let text = try result.firstTextContent()
        // `Deploy.transformArguments` injects --non-interactive so the
        // command takes the deploying branch instead of prompting.
        #expect(text.contains("Deploying to production"))
        #expect(text.contains("non-interactive=true"))
    }

    // MARK: - tools/call: error paths

    @Test func surfacesNonZeroExitCodeAsIsError() async throws {
        let client = try MCPProcessClient.launch()
        defer { client.terminate() }
        _ = try await client.initializeHandshake()

        let response = try await client.send(
            method: "tools/call",
            params: [
                "name": "fail",
                "arguments": [
                    "exit-code": 7,
                    "message": "boom",
                ],
            ]
        )

        let result = try response.requireResult()
        #expect(result["isError"] as? Bool == true)

        let structured = try result.requireObject(at: "structuredContent")
        #expect(structured["exitCode"] as? Int == 7)
        #expect(structured["terminationReason"] as? String == "exit")
        #expect((structured["stderr"] as? String)?.contains("boom") == true)
    }

    @Test func unknownToolNameReturnsJSONRPCError() async throws {
        let client = try MCPProcessClient.launch()
        defer { client.terminate() }
        _ = try await client.initializeHandshake()

        let response = try await client.send(
            method: "tools/call",
            params: [
                "name": "does-not-exist",
                "arguments": [String: Any](),
            ]
        )

        // Server should reject with a JSON-RPC error envelope, not a result.
        #expect(response["result"] == nil)
        let error = try response.requireObject(at: "error")
        #expect((error["message"] as? String)?.contains("does-not-exist") == true)
    }
}
