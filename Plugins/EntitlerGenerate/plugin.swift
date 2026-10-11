import Foundation
import PackagePlugin

/// Runs `entitler generate` in the package's directory: `swift package entitler-generate --out …`.
@main
struct EntitlerGenerate: CommandPlugin {
  /// Runs the generator with the arguments given.
  func performCommand(context: PluginContext, arguments: [String]) async throws {
    let process = Process()
    process.executableURL = try context.tool(named: "entitler").url
    process.arguments = ["generate"] + arguments
    process.currentDirectoryURL = context.package.directoryURL
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      Diagnostics.error("entitler generate failed.")
      return
    }
  }
}
