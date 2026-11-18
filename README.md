# Grammar LanguageKit

An independent permanent ModEdit provider for BNF, EBNF, WSN, and the Grammar
package’s combined notation. It uses the authoritative `GrammarParser`, while
Lexer supplies lossless restart-and-converge highlighting tokens. The package
does not depend on ModEdit.


## Author grammar examples

`GrammarProviderSession.checkExamples(_:corpus:)` validates a revisioned
BNF/EBNF draft and checks accepted and rejected examples through the shared
grammar-driven lexer and native LALR runtime. Recovery is disabled. Invalid
drafts return grammar diagnostics with an empty example list. Conflicts and
runtime limits fail either expectation.

`GrammarExampleCorpus` uses schema version 1. Each example provides a unique
`id`, its `input`, and `shouldAccept`. Reports include pass/fail results,
actual outcomes, and a bounded text projection of accepted syntax trees.
Consumers own file access, editing controls, and save policy.
