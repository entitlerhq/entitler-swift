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
  func byte(_ index: Int) -> UInt8? { index < scalars.count ? scalars[index] : nil }
  guard let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
    let hour = number(11, 2), let minute = number(14, 2), let second = number(17, 2),
    year > 0, byte(4) == UInt8(ascii: "-"), byte(7) == UInt8(ascii: "-"),
    byte(10) == UInt8(ascii: "T"), byte(13) == UInt8(ascii: ":"), byte(16) == UInt8(ascii: ":"),
    (1...12).contains(month), hour <= 23, minute <= 59, second <= 59
  else { return nil }
  let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
  let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
  guard (1...days).contains(day) else { return nil }
  var index = 19
  var fraction = 0.0
  if byte(index) == UInt8(ascii: ".") {
    index += 1
    var scale = 0.1
    let first = index
    while let digit = byte(index), (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(digit) {
      fraction += Double(digit - UInt8(ascii: "0")) * scale
      scale /= 10
      index += 1
    }
    guard index > first else { return nil }
  }
  var offset = 0
  switch byte(index) {
  case UInt8(ascii: "Z"):
    index += 1
  case UInt8(ascii: "+"), UInt8(ascii: "-"):
    guard let offsetHours = number(index + 1, 2), byte(index + 3) == UInt8(ascii: ":"),
      let offsetMinutes = number(index + 4, 2), offsetHours <= 23, offsetMinutes <= 59
    else { return nil }
    offset = (offsetHours * 60 + offsetMinutes) * 60 * (byte(index) == UInt8(ascii: "-") ? -1 : 1)
    index += 6
  default:
    return nil
  }
  guard index == scalars.count else { return nil }
  let seconds =
    daysFromCivil(year: year, month: month, day: day) * 86_400 + hour * 3_600 + minute * 60
    + second - offset
  return Date(timeIntervalSince1970: Double(seconds) + fraction)
}

private func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
  let shifted = month <= 2 ? year - 1 : year
  let era = (shifted >= 0 ? shifted : shifted - 399) / 400
  let yearOfEra = shifted - era * 400
  let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
  let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
  return era * 146_097 + dayOfEra - 719_468
}

private func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
  let shifted = days + 719_468
  let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
  let dayOfEra = shifted - era * 146_097
  let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
  let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
  let monthIndex = (5 * dayOfYear + 2) / 153
  let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
  let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
  return (year, month, dayOfYear - (153 * monthIndex + 2) / 5 + 1)
}

package func formatInstant(_ date: Date) -> String {
  let millis = Int(max(-9e18, min(9e18, (date.timeIntervalSince1970 * 1000).rounded())))
  let (days, millisOfDay) = millis.quotientAndRemainder(dividingBy: 86_400_000)
  let (day, time) = millisOfDay < 0 ? (days - 1, millisOfDay + 86_400_000) : (days, millisOfDay)
  let civil = civilFromDays(day)
  return String(
    format: "%04ld-%02ld-%02ldT%02ld:%02ld:%02ld.%03ldZ", civil.year, civil.month, civil.day,
    time / 3_600_000, time / 60_000 % 60, time / 1_000 % 60, time % 1_000)
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
