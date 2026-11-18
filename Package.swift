// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

let package = Package(
    name: "Stempeluhr",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Stempeluhr",
            path: "Sources/Stempeluhr"
        )
    ]
)
