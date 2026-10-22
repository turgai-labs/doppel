// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Doppel",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        // Swift checked as Swift checks it, and resolved: every name and type decided.
        .library(name: "Doppel", targets: ["Doppel"]),
        // Swift run from its resolved tree.
        .library(name: "DoppelRuntime", targets: ["DoppelRuntime"]),
        // The Swift compiler's verdict on code, for tests that hold a checker to it.
        .library(name: "DoppelCompilerCheck", targets: ["DoppelCompilerCheck"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "602.0.0")
    ],
    targets: [
        .target(
            name: "Doppel",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftOperators", package: "swift-syntax"),
            ]
        ),
        .target(name: "DoppelRuntime", dependencies: ["Doppel"]),
        .target(name: "DoppelCompilerCheck"),
        // Code run by Doppel, as the Swift compiler's build of it runs.
        .testTarget(
            name: "DoppelRuntimeTests",
            dependencies: ["DoppelRuntime", "Doppel", "DoppelCompilerCheck"],
            exclude: ["Programs"]
        ),
        // Every object in the corpus, checked by the Swift compiler and by Doppel.
        .testTarget(
            name: "DoppelAgreementTests",
            dependencies: ["Doppel", "DoppelCompilerCheck"],
            resources: [.copy("Corpus")]
        ),
    ],
    swiftLanguageModes: [.v6]
)

// Swift's upcoming defaults, for every target:
// - an async function runs on its caller's executor unless it says otherwise, so an
//   interpreter runs on the actor that owns it, one call at a time, interleaving only where a
//   script waits;
// - a conformance is isolated as the type it's on is;
// - a module sees only the members of the modules it imports;
// - an existential is written `any`;
// - a weak capture can't be reassigned.
for target in package.targets {
    target.swiftSettings =
        (target.swiftSettings ?? []) + [
            .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            .enableUpcomingFeature("InferIsolatedConformances"),
            .enableUpcomingFeature("MemberImportVisibility"),
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("ImmutableWeakCaptures"),
        ]
}
