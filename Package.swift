// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Helium",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Helium", targets: ["Helium"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "Helium",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Sources/Helium",
            resources: [
                .copy("../../Resources")
            ]
        ),
        .testTarget(
            name: "HeliumTests",
            dependencies: ["Helium"],
            path: "Tests/HeliumTests"
        )
    ]
)
