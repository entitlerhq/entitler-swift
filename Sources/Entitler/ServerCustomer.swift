import Foundation

/// A plan to move to: named by its key or public id, or replaced by a SKU the customer bought.
///
/// A string literal names a plan: `try await customer.subscribe(to: "pro")`.
public enum PlanChoice: Hashable, Sendable, ExpressibleByStringLiteral {
  /// A plan, by its key or public id.
  case plan(String)
  /// The SKU the customer bought, which names its own period.
  case sku(SKU)

  /// Names a plan by its key or public id.
  public init(stringLiteral value: String) { self = .plan(value) }
}

/// A product the customer bought from a connector: the connector and the provider's ids.
public struct SKU: Codable, Hashable, Sendable {
  /// The connector, such as `stripe` or `apple`.
  public var connector: String
  /// The provider's ids, such as `["productId": "pro_yearly"]`.
  public var ids: [String: String]

  /// Creates a SKU.
  public init(connector: String, ids: [String: String]) {
    self.connector = connector
    self.ids = ids
  }
}

/// A customer on the server: everything a ``Customer`` does, plus registration, details,
/// tokens, tracks and billing. Vendor actions live under ``vendor``.
///
/// ```swift
/// let customer = try server.customer("user_123")
/// try await customer.register(name: "Ada", email: "ada@example.com")
/// ```
public struct ServerCustomer: Customer, CustomStringConvertible, CustomReflectable {
  /// The id your app uses for the customer.
  public let id: String
  /// The client and customer this value acts through. Opaque.
  public let handle: CustomerHandle

  init(id: String, core: Core) {
    self.id = id
    handle = CustomerHandle(core: core, path: id)
  }

  /// Changes the vendor makes on the customer's behalf, apart so none is made by accident.
  public var vendor: Vendor { Vendor(handle: handle) }

  /// The customer's id.
  public var description: String { "ServerCustomer(\(id))" }

  /// The customer's id only, never the client's key.
  public var customMirror: Mirror { Mirror(self, children: ["id": id]) }

  /// Registers the customer, or stores the details given for one who already exists.
  ///
  /// Call it at sign-up and at sign-in with the latest details. Changing an existing customer's
  /// details needs `customers:write` or `customers:profile`.
  ///
  /// - Parameters:
  ///   - name: The customer's name.
  ///   - email: The customer's email address.
  ///   - metadata: Your metadata, merged into what Entitler holds; a `nil` value removes that key.
  ///   - visitor: The visitor id the person had while signed out, so they keep their
  ///     experiment arm.
  ///   - idempotencyKey: A key from your own unit of work, so a retry from anywhere is
  ///     recognised. The SDK generates one otherwise.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  @discardableResult
  public func register(
    name: String? = nil, email: String? = nil, metadata: [String: String?]? = nil,
    visitor: String? = nil, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> RegisteredCustomer {
    struct Body: Encodable {
      var name: String?
      var email: String?
      var metadata: [String: String?]?
    }
    let given = name != nil || email != nil || metadata != nil
    var request = try handle.request(
      "PUT", [], body: given ? Body(name: name, email: email, metadata: metadata) : nil,
      idempotencyKey: idempotencyKey, timeout: timeout)
    request.visitor = try validVisitor(visitor)
    return try await handle.core.call(request)
  }

  /// The customer in full, with a page of their usage log.
  ///
  /// - Parameters:
  ///   - cursor: The ``Page/next`` of the usage log, for the page after it.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  public func details(cursor: String? = nil, timeout: TimeInterval? = nil) async throws
    -> CustomerDetail
  {
    var request = try handle.request("GET", [], timeout: timeout)
    if let cursor { request.query = [("cursor", cursor)] }
    return try await handle.core.call(request)
  }

  /// Changes the customer's name, email or metadata. A `nil` metadata value removes that key.
  @discardableResult
  public func update(
    name: String? = nil, email: String? = nil, metadata: [String: String?]? = nil,
    idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> CustomerSummary {
    struct Body: Encodable {
      var name: String?
      var email: String?
      var metadata: [String: String?]?
    }
    return try await handle.call(
      "PATCH", [], body: Body(name: name, email: email, metadata: metadata),
      idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Deletes the customer, and with `erase` erases their personal data and usage too.
  @discardableResult
  public func delete(
    erase: Bool = false, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  )
    async throws -> CustomerSummary
  {
    var request = try handle.request("DELETE", [], idempotencyKey: idempotencyKey, timeout: timeout)
    if erase { request.query = [("erase", "true")] }
    return try await handle.core.call(request)
  }

  /// Mints a customer token for an in-app client. Send it only to this customer's app.
  ///
  /// - Parameters:
  ///   - scopes: The scopes to hold, from `entitlements:read`, `usage:read` and `usage:write`.
  ///   - ttlSeconds: How long it lasts, 60 to 3600 (the API's default is an hour).
  ///   - idempotencyKey: Sent as `Idempotency-Key`; minting writes nothing.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  public func token(
    scopes: [Scope]? = nil, ttlSeconds: Int? = nil, idempotencyKey: String? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> IssuedCustomerToken {
    struct Body: Encodable {
      var scopes: [Scope]?
      var ttlSeconds: Int?
    }
    return try await handle.call(
      "POST", ["tokens"], body: Body(scopes: scopes, ttlSeconds: ttlSeconds),
      idempotencyKey: idempotencyKey, changesAnswers: false, timeout: timeout)
  }

  /// Puts the customer on a track, or back on All customers with `nil`.
  @discardableResult
  public func setTrack(
    _ trackID: String?, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  )
    async throws -> CustomerTrack
  {
    struct Body: Encodable {
      var trackID: String?

      func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(trackID, forKey: .trackID)
      }

      enum CodingKeys: String, CodingKey {
        case trackID = "trackId"
      }
    }
    return try await handle.call(
      "PUT", ["track"], body: Body(trackID: trackID), idempotencyKey: idempotencyKey,
      timeout: timeout)
  }

  /// Subscribes the customer to a plan, or moves them, as they would choose themselves.
  ///
  /// The move must be on a self-serve path from their plans, or the API refuses it with
  /// ``ErrorCode/notSelfServe``. ``Vendor/subscribe(to:period:when:idempotencyKey:timeout:)``
  /// moves them anywhere.
  @discardableResult
  public func subscribe(
    to plan: PlanChoice, period: String? = nil, when: ChangeTiming? = nil,
    idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> CustomerDetail {
    try await Billing(handle: handle, selfServe: true).subscribe(
      plan, period: period, when: when, override: nil, idempotencyKey: idempotencyKey,
      timeout: timeout)
  }

  /// Opens the payment provider's checkout for a plan, as the customer would choose themselves.
  public func checkout(
    _ plan: PlanChoice, period: String? = nil, successURL: URL, cancelURL: URL,
    connection: String? = nil, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> ProviderPage {
    try await Billing(handle: handle, selfServe: true).checkout(
      plan, period: period, successURL: successURL, cancelURL: cancelURL, connection: connection,
      idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Cancels the customer's plan, at the end of the period unless `when` is ``ChangeTiming/now``.
  ///
  /// - Parameters:
  ///   - when: ``ChangeTiming/now`` to cancel at once.
  ///   - product: The product's key, needed only when they hold plans in several.
  ///   - idempotencyKey: A key from your own unit of work, so a retry from anywhere is
  ///     recognised. The SDK generates one otherwise.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  @discardableResult
  public func cancel(
    when: ChangeTiming? = nil, product: String? = nil, idempotencyKey: String? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> CustomerDetail {
    var request = try handle.request(
      "DELETE", ["subscription"], idempotencyKey: idempotencyKey, timeout: timeout)
    request.query = [("product", product), ("when", when?.rawValue)].compactMap { name, value in
      value.map { (name, $0) }
    }
    return try await handle.core.call(request)
  }

  /// Undoes a move or a cancellation booked for the end of the period.
  @discardableResult
  public func undoPendingChange(
    product: String? = nil, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> CustomerDetail {
    var request = try handle.request(
      "DELETE", ["subscription", "pending"], idempotencyKey: idempotencyKey, timeout: timeout)
    if let product { request.query = [("product", product)] }
    return try await handle.core.call(request)
  }

  /// Adds an add-on, or with `replaces` moves from one add-on to another, as the customer would.
  @discardableResult
  public func addAddOn(
    _ plan: PlanChoice, quantity: Int? = nil, replaces: String? = nil, when: ChangeTiming? = nil,
    idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> CustomerDetail {
    try await Billing(handle: handle, selfServe: true).addAddOn(
      plan, quantity: quantity, replaces: replaces, when: when, idempotencyKey: idempotencyKey,
      timeout: timeout)
  }

  /// Sets how many of an add-on the customer holds, as they would.
  @discardableResult
  public func setAddOnQuantity(
    _ plan: String, to quantity: Int, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> CustomerDetail {
    try await Billing(handle: handle, selfServe: true).setAddOnQuantity(
      plan, quantity: quantity, idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Removes an add-on the customer holds.
  @discardableResult
  public func removeAddOn(
    _ plan: String, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  )
    async throws -> CustomerDetail
  {
    try await handle.call(
      "DELETE", ["subscription", "add-ons", require(plan, Messages.plan)],
      idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Undoes a move from this add-on booked for the end of the period.
  @discardableResult
  public func undoAddOnChange(
    _ plan: String, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> CustomerDetail {
    try await handle.call(
      "DELETE", ["subscription", "add-ons", require(plan, Messages.plan), "pending"],
      idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Whether a payment provider bills the customer, and how.
  public func billing(timeout: TimeInterval? = nil) async throws -> CustomerBilling {
    try await handle.call("GET", ["billing"], timeout: timeout)
  }

  /// Opens the payment provider's page where the customer updates payment details and sees
  /// invoices.
  public func billingPortal(
    returnURL: URL, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> ProviderPage {
    struct Body: Encodable {
      var returnUrl: URL
    }
    return try await handle.call(
      "POST", ["billing-portal"], body: Body(returnUrl: returnURL), idempotencyKey: idempotencyKey,
      changesAnswers: false, timeout: timeout)
  }

  /// The customer's subscriptions and payments as each provider last reported them.
  public func providers(timeout: TimeInterval? = nil) async throws -> CustomerProviders {
    try await handle.call("GET", ["providers"], timeout: timeout)
  }
}

/// Changes the vendor makes on a customer's behalf: ``ServerCustomer/vendor``.
///
/// Unlike the customer's own billing calls these send `selfServe: false`, so the vendor may move
/// the customer anywhere, sales-led plans included.
public struct Vendor: Sendable {
  let handle: CustomerHandle

  /// Subscribes or moves the customer to any plan.
  @discardableResult
  public func subscribe(
    to plan: PlanChoice, period: String? = nil, when: ChangeTiming? = nil,
    idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> CustomerDetail {
    try await Billing(handle: handle, selfServe: false).subscribe(
      plan, period: period, when: when, override: nil, idempotencyKey: idempotencyKey,
      timeout: timeout)
  }

  /// Moves the customer in Entitler only, while the payment provider keeps billing the plan they
  /// held.
  @discardableResult
  public func override(
    to plan: String, period: String? = nil, idempotencyKey: String? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> CustomerDetail {
    try await Billing(handle: handle, selfServe: false).subscribe(
      .plan(plan), period: period, when: nil, override: true, idempotencyKey: idempotencyKey,
      timeout: timeout)
  }

  /// Moves the customer back to the plan they held before an override.
  @discardableResult
  public func undoOverride(
    product: String? = nil, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> CustomerDetail {
    var request = try handle.request(
      "DELETE", ["subscription", "override"], idempotencyKey: idempotencyKey, timeout: timeout)
    if let product { request.query = [("product", product)] }
    return try await handle.core.call(request)
  }

  /// Opens the payment provider's checkout for any plan.
  public func checkout(
    _ plan: PlanChoice, period: String? = nil, successURL: URL, cancelURL: URL,
    connection: String? = nil, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> ProviderPage {
    try await Billing(handle: handle, selfServe: false).checkout(
      plan, period: period, successURL: successURL, cancelURL: cancelURL, connection: connection,
      idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Adds any add-on the customer's plans allow.
  @discardableResult
  public func addAddOn(
    _ plan: PlanChoice, quantity: Int? = nil, replaces: String? = nil, when: ChangeTiming? = nil,
    idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> CustomerDetail {
    try await Billing(handle: handle, selfServe: false).addAddOn(
      plan, quantity: quantity, replaces: replaces, when: when, idempotencyKey: idempotencyKey,
      timeout: timeout)
  }

  /// Sets how many of an add-on the customer holds.
  @discardableResult
  public func setAddOnQuantity(
    _ plan: String, to quantity: Int, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> CustomerDetail {
    try await Billing(handle: handle, selfServe: false).setAddOnQuantity(
      plan, quantity: quantity, idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Grants a feature beyond the customer's plan.
  ///
  /// ```swift
  /// try await customer.vendor.grant(Features.sso, days: 30, reason: "Trial")
  /// ```
  ///
  /// - Parameters:
  ///   - feature: The feature to grant.
  ///   - value: An amount or ``FeatureValue/unlimited``; leave it out for an on/off feature.
  ///   - days: How many days it lasts; leave it out for no end.
  ///   - reason: Why it was given, kept in the customer's history.
  ///   - idempotencyKey: A key from your own unit of work, so a retry from anywhere is
  ///     recognised. The SDK generates one otherwise.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  @discardableResult
  public func grant<Kind>(
    _ feature: Feature<Kind>, value: FeatureValue? = nil, days: Int? = nil, reason: String? = nil,
    idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> CustomerDetail {
    try await grant(
      feature.key, value: value, days: days, reason: reason, idempotencyKey: idempotencyKey,
      timeout: timeout)
  }

  /// Grants the feature with this key beyond the customer's plan.
  @discardableResult
  public func grant(
    _ key: String, value: FeatureValue? = nil, days: Int? = nil, reason: String? = nil,
    idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> CustomerDetail {
    struct Body: Encodable {
      var feature: String
      var value: String?
      var days: Int?
      var reason: String?
    }
    let written: String? =
      switch value {
      case .amount(let amount): String(amount)
      case .unlimited: "unlimited"
      case .on, nil: nil
      }
    return try await handle.call(
      "POST", ["grants"],
      body: Body(feature: requireFeature(key), value: written, days: days, reason: reason),
      idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Revokes a grant. It stops counting now and stays in the customer's history.
  @discardableResult
  public func revokeGrant(
    _ grantID: String, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  )
    async throws -> CustomerDetail
  {
    try await handle.call(
      "DELETE", ["grants", require(grantID, Messages.grant)], idempotencyKey: idempotencyKey,
      timeout: timeout)
  }

  /// Sets how much of a metered feature the customer has used this period.
  @discardableResult
  public func setMeter(
    _ feature: Feature<Metered>, to used: Int64, idempotencyKey: String? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    struct Body: Encodable {
      var used: Int64
    }
    return try await handle.call(
      "PUT", ["meters", requireFeature(feature.key)], body: Body(used: used),
      idempotencyKey: idempotencyKey,
      timeout: timeout)
  }

  /// Cancels a usage report: a correction that takes its amount off the meter.
  @discardableResult
  public func cancelUsage(
    _ usageID: String, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  )
    async throws -> UsageResult
  {
    try await handle.call(
      "DELETE", ["usage", require(usageID, Messages.usage)], idempotencyKey: idempotencyKey,
      timeout: timeout)
  }
}

struct Billing {
  let handle: CustomerHandle
  let selfServe: Bool

  private struct Body: Encodable {
    var plan: String?
    var sku: SKU?
    var period: String?
    var when: ChangeTiming?
    var quantity: Int?
    var replaces: String?
    var successUrl: URL?
    var cancelUrl: URL?
    var connection: String?
    var override: Bool?
    var selfServe: Bool

    init(_ choice: PlanChoice?, selfServe: Bool) throws {
      switch choice {
      case .plan(let plan): self.plan = try require(plan, Messages.plan)
      case .sku(let sku): self.sku = sku
      case nil: break
      }
      self.selfServe = selfServe
    }
  }

  func subscribe(
    _ choice: PlanChoice, period: String?, when: ChangeTiming?, override: Bool?,
    idempotencyKey: String?, timeout: TimeInterval?
  ) async throws -> CustomerDetail {
    var body = try Body(choice, selfServe: selfServe)
    body.period = period
    body.when = when
    body.override = override
    return try await handle.call(
      "POST", ["subscription"], body: body, idempotencyKey: idempotencyKey, timeout: timeout)
  }

  func checkout(
    _ choice: PlanChoice, period: String?, successURL: URL, cancelURL: URL, connection: String?,
    idempotencyKey: String?, timeout: TimeInterval?
  ) async throws -> ProviderPage {
    var body = try Body(choice, selfServe: selfServe)
    body.period = period
    body.successUrl = successURL
    body.cancelUrl = cancelURL
    body.connection = connection
    return try await handle.call(
      "POST", ["checkout"], body: body, idempotencyKey: idempotencyKey, changesAnswers: false,
      timeout: timeout)
  }

  func addAddOn(
    _ choice: PlanChoice, quantity: Int?, replaces: String?, when: ChangeTiming?,
    idempotencyKey: String?, timeout: TimeInterval?
  ) async throws -> CustomerDetail {
    var body = try Body(choice, selfServe: selfServe)
    body.quantity = quantity
    body.replaces = try replaces.map { try require($0, Messages.plan) }
    body.when = when
    return try await handle.call(
      "POST", ["subscription", "add-ons"], body: body, idempotencyKey: idempotencyKey,
      timeout: timeout)
  }

  func setAddOnQuantity(
    _ plan: String, quantity: Int, idempotencyKey: String?, timeout: TimeInterval?
  )
    async throws -> CustomerDetail
  {
    var body = try Body(nil, selfServe: selfServe)
    body.quantity = quantity
    return try await handle.call(
      "PATCH", ["subscription", "add-ons", require(plan, Messages.plan)], body: body,
      idempotencyKey: idempotencyKey, timeout: timeout)
  }
}
