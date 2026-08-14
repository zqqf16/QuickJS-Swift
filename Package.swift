// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "QuickJS",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(
            name: "QuickJS",
            targets: ["QuickJS"]),
    ],
    targets: [
        .target(
            name: "QuickJSC",
            dependencies: [],
            path: "Sources/QuickJSC",
            exclude: [
                "VERSION",
                "QUICKJS_LICENSE",
            ],
            // CONFIG_VERSION must match Sources/QuickJSC/VERSION and
            // `quickJSCVersion` in Sources/QuickJS/Version.swift (verified by
            // `testVersionConsistency`). Keep the three in sync when upgrading.
            cSettings: [
                .define("CONFIG_VERSION", to: "\"2026-06-04\""),
                .define("_GNU_SOURCE"),
            ],
            linkerSettings: [
                .linkedLibrary("pthread", .when(platforms: [.linux])),
                .linkedLibrary("m", .when(platforms: [.linux])),
            ]),
        .target(
            name: "QuickJS",
            dependencies: ["QuickJSC"]),
        .testTarget(
            name: "QuickJSTests",
            dependencies: ["QuickJS"]),
    ]
)
