import Foundation

let operations = ["Entitlements.CheckFeature", "Entitlements.ListEntitlements"]
let schemaPrefix = "#/components/schemas/"
typealias Object = [String: Any]

struct Failure: Error, CustomStringConvertible {
  let description: String
}

func typeName(_ reference: String) -> String {
  let name = reference.dropFirst(schemaPrefix.count)
  return String(name.split(separator: ".").last ?? name).replacingOccurrences(of: "-", with: "")
}

func swiftType(_ schema: Object, references: inout Set<String>) -> String {
  if let reference = schema["$ref"] as? String {
    references.insert(reference)
    return typeName(reference)
  }
  if schema["enum"] != nil { return "String" }
  switch schema["type"] as? String {
  case "string": return "String"
  case "integer": return "Int64"
  case "number": return "Double"
  case "boolean": return "Bool"
  case "array":
    return "[\(swiftType(schema["items"] as? Object ?? [:], references: &references))]"
  case "object":
    if let values = schema["additionalProperties"] as? Object {
      return "[String: \(swiftType(values, references: &references))]"
    }
    return "[String: String]"
  default: return "String"
  }
}

func declaration(_ name: String, _ schema: Object, references: inout Set<String>) throws
  -> String
{
  let required = Set(schema["required"] as? [String] ?? [])
  let properties = schema["properties"] as? Object ?? [:]
  let fields = try properties.keys.sorted().map { field in
    guard let property = properties[field] as? Object else {
      throw Failure(description: "\(name).\(field) is not a schema object.")
    }
    let type = swiftType(property, references: &references)
    return "    var `\(field)`: \(type)\(required.contains(field) ? "" : "?")"
  }
  guard !fields.isEmpty else { return "  struct \(name): Decodable, Sendable {}" }
  return (["  struct \(name): Decodable, Sendable {"] + fields + ["  }"]).joined(separator: "\n")
}

func lowerCamel(_ operation: String) -> String {
  let joined = operation.replacingOccurrences(of: ".", with: "")
  return joined.prefix(1).lowercased() + joined.dropFirst()
}

func generate(_ document: Object) throws -> String {
  var found: [String: (method: String, path: String, operation: Object)] = [:]
  for (path, methods) in document["paths"] as? [String: Object] ?? [:] {
    for (method, value) in methods {
      guard let operation = value as? Object, let id = operation["operationId"] as? String else {
        continue
      }
      found[id] = (method.uppercased(), path, operation)
    }
  }
  var references = Set<String>()
  var routes: [String] = []
  for id in operations.sorted() {
    guard let route = found[id] else { throw Failure(description: "No operation \(id).") }
    let content = { (container: Object?) in
      ((container?["content"] as? Object)?["application/json"] as? Object)?["schema"] as? Object
    }
    if let body = content(route.operation["requestBody"] as? Object) {
      _ = swiftType(body, references: &references)
    }
    if let answer = content((route.operation["responses"] as? Object)?["200"] as? Object) {
      _ = swiftType(answer, references: &references)
    }
    let query = (route.operation["parameters"] as? [Object] ?? [])
      .filter { $0["in"] as? String == "query" }
      .compactMap { $0["name"] as? String }
      .map { "\"\($0)\"" }
      .joined(separator: ", ")
    routes.append(
      "  static let \(lowerCamel(id)) = Route(method: \"\(route.method)\", path: \"\(route.path)\", query: [\(query)])"
    )
  }
  let schemas = (document["components"] as? Object)?["schemas"] as? Object ?? [:]
  var declarations: [String: String] = [:]
  while let reference = references.first(where: { declarations[typeName($0)] == nil }) {
    let key = String(reference.dropFirst(schemaPrefix.count))
    guard let schema = schemas[key] as? Object else {
      throw Failure(description: "No schema \(key).")
    }
    if schema["enum"] != nil {
      declarations[typeName(reference)] = "  typealias \(typeName(reference)) = String"
    } else {
      declarations[typeName(reference)] = try declaration(
        typeName(reference), schema, references: &references)
    }
  }
  let body = declarations.keys.sorted().map { declarations[$0]! }
  return
    ([
      "// Generated from openapi.json by `swift run generate-wire`. Do not edit.", "",
      "enum Wire {",
    ]
    + body + [""] + routes + ["}", ""]).joined(separator: "\n")
}

let arguments = CommandLine.arguments
let input = arguments.count > 1 ? arguments[1] : "openapi.json"
let output = arguments.count > 2 ? arguments[2] : "Sources/Entitler/Wire.gen.swift"
do {
  let data = try Data(contentsOf: URL(fileURLWithPath: input))
  guard let document = try JSONSerialization.jsonObject(with: data) as? Object else {
    throw Failure(description: "\(input) is not a JSON object.")
  }
  try generate(document).write(toFile: output, atomically: true, encoding: .utf8)
} catch {
  FileHandle.standardError.write(Data("generate-wire: \(error)\n".utf8))
  exit(1)
}
