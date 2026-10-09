// swift-tools-version:6.0
import Foundation
import PackageDescription

let package = Package(
  name: "Entitler",
  platforms: [.iOS(.v15), .macOS(.v12), .tvOS(.v15), .watchOS(.v8), .visionOS(.v1)],
  products: [
    .library(name: "Entitler", targets: ["Entitler"]),
    .library(name: "EntitlerGenerator", targets: ["EntitlerGenerator"]),
    .executable(name: "entitler", targets: ["EntitlerCommand"]),
    .plugin(name: "entitler-generate", targets: ["EntitlerGenerate"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"6.0.0")
  ],
  targets: [
    .target(
      name: "Entitler",
      dependencies: [
        .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
      ]
    ),
    .target(name: "EntitlerGenerator", dependencies: ["Entitler"]),
    .executableTarget(name: "EntitlerCommand", dependencies: ["Entitler", "EntitlerGenerator"]),
    .plugin(
      name: "EntitlerGenerate",
      capability: .command(
        intent: .custom(
          verb: "entitler-generate",
          description: "Write typed feature constants from your Entitler catalogue."
        ),
        permissions: [
          .allowNetworkConnections(
            scope: .all(ports: [443]),
            reason: "Reads your features from the Entitler API."
          ),
          .writeToPackageDirectory(reason: "Writes the generated feature constants."),
        ]
      ),
      dependencies: ["EntitlerCommand"]
    ),
    .testTarget(name: "EntitlerTests", dependencies: ["Entitler", "EntitlerGenerator"]),
    .testTarget(name: "EntitlerIntegrationTests", dependencies: ["Entitler"]),
  ]
)

if ProcessInfo.processInfo.environment["ENTITLER_DOCS"] != nil {
  package.dependencies.append(
    .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.4.0")
  )
}
