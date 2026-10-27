import Foundation

/// What a customer token lets an app do, extensible: a scope this SDK does not list is kept as the
/// API spells it, such as `CUSTOMER_TOKEN_SCOPE_REPORTS_READ`, and sent back unchanged.
public struct CustomerTokenScope: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
  /// The scope as the SDK spells it, such as `usage:write`.
  public let rawValue: String

  /// Creates a scope from its spelling.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// The scope's spelling.
  public var description: String { rawValue }

  /// Checks features and lists entitlements.
  public static let entitlementsRead = CustomerTokenScope(rawValue: "entitlements:read")
  /// Reads the customer's usage.
  public static let usageRead = CustomerTokenScope(rawValue: "usage:read")
  /// Reports usage, and places, settles and releases holds.
  public static let usageWrite = CustomerTokenScope(rawValue: "usage:write")
  /// Buys for the customer: only for people who may.
  public static let billingSelf = CustomerTokenScope(rawValue: "billing:self")

  private static let wirePrefix = "CUSTOMER_TOKEN_SCOPE_"
  private static let listed: [CustomerTokenScope] = [
    .entitlementsRead, .usageRead, .usageWrite, .billingSelf,
  ]

  init(wireName: String) {
    self = Self.listed.first { $0.wireName == wireName } ?? CustomerTokenScope(rawValue: wireName)
  }

  var wireName: String {
    guard !rawValue.hasPrefix(Self.wirePrefix) else { return rawValue }
    return Self.wirePrefix + rawValue.uppercased().replacingOccurrences(of: ":", with: "_")
  }
}

/// A customer's record.
public struct CustomerRecord: Hashable, Sendable {
  /// The customer's external id: the id your app uses for them.
  public let customer: String
  /// Entitler's id for the customer.
  public let customerID: String
  /// The customer's name, or `nil`.
  public let name: String?
  /// The customer's email, or `nil`.
  public let email: String?
  /// Your own attributes for the customer, such as their region or account manager.
  public let attributes: [String: String]
  /// The id of the track the customer is on, or `nil` for the default track.
  public let trackID: String?
  /// `real` for a customer who pays real money, `test` for one in test mode.
  public let money: OpenName
  /// The record's revision, which every change raises.
  public let revision: Int64
  /// When the customer was registered.
  public let createdAt: Date
  /// When the record last changed.
  public let updatedAt: Date
}

/// The answer to ``ServerCustomer/register(name:email:attributes:visitor:timeout:)``: the record,
/// and whether this call created it. Read the record's fields straight from it.
@dynamicMemberLookup
public struct RegisteredCustomer: Hashable, Sendable {
  /// The customer's record.
  public let record: CustomerRecord
  /// True when this call registered the customer, false when they were registered already. Also
  /// false when a lost answer was retried, so a sign-up count read from it can be one short.
  public let created: Bool

  /// Reads a field of ``record``.
  public subscript<Value>(dynamicMember field: KeyPath<CustomerRecord, Value>) -> Value {
    record[keyPath: field]
  }
}

/// A customer token for an in-app client. Its description never shows the token.
public struct CustomerToken: Hashable, Sendable, CustomStringConvertible, CustomReflectable {
  /// The token. Treat it as a secret of that customer's session.
  public let token: String
  /// The token's id.
  public let id: String
  /// Entitler's id for the customer, or `nil` while they are not registered.
  public let customerID: String?
  /// What the token lets the client do.
  public let scopes: [CustomerTokenScope]
  /// When the token expires.
  public let expiresAt: Date

  /// The token's id and expiry, never the token.
  public var description: String { "CustomerToken(\(id), expires \(expiresAt))" }

  /// The token's id, scopes and expiry, never the token.
  public var customMirror: Mirror {
    Mirror(self, children: ["id": id, "scopes": scopes, "expiresAt": expiresAt])
  }
}

/// A customer on the server: everything an app's customer does, plus their record and tokens.
///
/// ```swift
/// let ada = try entitler.customer("ada")
/// try await ada.register(name: "Ada", email: "ada@example.com")
/// ```
public struct ServerCustomer: Customer, CustomStringConvertible, CustomReflectable {
  /// The id your app uses for the customer.
  public let id: String
  /// The client this customer acts through. Opaque.
  public let handle: CustomerHandle

  /// The customer's id.
  public var description: String { "ServerCustomer(\(id))" }

  /// The customer's id only, never the client's key.
  public var customMirror: Mirror { Mirror(self, children: ["id": id]) }

  /// Registers the customer, or keeps their details current: call it at sign-up, and at sign-in
  /// with the latest details. Registering twice is safe.
  ///
  /// - Parameters:
  ///   - name: The customer's name.
  ///   - email: The customer's email.
  ///   - attributes: Attributes to set, merged into those kept; a `nil` value removes that
  ///     attribute.
  ///   - visitor: The visitor id the customer had while signed out, so they keep their experiment
  ///     arm.
  ///   - timeout: How long each attempt may take, in seconds, instead of the client's timeout.
  @discardableResult
  public func register(
    name: String? = nil, email: String? = nil, attributes: [String: String?] = [:],
    visitor: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> RegisteredCustomer {
    try await send(
      Wire.customersRegisterCustomer,
      DetailsBody(name: name, email: email, attributes: attributes, visitorId: visitor), timeout,
      decodeRegistered)
  }

  /// Reads the customer's record.
  public func details(timeout: TimeInterval? = nil) async throws -> CustomerRecord {
    try await send(Wire.customersGetCustomer, nil as DetailsBody?, timeout, decodeCustomer)
  }

  /// Changes the customer's details.
  ///
  /// - Parameters:
  ///   - attributes: Attributes to set, merged into those kept; a `nil` value removes that
  ///     attribute.
  @discardableResult
  public func update(
    name: String? = nil, email: String? = nil, attributes: [String: String?] = [:],
    timeout: TimeInterval? = nil
  ) async throws -> CustomerRecord {
    try await send(
      Wire.customersUpdateCustomer,
      DetailsBody(name: name, email: email, attributes: attributes), timeout, decodeCustomer)
  }

  /// Erases the customer, as account deletion in app stores requires: their details, usage and
  /// events. Cancel store subscriptions through Apple or Google first. Erasing twice is safe.
  public func erase(timeout: TimeInterval? = nil) async throws {
    try await send(
      Wire.customersEraseCustomer, EmptyBody(), timeout, retryable: true,
      { _ = try wire(Wire.EraseCustomerResponse.self, $0) })
  }

  /// Mints a customer token for an in-app client, `entitlements:read` alone unless `scopes` asks
  /// for more. Hand it to your own signed-in app only.
  ///
  /// ```swift
  /// let token = try await entitler.customer(user.id).token(scopes: [.entitlementsRead, .usageWrite])
  /// ```
  ///
  /// - Parameters:
  ///   - scopes: What the token lets the app do. Ask for ``CustomerTokenScope/usageWrite`` only
  ///     when the app records usage itself, and ``CustomerTokenScope/billingSelf`` only for people
  ///     who may buy for the customer.
  ///   - ttlSeconds: How long the token lasts, 60 to 3,600 seconds. Defaults to 3,600.
  public func token(
    scopes: [CustomerTokenScope]? = nil, ttlSeconds: Int? = nil, timeout: TimeInterval? = nil
  ) async throws -> CustomerToken {
    if let ttlSeconds, !(60...3600).contains(ttlSeconds) {
      throw ArgumentError(message: Messages.ttlToken)
    }
    let body = TokenBody(
      scopes: scopes?.map(\.wireName),
      lifetimeSeconds: ttlSeconds)
    return try await send(Wire.customerTokensCreateToken, body, timeout, decodeToken)
  }

  private func send<Body: Encodable, Answer: Sendable>(
    _ route: Route, _ body: Body?, _ timeout: TimeInterval?, retryable: Bool? = nil,
    _ decode: @escaping @Sendable (Data) throws -> Answer
  ) async throws -> Answer {
    var request = try route.request(["external_id": id])
    request.body = try body.map { try JSONEncoder().encode($0) }
    request.retryable = retryable
    request.timeout = timeout
    return try await core.call(request, decode: decode).answer
  }
}

private struct DetailsBody: Encodable {
  struct Attribute: Encodable {
    var key: String
    var value: String?
  }

  var name: String?
  var email: String?
  var attributes: [Attribute]?
  var visitorId: String?

  init(name: String?, email: String?, attributes: [String: String?], visitorId: String? = nil) {
    self.name = name
    self.email = email
    self.attributes =
      attributes.isEmpty
      ? nil : attributes.keys.sorted().map { Attribute(key: $0, value: attributes[$0] ?? nil) }
    self.visitorId = visitorId
  }
}

private struct TokenBody: Encodable {
  var scopes: [String]?
  var lifetimeSeconds: Int?
}

private struct EmptyBody: Encodable {}
