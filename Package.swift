// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LanReadBatchAutomation",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "lanread-batch", targets: ["BatchCLI"]),
        .library(name: "BatchCore", targets: ["BatchCore"]),
        .library(name: "BatchAI", targets: ["BatchAI"]),
        .library(name: "BatchRender", targets: ["BatchRender"]),
        .library(name: "BatchModels", targets: ["BatchModels"]),
        .library(name: "BatchSupport", targets: ["BatchSupport"])
    ],
    targets: [
        .executableTarget(
            name: "BatchCLI",
            dependencies: ["BatchCore", "BatchModels", "BatchSupport"],
            path: "Batch/BatchCLI"
        ),
        .target(
            name: "BatchCore",
            dependencies: ["BatchAI", "BatchRender", "BatchModels", "BatchSupport"],
            path: "Batch/BatchCore"
        ),
        .target(
            name: "BatchAI",
            dependencies: ["BatchModels", "BatchSupport"],
            path: "Batch/BatchAI"
        ),
        .target(
            name: "BatchRender",
            dependencies: ["BatchModels", "BatchSupport"],
            path: "Batch/BatchRender",
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "BatchModels",
            path: "Batch/BatchModels"
        ),
        .target(
            name: "BatchSupport",
            dependencies: ["BatchModels"],
            path: "Batch/BatchSupport"
        ),
        .testTarget(
            name: "BatchCLITests",
            dependencies: ["BatchCLI", "BatchCore", "BatchAI", "BatchModels", "BatchSupport"],
            path: "Batch/BatchCLITests"
        ),
        .testTarget(
            name: "BatchCoreTests",
            dependencies: ["BatchCore", "BatchModels", "BatchSupport"],
            path: "Batch/BatchCoreTests"
        ),
        .testTarget(
            name: "BatchSupportTests",
            dependencies: ["BatchSupport"],
            path: "Batch/BatchSupportTests"
        )
    ]
)
