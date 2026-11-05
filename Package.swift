// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "UniversalSIPKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        // The public, umbrella SDK product that host applications integrate.
        .library(
            name: "UniversalSIPKit",
            targets: ["UniversalSIPKit"]
        ),
    ],
    targets: [
        // MARK: - Domain
        // Framework-independent business core. Must not depend on any other target.
        .target(
            name: "SIPDomain"
        ),

        // MARK: - Data
        // Concrete repository implementations. Depends only on Domain.
        .target(
            name: "SIPData",
            dependencies: ["SIPDomain"]
        ),

        // MARK: - Baresip C bridge
        // Thin C surface over libre/baresip. Compiles as a no-op stub until the
        // Baresip XCFramework is linked (guarded by `#if __has_include`), so the
        // package builds today. See docs/BARESIP-POC.md.
        //
        // When the XCFramework is produced, add it as a binary target and make
        // this target depend on it so <baresip.h> resolves:
        //
        //   .binaryTarget(name: "Baresip", path: "Frameworks/Baresip.xcframework"),
        //
        // then add `dependencies: ["Baresip"]` below.
        .target(
            name: "BaresipBridge"
        ),

        // MARK: - Infrastructure
        // Platform adapters (engine, CallKit, PushKit, audio, keychain, logging).
        // Depends only on Domain.
        .target(
            name: "SIPInfrastructure",
            dependencies: ["SIPDomain", "BaresipBridge"]
        ),

        // MARK: - Public SDK + Composition Root
        .target(
            name: "UniversalSIPKit",
            dependencies: [
                "SIPDomain",
                "SIPData",
                "SIPInfrastructure"
            ]
        ),

        // MARK: - Tests
        .testTarget(
            name: "SIPDomainTests",
            dependencies: ["SIPDomain"]
        ),
        .testTarget(
            name: "SIPDataTests",
            dependencies: ["SIPData", "SIPDomain", "SIPInfrastructure"]
        ),
        .testTarget(
            name: "UniversalSIPKitTests",
            dependencies: ["UniversalSIPKit", "SIPDomain", "SIPInfrastructure"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
