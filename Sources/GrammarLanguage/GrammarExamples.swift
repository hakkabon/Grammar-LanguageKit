import Foundation
import Grammar
import IncrementalParsing
import Lexer
import LR_Parsing

public struct GrammarExample: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var input: String
    public var shouldAccept: Bool

    public init(id: String, input: String, shouldAccept: Bool) {
        self.id = id
        self.input = input
        self.shouldAccept = shouldAccept
    }
}

public struct GrammarExampleCorpus: Codable, Sendable {
    public let schemaVersion: Int
    public var examples: [GrammarExample]

    public init(examples: [GrammarExample]) {
        schemaVersion = 1
        self.examples = examples
    }

    public static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw Failure("Unsupported grammar example schema.") }
        guard !examples.isEmpty, examples.count <= 100 else {
            throw Failure("Provide between 1 and 100 grammar examples.")
        }
        guard examples.allSatisfy({ !$0.id.isEmpty && $0.input.utf16.count <= 16_384 }),
              Set(examples.map(\.id)).count == examples.count else {
            throw Failure("Examples need unique nonempty names and inputs of at most 16,384 UTF-16 units.")
        }
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

public struct GrammarExampleResult: Codable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case accepted, rejected, lexicalError, grammarConflict, limitReached
    }

    public let id: String
    public let shouldAccept: Bool
    public let status: Status
    public let message: String
    public let tree: String?

    public let passed: Bool

    init(id: String, shouldAccept: Bool, status: Status, message: String, tree: String?) {
        self.id = id
        self.shouldAccept = shouldAccept
        self.status = status
        self.message = message
        self.tree = tree
        passed = shouldAccept ? status == .accepted : status == .rejected || status == .lexicalError
    }
}

public struct GrammarExampleReport: Codable, Sendable {
    public let revision: UInt64
    public let grammarValid: Bool
    public let diagnostics: [LanguageProviderDiagnostic]
    public let affectedRules: [String]
    public let examples: [GrammarExampleResult]
    public let passed: Bool

    init(revision: UInt64, grammarValid: Bool, diagnostics: [LanguageProviderDiagnostic],
         affectedRules: [String], examples: [GrammarExampleResult]) {
        self.revision = revision
        self.grammarValid = grammarValid
        self.diagnostics = diagnostics
        self.affectedRules = affectedRules
        self.examples = examples
        passed = grammarValid && !examples.isEmpty && examples.allSatisfy(\.passed)
    }
}

enum GrammarExampleEvaluator {
    static func evaluate(_ examples: [GrammarExample], grammar: Grammar) throws -> [GrammarExampleResult] {
        let parser = LRParser(grammar: grammar, algorithm: .lalr)
        let automaton = parser.generate()
        if !automaton.unresolvedConflicts.isEmpty {
            return examples.map {
                .init(id: $0.id, shouldAccept: $0.shouldAccept, status: .grammarConflict,
                      message: "The grammar has unresolved LALR conflicts.", tree: nil)
            }
        }
        let table = parser.incrementalRuntimeTable()
        let (specification, names) = lexicalRules(for: grammar)
        let scanner = try GrammarDrivenLexer(specification: specification)
        return examples.map { example in
            var tokenizer = RestartAndConvergeTokenizer(scanner: scanner)
            let lexed = tokenizer.tokenize(snapshot: SourceSnapshot(text: example.input, revision: .init(1)))
            if let diagnostic = lexed.output.diagnostics.first {
                return .init(id: example.id, shouldAccept: example.shouldAccept, status: .lexicalError,
                             message: diagnostic.message, tree: nil)
            }
            let tokens = lexed.output.tokens.filter { !$0.isEndOfInput }.map { names[$0.kind] ?? $0.kind }
            let result = LRTableRuntime.parse(tokens, table: table, stepLimit: 100_000, recovery: .disabled)
            let status: GrammarExampleResult.Status
            let message: String
            switch result.outcome {
            case .accepted: status = .accepted; message = "Accepted"
            case .rejected(let reason, _): status = .rejected; message = reason
            case .conflict: status = .grammarConflict; message = "Unresolved parser conflict."
            case .looping: status = .limitReached; message = "The example exceeded the parser step limit."
            }
            return .init(id: example.id, shouldAccept: example.shouldAccept, status: status,
                         message: message, tree: result.tree.map { render($0, depth: 0) })
        }
    }

    private static func render(_ root: LRRuntimeNode, depth: Int) -> String {
        var pending = [(root, depth)]
        var lines: [String] = []
        while let (node, depth) = pending.popLast(), lines.count < 1_000 {
            lines.append(String(repeating: "  ", count: depth) + node.symbol)
            if depth < 64 {
                pending.append(contentsOf: node.children.reversed().map { ($0, depth + 1) })
            } else if !node.children.isEmpty {
                lines.append("…")
            }
        }
        if !pending.isEmpty { lines.append("…") }
        return lines.joined(separator: "\n")
    }

    private static func lexicalRules(for grammar: Grammar) -> (LexicalSpecification, [String: String]) {
        var rules = grammar.lexicalSpecification.rules
        var names: [String: String] = [:]
        let declared = Set(grammar.lexicalTokens.values.map(\.lrSymbolName))
        for (name, terminal) in grammar.lexicalTokens { names[name] = terminal.lrSymbolName }
        if rules.isEmpty {
            rules.append(.init(name: "$whitespace", matcher: .regularExpression(#"\s+"#), channel: .trivia))
        }
        for terminal in grammar.terminals.sorted(by: { $0.lrSymbolName < $1.lrSymbolName }) {
            guard !declared.contains(terminal.lrSymbolName) else { continue }
            let matcher: LexicalMatcher
            switch terminal {
            case .string(let value): matcher = .literal(value)
            case .stringList(let values): matcher = .literals(values)
            case .regularExpression(let regex): matcher = .regularExpression(regex.pattern)
            case .characterRange(let range):
                matcher = .characterRange(String(range.lowerBound), String(range.upperBound))
            case .meta: continue
            }
            rules.append(.init(name: terminal.lrSymbolName, matcher: matcher, priority: -1))
        }
        return (.init(rules: rules), names)
    }
}
