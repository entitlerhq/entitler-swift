import Entitler
import Foundation

/// The `entitler` command line: `entitler generate` writes typed feature constants, and
/// `entitler snapshot-keys` writes the snapshot keys an app ships.
public enum GeneratorCommand {
  /// The usage text `--help` prints.
  public static let usage = """
    Usage: entitler <command> [options]

    Commands:
      generate        Writes typed feature constants for your Entitler catalogue.
      snapshot-keys   Writes the keys that verify offline snapshots, for your app to ship.

    Options for generate:
      --out <file>            The Swift file to write (default: EntitlerFeatures.swift)
      --key <key>             An API key with the plans:read scope (default: $ENTITLER_KEY)
      --base-url <url>        The API's address (default: https://api.entitler.dev)
      --access-level <level>  public, package or internal (default: internal)
      --check                 Compare the file with the catalogue instead of writing it
      --allow-empty           Write the file even when Entitler lists no features
      --help                  Show this help

    Options for snapshot-keys:
      --out <file>            The JSON file to write (default: entitler-snapshot-keys.json)
      --base-url <url>        The API's address (default: https://api.entitler.dev)
      --help                  Show this help
    """

  /// Runs the command and answers its exit code.
  ///
  /// - Parameters:
  ///   - arguments: The arguments after the program's name, such as `["generate", "--check"]`.
  ///   - environment: The environment, read for `ENTITLER_KEY`.
  ///   - options: The client options, for tests and proxies.
  ///   - print: Where each line of output goes.
  public static func run(
    _ arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment,
    options: EntitlerOptions = EntitlerOptions(), print: (String) -> Void = { Swift.print($0) }
  ) async -> Int32 {
    guard let command = arguments.first else {
      print(usage)
      return 1
    }
    if command == "--help" {
      print(usage)
      return 0
    }
    let accepted: (flags: Set<String>, values: Set<String>)
    switch command {
    case "generate":
      accepted = (
        ["--check", "--allow-empty", "--help"], ["--out", "--key", "--base-url", "--access-level"]
      )
    case "snapshot-keys":
      accepted = (["--help"], ["--out", "--base-url"])
    default:
      print("Unknown command \(command).\n\n\(usage)")
      return 1
    }
    var values: [String: String] = [:]
    var flags: Set<String> = []
    var index = 1
    while index < arguments.count {
      let argument = arguments[index]
      index += 1
      let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
      let name = parts[0]
      if accepted.flags.contains(name) {
        flags.insert(name)
      } else if accepted.values.contains(name) {
        if parts.count == 2 {
          values[name] = parts[1]
        } else if index < arguments.count {
          values[name] = arguments[index]
          index += 1
        } else {
          print("Pass a value with \(name).\n\n\(usage)")
          return 1
        }
      } else {
        print("Unknown option \(argument).\n\n\(usage)")
        return 1
      }
    }
    if flags.contains("--help") {
      print(usage)
      return 0
    }
    var options = options
    if let base = values["--base-url"] {
      guard let url = URL(string: base), url.scheme != nil else {
        print("Pass --base-url as a URL, such as https://api.entitler.dev.")
        return 1
      }
      options.baseURL = url
    }
    if command == "snapshot-keys" {
      return await writeSnapshotKeys(
        to: values["--out"] ?? "entitler-snapshot-keys.json", options: options, print: print)
    }
    guard let accessLevel = AccessLevel(rawValue: values["--access-level"] ?? "internal") else {
      print("Pass --access-level as public, package or internal.")
      return 1
    }
    guard
      let key = (values["--key"] ?? environment["ENTITLER_KEY"]).flatMap({ $0.isEmpty ? nil : $0 })
    else {
      print(
        "Provide an API key with --key or set ENTITLER_KEY. The key needs the plans:read scope.")
      return 1
    }
    let file = values["--out"] ?? "EntitlerFeatures.swift"
    let list: FeatureList
    do {
      list = try await EntitlerServer(key: key, cache: nil, options: options).features()
    } catch {
      print(failure(error))
      return 1
    }
    let existing = try? String(contentsOfFile: file, encoding: .utf8)
    if list.features.isEmpty, !flags.contains("--allow-empty"),
      let existing, !existingFeatureNames(in: existing).isEmpty
    {
      print(
        "Entitler listed no features, so \(file) was left as it is. Check the key's environment, or pass --allow-empty."
      )
      return 1
    }
    let source = renderFeatures(list, accessLevel: accessLevel, existingSource: existing)
    let count = list.features.count == 1 ? "1 feature" : "\(list.features.count) features"
    if flags.contains("--check") {
      guard let existing, withoutReadLine(existing) == withoutReadLine(source) else {
        print("\(file) is out of date. Run entitler generate to update it.")
        return 1
      }
      print("\(file) is up to date with \(count).")
      return 0
    }
    do {
      try source.write(toFile: file, atomically: true, encoding: .utf8)
    } catch {
      print("Could not write \(file): \(error.localizedDescription)")
      return 1
    }
    print("Wrote \(count) to \(file).")
    return 0
  }

  private static func writeSnapshotKeys(
    to file: String, options: EntitlerOptions, print: (String) -> Void
  ) async -> Int32 {
    let keys: SnapshotKeys
    do {
      keys = try await fetchSnapshotKeys(options: options)
    } catch {
      print(failure(error))
      return 1
    }
    guard !keys.keys.isEmpty else {
      print("Entitler published no snapshot keys, so \(file) was left as it is.")
      return 1
    }
    do {
      try renderSnapshotKeys(keys).write(toFile: file, atomically: true, encoding: .utf8)
    } catch {
      print("Could not write \(file): \(error.localizedDescription)")
      return 1
    }
    let count = keys.keys.count == 1 ? "1 snapshot key" : "\(keys.keys.count) snapshot keys"
    print("Wrote \(count) to \(file).")
    return 0
  }

  private static func failure(_ error: any Error) -> String {
    if case EntitlerError.api(let error) = error {
      return "Entitler request failed: \(withoutFullStop(error.message)) (\(error.code))."
    }
    return "Entitler request failed: \(withoutFullStop(error.localizedDescription))."
  }

  private static func withoutFullStop(_ message: String) -> String {
    message.hasSuffix(".") ? String(message.dropLast()) : message
  }

  private static func withoutReadLine(_ source: String) -> String {
    source.split(separator: "\n", omittingEmptySubsequences: false)
      .filter { !$0.hasPrefix("// Read from ") }.joined(separator: "\n")
  }
}
