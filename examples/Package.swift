// swift-tools-version:6.0
import PackageDescription

let entitler = Target.Dependency.product(name: "Entitler", package: "entitler-swift")

let package = Package(
  name: "EntitlerExamples",
  platforms: [.iOS(.v15), .macOS(.v12)],
  dependencies: [.package(path: "..")],
  targets: [
    .executableTarget(name: "quickstart", dependencies: [entitler], path: "quickstart"),
    .executableTarget(name: "pricing-page", dependencies: [entitler], path: "pricing-page"),
    .executableTarget(name: "in-app", dependencies: [entitler], path: "in-app"),
    .executableTarget(name: "metered-work", dependencies: [entitler], path: "metered-work"),
    .executableTarget(name: "offline", dependencies: [entitler], path: "offline"),
    .executableTarget(name: "billing", dependencies: [entitler], path: "billing"),
    .executableTarget(
      name: "generated-features", dependencies: [entitler], path: "generated-features"),
    .target(name: "SwiftUIViewModel", dependencies: [entitler], path: "swiftui-view-model"),
    .target(name: "DocSnippets", dependencies: [entitler], path: "doc-snippets"),
  ]
)
