struct Route: Sendable {
  let method: String
  let path: String
  let query: [String]

  func request(
    _ variables: [String: String], query given: [(name: String, value: String)] = []
  ) throws -> Request {
    var path = ""
    var rest = Substring(self.path)
    while let open = rest.firstIndex(of: "{"), let close = rest.firstIndex(of: "}") {
      let name = String(rest[rest.index(after: open)..<close])
      guard let value = variables[name] else {
        preconditionFailure("\(self.path) needs \(name).")
      }
      guard !(value.allSatisfy { $0 == "." }) else { throw ArgumentError(message: Messages.dots) }
      path += rest[..<open] + value.componentEncoded
      rest = rest[rest.index(after: close)...]
    }
    precondition(given.allSatisfy { query.contains($0.name) }, "\(self.path) takes no such query.")
    return Request(method: method, path: path + rest, query: given)
  }
}
