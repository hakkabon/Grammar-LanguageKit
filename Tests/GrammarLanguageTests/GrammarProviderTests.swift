import GrammarLanguage
import IncrementalParsing
import Testing

@Suite("Grammar language provider")
struct GrammarProviderTests {
    @Test func acceptsBNFAndPublishesGrammarTokens() async throws {
        let session = GrammarProvider().makeToolingSession()
        let snapshot = SourceSnapshot(
            text: #"<value> ::= "true" | "false" ;"#,
            revision: .init(1))
        let result = try await session.analyze(snapshot)
        #expect(result.diagnostics.isEmpty)
        #expect(result.tokens.contains { $0.classification == "string" })
        #expect(result.evidence(for: "parsing") != nil)
        #expect(!(try await session.semanticTokens()).data.isEmpty)
    }

    @Test func reportsMalformedGrammarAndReusesLexing() async throws {
        let session = GrammarProvider().makeToolingSession()
        let first = SourceSnapshot(
            text: #"<value> ::= "true" ;"#, revision: .init(1))
        _ = try await session.analyze(first)
        let change = try SourceEdit(
            baseRevision: first.revision,
            range: .init(location: 0, length: 0), replacement: "42 ")
            .applying(to: first)
        let result = try await session.analyze(change.after, change: change)
        #expect(result.evidence(for: "lexing")?.strategy == .incremental)
        #expect(!result.diagnostics.isEmpty)
        #expect(!result.recoveryEdits.isEmpty)
        #expect(result.recoveryEdits.allSatisfy { $0.range.length > 0 })
    }
}
