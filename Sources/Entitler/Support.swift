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
}

protocol StaleMarking {
  var stale: Bool { get set }
}

protocol MeterChecked {
  var hasValidMeters: Bool { get }
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

func formatInstant(_ date: Date) -> String {
  Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
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
  try require(value, message).trimmed
}

enum Messages {
  static let key = "Provide an Entitler API key from the dashboard."
  static let identityToken = "Provide the identity token your sign-in provider issued."
  static let customerToken = "Provide a customer token minted by your server."
  static let customerID = "Provide the id your app uses for the customer."
  static let plan = "Name the plan by its id or its key."
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
  static let amount = "Pass amount as a whole number from 1 to 9007199254740991."
  static let settledAmount = "Pass amount as a whole number from 0 to the held amount."
  static let amountUsed = "Pass the amount used as a whole number of 0 or more."
}
