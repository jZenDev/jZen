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
        .target(
            name: "zen_store_cloudkit",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
