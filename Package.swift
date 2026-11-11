// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Grammar-LanguageKit",
    platforms: [.macOS(.v13)],
    products: [.library(name: "GrammarLanguage", targets: ["GrammarLanguage"])],
    dependencies: [
        .package(path: "../Grammar"),
        .package(path: "../Lexer"),
        .package(path: "../Incremental-Parsing"),
        .package(path: "../Language-Tooling"),
    ],
    targets: [
        .target(name: "GrammarLanguage", dependencies: [
            .product(name: "Grammar", package: "Grammar"),
            .product(name: "Lexer", package: "Lexer"),
            .product(name: "IncrementalParsing", package: "Incremental-Parsing"),
            .product(name: "LanguageTooling", package: "Language-Tooling"),
        ]),
        .testTarget(name: "GrammarLanguageTests", dependencies: [
            "GrammarLanguage",
            .product(name: "IncrementalParsing", package: "Incremental-Parsing"),
        ]),
    ])
