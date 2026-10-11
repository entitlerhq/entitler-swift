import Foundation

/// A scope a credential may hold, in the order ``EntitlerServer/scopes(timeout:)`` lists them.
public enum Scope: String, CaseIterable, Codable, Hashable, Sendable {
  /// Read plans and pricing.
  case plansRead = "plans:read"
  /// Read entitlements.
  case entitlementsRead = "entitlements:read"
  /// Read usage.
  case usageRead = "usage:read"
  /// Record usage.
  case usageWrite = "usage:write"
  /// Buy for the customer the credential names: subscribe, cancel, undo, the billing portal and
  /// the billing sync. Mint it only for people who may buy for the customer.
  case billingSelf = "billing:self"
  /// Register customers.
  case customersRegister = "customers:register"
  /// Read customers.
  case customersRead = "customers:read"
  /// Change customers and their plans.
  case customersWrite = "customers:write"
  /// Change customers' names, emails and metadata.
  case customersProfile = "customers:profile"
  /// Replace the sample customers.
  case customersSample = "customers:sample"
  /// Mint customer tokens.
  case tokensMint = "tokens:mint"
  /// Change the catalogue.
  case plansWrite = "plans:write"
  /// Release the catalogue.
  case plansRelease = "plans:release"
  /// Manage tracks.
  case tracksManage = "tracks:manage"
  /// Promote tracks.
  case tracksPromote = "tracks:promote"
  /// Put customers on tracks.
  case tracksAssign = "tracks:assign"
  /// Manage keys.
  case keysManage = "keys:manage"
  /// Manage members.
  case membersManage = "members:manage"
  /// Manage projects.
  case projectsManage = "projects:manage"
  /// Manage the organisation.
  case orgManage = "org:manage"

  static func known(_ names: [String]) -> [Scope] {
    let held = Set(names)
    return allCases.filter { held.contains($0.rawValue) }
  }
}

/// The scopes a client's credential holds.
public struct CredentialScopes: Hashable, Sendable {
  /// The scopes this SDK knows, in the order ``Scope`` lists them.
  public let scopes: [Scope]
  /// For an identity client, whether the sign-in provider lets a new person register.
  public let registration: Bool?

  /// Whether the credential holds a scope.
  public func contains(_ scope: Scope) -> Bool { scopes.contains(scope) }
}

struct KeySelf: Decodable {
  let scopes: [String]
  let registration: Bool?

  enum CodingKeys: String, CodingKey {
    case id, name, kind, orgId, projectId, environmentId, scopes, allowedOrigins, createdAt
    case revokedAt, registration, customer, expiresAt
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    scopes = try container.decode([String].self, forKey: .scopes)
    registration = try container.decodeIfPresent(Bool.self, forKey: .registration)
    if container.contains(.customer) {
      _ = try container.decode(String.self, forKey: .customer)
      _ = try container.decode(Date.self, forKey: .expiresAt)
      return
    }
    for key in [CodingKeys.id, .name, .kind, .orgId] {
      _ = try container.decode(String.self, forKey: key)
    }
    for key in [CodingKeys.projectId, .environmentId] {
      _ = try container.decode(String?.self, forKey: key)
    }
    _ = try container.decode([String].self, forKey: .allowedOrigins)
    _ = try container.decode(Date.self, forKey: .createdAt)
    _ = try container.decode(Date?.self, forKey: .revokedAt)
  }
}

protocol StaleMarking {
  var stale: Bool { get set }
}

protocol ShapeChecked {
  var hasValidShape: Bool { get }
}

extension Optional where Wrapped == FeatureValue {
  var isMeterAmount: Bool { self != .on }
}

protocol Replaying {
  var replayed: Bool { get set }
}

func markedReplayed<Value>(_ value: Value) -> Value {
  guard var marked = value as? any Replaying else { return value }
  marked.replayed = true
  return (marked as? Value) ?? value
}

func markedStale<Value>(_ value: Value) -> Value {
  guard var marked = value as? any StaleMarking else { return value }
  marked.stale = true
  return (marked as? Value) ?? value
}

enum JSON {
  static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let text = try container.decode(String.self)
      guard let date = parseInstant(text) else {
        throw DecodingError.dataCorruptedError(
          in: container, debugDescription: "Expected an RFC 3339 instant.")
      }
      return date
    }
    return decoder
  }

  static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(formatInstant(date))
    }
    return encoder
  }
}

func parseInstant(_ text: String) -> Date? {
  guard hasRealFields(text) else { return nil }
  let year = text.prefix(5)
  guard year.count == 5, year.last == "-", year.dropLast().allSatisfy(\.isASCIIDigit),
    year.dropLast() != "0000"
  else { return nil }
  let cycles = max(0, (1999 - Int(year.dropLast())!) / 400)
  let shifted = String(format: "%04d", Int(year.dropLast())! + cycles * 400) + text.dropFirst(4)
  let date =
    (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(shifted))
    ?? (try? Date.ISO8601FormatStyle().parse(shifted))
  return date?.addingTimeInterval(-Double(cycles) * 146_097 * 86_400)
}

private func hasRealFields(_ text: String) -> Bool {
  let scalars = Array(text.utf8)
  func number(_ start: Int, _ length: Int) -> Int? {
    guard start + length <= scalars.count else { return nil }
    var value = 0
    for byte in scalars[start..<start + length] {
      guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { return nil }
      value = value * 10 + Int(byte - UInt8(ascii: "0"))
    }
    return value
  }
  guard let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
    let hour = number(11, 2), let minute = number(14, 2), let second = number(17, 2),
    (1...12).contains(month), hour <= 23, minute <= 59, second <= 59
  else { return false }
  let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
  let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
  guard (1...days).contains(day) else { return false }
  var index = 19
  if index < scalars.count, scalars[index] == UInt8(ascii: ".") {
    index += 1
    while index < scalars.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(scalars[index]) {
      index += 1
    }
  }
  guard index < scalars.count, scalars[index] != UInt8(ascii: "Z"),
    scalars[index] != UInt8(ascii: "z")
  else { return true }
  guard let offsetHours = number(index + 1, 2), let offsetMinutes = number(index + 4, 2) else {
    return false
  }
  return offsetHours <= 23 && offsetMinutes <= 59
}

func formatInstant(_ date: Date) -> String {
  let millis = (date.timeIntervalSince1970 * 1000).rounded()
  let seconds = (millis / 1000).rounded(.down)
  let whole = Date.ISO8601FormatStyle().format(Date(timeIntervalSince1970: seconds))
  return whole.dropLast() + String(format: ".%03dZ", Int(millis - seconds * 1000))
}

extension Character {
  var isASCIIDigit: Bool { isASCII && isNumber }
}

extension String {
  var trimmed: String { trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n")) }

  var componentEncoded: String {
    var allowed = CharacterSet(charactersIn: "-_.!~*'()")
    allowed.formUnion(CharacterSet(charactersIn: "a"..."z"))
    allowed.formUnion(CharacterSet(charactersIn: "A"..."Z"))
    allowed.formUnion(CharacterSet(charactersIn: "0"..."9"))
    return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
  }
}

enum Base64URL {
  static let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

  static func decode(_ text: some StringProtocol) -> Data? {
    guard text.allSatisfy(alphabet.contains) else { return nil }
    var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(
      of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    return Data(base64Encoded: base64)
  }

  static func encode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

let maxAmount: Int64 = 9_007_199_254_740_991

func validAmount(_ amount: Int64) throws -> Int64 {
  guard (1...maxAmount).contains(amount) else { throw ArgumentError(message: Messages.amount) }
  return amount
}

func require(_ value: String, _ message: String) throws -> String {
  guard !value.trimmed.isEmpty else { throw ArgumentError(message: message) }
  return value
}

func requireCredential(_ value: String, _ message: String) throws -> String {
  let credential = value.trimmed
  guard !credential.isEmpty, credential.isHeaderSafe else {
    throw ArgumentError(message: message)
  }
  return credential
}

extension String {
  var isHeaderSafe: Bool { utf8.allSatisfy { (0x21...0x7E).contains($0) } }
}

enum Messages {
  static let key = "Provide an Entitler API key from the dashboard."
  static let identityToken = "Provide the identity token your sign-in provider issued."
  static let customerToken = "Provide a customer token minted by your server."
  static let customerID = "Provide the id your app uses for the customer."
  static let plan = "Name the plan by its id or its key."
  static let product = "Name the product by its key."
  static let endingPlan = "Pass no period, until or version when ending a plan."
  static let feature = "Name the feature by its key."
  static let grant = "Provide the id of the grant."
  static let hold = "Provide the id of the hold."
  static let usage = "Provide the id of the usage report."
  static let visitor = "Pass visitor as an id of 16 to 64 letters, numbers, hyphens or underscores."
  static let asOf = "Pass asOf as a valid date."
  static let idempotencyKey = "Pass idempotencyKey as 1 to 200 printable ASCII characters."
  static let holdKey = "Pass idempotencyKey as 1 to 193 printable ASCII characters."
  static let track = "Name the track by its name."
  static let addOnOrProduct = "Pass either addOn or product, not both."
  static let adjustment =
    "Pass either by, a whole number other than 0, or to, a whole number of 0 or more."
  static let publishableOnServer =
    "A publishable key belongs in EntitlerClient. Use a secret key from the dashboard on your server."
  static let secretInApp =
    "A secret key belongs on your server, in EntitlerServer. Use a publishable key (ent_pk_…) in an app."
  static let expectation = "Provide the customer and environment the snapshot must be for."
  static let dots = "Pass an id that is not made only of dots."
  static let timeout = "Pass timeout as a number of seconds above 0."
  static let amount = "Pass amount as a whole number from 1 to 9007199254740991."
  static let settledAmount = "Pass amount as a whole number from 0 to the held amount."
  static let amountUsed = "Pass the amount used as a whole number of 0 or more."
}

protocol RequiredNullableKeys: CodingKey {
  static var requiredNullable: Set<String> { get }
}

extension KeyedDecodingContainer where K: RequiredNullableKeys {
  func decodeIfPresent(_ type: Int64.Type, forKey key: K) throws -> Int64? {
    try decodeNullable(type, forKey: key)
  }

  func decodeIfPresent(_ type: String.Type, forKey key: K) throws -> String? {
    try decodeNullable(type, forKey: key)
  }

  func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: K) throws -> T? {
    try decodeNullable(type, forKey: key)
  }

  private func decodeNullable<T: Decodable>(_ type: T.Type, forKey key: K) throws -> T? {
    guard contains(key) else {
      guard !K.requiredNullable.contains(key.stringValue) else {
        throw DecodingError.keyNotFound(
          key, DecodingError.Context(codingPath: codingPath, debugDescription: "Missing."))
      }
      return nil
    }
    return try decodeNil(forKey: key) ? nil : decode(T.self, forKey: key)
  }
}

extension KeyedEncodingContainer where K: RequiredNullableKeys {
  mutating func encodeIfPresent(_ value: Int64?, forKey key: K) throws {
    try encodeNullable(value, forKey: key)
  }

  mutating func encodeIfPresent(_ value: String?, forKey key: K) throws {
    try encodeNullable(value, forKey: key)
  }

  mutating func encodeIfPresent<T: Encodable>(_ value: T?, forKey key: K) throws {
    try encodeNullable(value, forKey: key)
  }

  private mutating func encodeNullable<T: Encodable>(_ value: T?, forKey key: K) throws {
    if let value {
      try encode(value, forKey: key)
    } else if K.requiredNullable.contains(key.stringValue) {
      try encodeNil(forKey: key)
    }
  }
}
