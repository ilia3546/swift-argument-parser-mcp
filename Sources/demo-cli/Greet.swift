import ArgumentParser
import ArgumentParserMCP

struct Greet: ParsableCommand, MCPCommand {

    static let configuration = CommandConfiguration(
        abstract: "Greet a person in a chosen language."
    )

    @Argument(help: "Name of the person to greet.")
    var name: String

    @Option(name: .shortAndLong, help: "Greeting language.")
    var language: GreetLanguage = .en

    @Option(help: "Optional title prefix, e.g. 'Dr.'.")
    var title: String? = nil

    @Option(name: .shortAndLong, help: "Number of exclamation points to append.")
    var exclamations: Int = 1

    @Flag(name: .shortAndLong, help: "Shout the greeting in upper case.")
    var shout: Bool = false

    mutating func run() throws {
        let prefix = title.map { "\($0) " } ?? ""
        let bangs = String(repeating: "!", count: max(0, exclamations))
        var line = "\(language.greeting), \(prefix)\(name)\(bangs)"
        if shout {
            line = line.uppercased()
        }
        print(line)
    }
}

enum GreetLanguage: String, ExpressibleByArgument, CaseIterable {

    case en
    case es
    case fr
    case de
    case ja

    var greeting: String {
        switch self {
        case .en: return "Hello"
        case .es: return "Hola"
        case .fr: return "Bonjour"
        case .de: return "Hallo"
        case .ja: return "こんにちは"
        }
    }
}
