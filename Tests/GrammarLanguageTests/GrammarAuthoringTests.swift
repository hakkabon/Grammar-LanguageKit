import GrammarLanguage
import IncrementalParsing
import Testing

@Test func unchangedEBNFDraftKeepsGeneratedProductionIdentities() async throws {
    let session = GrammarProvider().makeAuthoringSession()
    let text = "<start> ::= { \"a\" } ;"
    let first = try await session.submit(.init(text: text, revision: .init(1)))
    #expect(first.activated)
    let second = try await session.submit(.init(text: text + "\n", revision: .init(2)))
    #expect(second.activated)
    #expect(second.impact?.isEmpty == true)
    #expect(second.impact?.retainedProductionIDs.isEmpty == false)
}

@Test func authoringRetainsActiveGrammarAcrossInvalidDrafts() async throws {
    let session = GrammarProvider().makeAuthoringSession()
    let first = SourceSnapshot(text: "<start> ::= \"a\" ;", revision: .init(1))
    let activated = try await session.submit(first)
    #expect(activated.activated)
    #expect(activated.activeSource == first)

    let invalid = try SourceEdit(baseRevision: first.revision,
        range: .init(location: 0, length: first.utf16Count),
        replacement: "<start> ::= <missing> ;").applying(to: first)
    let rejected = try await session.submit(invalid.after, change: invalid)
    #expect(!rejected.activated)
    #expect(rejected.activeSource == first)
    #expect(!rejected.analysis.diagnostics.isEmpty)

    let edited = try SourceEdit(baseRevision: invalid.after.revision,
        range: .init(location: 0, length: invalid.after.utf16Count),
        replacement: "<start> ::= \"b\" ;").applying(to: invalid.after)
    let accepted = try await session.submit(edited.after, change: edited)
    #expect(accepted.activated)
    #expect(accepted.activeSource == edited.after)
    #expect(accepted.impact?.affectedNonterminalNames == ["start"])
    #expect(accepted.impact?.addedProductionIDs.count == 1)
    #expect(accepted.impact?.removedProductionIDs.count == 1)
}
