// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "zen_store_cloudkit",
    platforms: [
        // CKSyncEngine starts here (ADR-065).
        .iOS("17.0"),
        .macOS("14.0"),
    ],
    products: [
        .library(name: "zen-store-cloudkit", targets: ["zen_store_cloudkit"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        // The record-name HMAC, with no Flutter dependency so it can be tested alone (ADR-083).
        .target(name: "ZenRecordNames"),
        .testTarget(name: "ZenRecordNamesTests", dependencies: ["ZenRecordNames"]),
        // When the engine's state may be saved, with no Flutter dependency either (ADR-088).
        .target(name: "ZenDeliveryLedger"),
        .testTarget(name: "ZenDeliveryLedgerTests", dependencies: ["ZenDeliveryLedger"]),
        .target(
            name: "zen_store_cloudkit",
            dependencies: [
                "ZenDeliveryLedger",
                "ZenRecordNames",
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
