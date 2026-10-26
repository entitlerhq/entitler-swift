// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "Entitler",
  platforms: [.iOS(.v15), .macOS(.v12), .tvOS(.v15), .watchOS(.v8), .visionOS(.v1)],
  products: [
    .library(name: "Entitler", targets: ["Entitler"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0")
  ],
  targets: [
    .target(
      name: "Entitler",
      dependencies: [
        .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
      ]
    ),
    .executableTarget(name: "generate-wire"),
    .testTarget(name: "EntitlerTests", dependencies: ["Entitler"]),
  ]
)
