import Foundation
import GrammarLanguage
import IncrementalParsing
import Testing

@Test func examplesDetectRegressionsAndKeepRejectedDraftsSeparate() async throws {
    let session = GrammarProviderSession()
    let corpus = GrammarExampleCorpus(examples: [
        .init(id: "enable", input: "enable cache", shouldAccept: true),
        .init(id: "disable", input: "disable cache", shouldAccept: true),
        .init(id: "incomplete", input: "enable", shouldAccept: false),
        .init(id: "unknown", input: "remove cache", shouldAccept: false)
    ])
    let grammar = #"""
        <command> ::= <action> "cache" ;
        <action> ::= "enable" | "disable" ;
        """#
    let first = try await session.checkExamples(.init(text: grammar, revision: .init(1)), corpus: corpus)
    #expect(first.passed)
    #expect(first.examples.first?.tree?.contains("command") == true)

    let regressed = try await session.checkExamples(.init(
        text: grammar.replacingOccurrences(of: #""enable" | "disable""#, with: #""enable""#),
        revision: .init(2)), corpus: corpus)
    #expect(!regressed.passed)
    #expect(regressed.examples.first { $0.id == "disable" }?.passed == false)

    let invalid = try await session.checkExamples(.init(
        text: "<command> ::= <missing> ;", revision: .init(3)), corpus: corpus)
    #expect(!invalid.grammarValid)
    #expect(invalid.examples.isEmpty)
    #expect(!invalid.diagnostics.isEmpty)
    let missing = ("<command> ::= <missing> ;" as NSString).range(of: "missing")
    #expect(invalid.diagnostics.first?.range.location == missing.location)
    #expect(invalid.diagnostics.first?.range.length == missing.length)

    let repaired = try await session.checkExamples(.init(text: grammar, revision: .init(4)), corpus: corpus)
    #expect(repaired.passed)
}

@Test func examplesUseDeclaredLexicalRulesAndNeverRecoverToPass() async throws {
    let grammar = #"""
        lexical {
            token NAME = /[a-z]+/;
            trivia SPACE = /\s+/;
        }
        <pair> ::= NAME "=" NAME ;
        """#
    let corpus = GrammarExampleCorpus(examples: [
        .init(id: "pair", input: "colour = blue", shouldAccept: true),
        .init(id: "missing-equals", input: "colour blue", shouldAccept: false)
    ])
    let report = try await GrammarProviderSession().checkExamples(
        .init(text: grammar, revision: .init(1)), corpus: corpus)
    #expect(report.passed)
    #expect(report.examples.last?.status == .rejected)
}

@Test func invalidCorpusFailsBeforeGrammarActivation() async throws {
    let session = GrammarProviderSession()
    let invalid = GrammarExampleCorpus(examples: [
        .init(id: "same", input: "a", shouldAccept: true),
        .init(id: "same", input: "b", shouldAccept: false)
    ])
    await #expect(throws: (any Error).self) {
        try await session.checkExamples(.init(text: #"<s> ::= "a";"#, revision: .init(1)), corpus: invalid)
    }
    let first = try await session.submit(.init(text: #"<s> ::= "a";"#, revision: .init(1)))
    #expect(first.activated)
}
