import Foundation
import Grammar
import IncrementalParsing
import LanguageTooling
import Lexer

public struct GrammarProvider: LanguageToolingProvider {
    public let descriptor = LanguageProviderDescriptor(
        id: "grammar", displayName: "Grammar",
        fileExtensions: ["bnf", "ebnf", "wsn", "grammar"],
        distribution: .bundledPermanent,
        capabilities: [
            .syntaxHighlighting, .incrementalAnalysis, .diagnostics, .recovery,
        ])

    public init() {}
    public func makeToolingSession() -> any LanguageToolingSession {
        GrammarProviderSession()
    }
}

public actor GrammarProviderSession: LanguageToolingSession {
    private var tokenizer: GrammarIncrementalTokenizer
    private var text: String?
    private var revision: SourceRevision?
    private var elements: [GrammarLexicalElement] = []

    public init() {
        do {
            tokenizer = RestartAndConvergeTokenizer(
                scanner: try GrammarDrivenLexer(
                    specification: GrammarNotationLexicalSpecification.shared))
        } catch {
            preconditionFailure("Invalid grammar-language lexical specification: \(error)")
        }
    }

    public func analyze(_ snapshot: SourceSnapshot, change: SourceChange?) async throws
        -> LanguageProviderAnalysis {
        if let change, change.after != snapshot {
            throw LanguageProviderError.inconsistentChange
        }
        let lexed = tokenizer.tokenize(snapshot: snapshot, change: change)
        text = snapshot.text
        revision = snapshot.revision
        elements = lexed.output.elements

        let parser = GrammarParser(
            grammar: snapshot.text, reportsDiagnostics: false)
        _ = parser.parse()
        let diagnosticRanges = parser.diagnostics.map { diagnostic in
            let nsRange = NSRange(diagnostic.token.range, in: snapshot.text)
            let range = nsRange.location == NSNotFound
                ? SourceRange(location: 0, length: 0)
                : SourceRange(location: nsRange.location, length: nsRange.length)
            return (diagnostic, range)
        }
        let parserDiagnostics = diagnosticRanges.map { diagnostic, range in
            LanguageProviderDiagnostic(
                severity: .error, message: diagnostic.message,
                range: range)
        }
        let lexicalDiagnostics = lexed.output.diagnostics.map {
            LanguageProviderDiagnostic(
                severity: .error, message: $0.message,
                range: SourceRange($0.range.lowerBound, $0.range.upperBound))
        }
        let metrics = lexed.metrics
        return LanguageProviderAnalysis(
            languageID: "grammar", revision: snapshot.revision,
            tokens: Self.providerTokens(lexed.output.elements),
            diagnostics: lexicalDiagnostics + parserDiagnostics,
            recoveryEdits: diagnosticRanges.compactMap { _, range in
                guard let token = lexed.output.tokens.first(where: {
                    $0.range.lowerBound == range.location
                }) else { return nil }
                return .init(action: .delete(
                    terminal: token.kind, range: range))
            },
            operations: [
                .init(operation: "lexing", evidence: .init(
                    strategy: metrics.incremental ? .incremental : .full,
                    measurements: [.init(
                        dimension: .tokens,
                        reused: metrics.reusedPrefixTokenCount
                            + metrics.reusedSuffixTokenCount,
                        rebuilt: metrics.generatedTokenCount,
                        strategy: metrics.incremental
                            ? "restart-and-converge" : "full-tokenization")])),
                .init(operation: "parsing", evidence: .init(
                    strategy: .full,
                    measurements: [.init(
                        dimension: .grammarProductions,
                        reused: 0,
                        rebuilt: Self.productionCount(in: lexed.output.elements),
                        strategy: "GrammarParser-panic-recovery")]))
            ])
    }

    public func semanticTokens() async throws -> ToolingSemanticTokensResult {
        guard let text, let revision else {
            throw LanguageToolingError.documentNotAnalyzed
        }
        let map = SourceLineMap(text)
        let tokens = Self.providerTokens(elements).compactMap { token -> ToolingSemanticToken? in
            guard let type = Self.semanticType(token.classification) else { return nil }
            return .init(range: map.toolingRange(token.range), type: type)
        }
        return SemanticTokenEncoder.encode(
            tokens, resultID: "grammar:\(revision.rawValue)")
    }

    private static func productionCount(
        in elements: [GrammarLexicalElement]
    ) -> Int {
        elements.filter {
            if case .token(let kind) = $0.kind { return kind == "DEFINE" }
            return false
        }.count
    }

    private static func providerTokens(
        _ elements: [GrammarLexicalElement]
    ) -> [LanguageProviderToken] {
        elements.compactMap { element in
            let classification: String
            switch element.kind {
            case .invalid: classification = "invalid"
            case .trivia: classification = "comment"
            case .token(let kind):
                switch kind {
                case "LITERAL", "REGEX": classification = "string"
                case "NUMBER": classification = "number"
                case "IDENTIFIER": classification = "type"
                case "DEFINE", "RANGE", "PUNCTUATION": classification = "operator"
                default: classification = "keyword"
                }
            }
            return .init(
                range: SourceRange(element.range.lowerBound, element.range.upperBound),
                classification: classification)
        }
    }

    private static func semanticType(
        _ classification: String
    ) -> ToolingSemanticTokenType? {
        switch classification {
        case "comment": .comment
        case "string": .string
        case "number": .number
        case "type": .type
        case "operator": .operatorToken
        case "keyword": .keyword
        default: nil
        }
    }
}
