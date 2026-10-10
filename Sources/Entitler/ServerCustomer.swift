import Foundation

/// A plan to move to: named by its key or public id, or replaced by a SKU the customer bought.
///
/// A string literal names a plan: `try await customer.setPlan(to: "pro")`.
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
/// tokens, tracks and the company's own decisions.
///
/// ```swift
/// let customer = try server.customer("user_123")
/// try await customer.register(name: "Ada", email: "ada@example.com")
/// ```
///
/// Its reads also take `asOf`, to read the customer at another instant.
public struct ServerCustomer: Customer, CustomStringConvertible, CustomReflectable {
  /// The id your app uses for the customer.
  public let id: String
  /// The client and customer this value acts through. Opaque.
  public let handle: CustomerHandle

  init(id: String, core: Core) {
    self.id = id
    handle = CustomerHandle(core: core, path: id)
  }

  /// The customer's id.
  public var description: String { "ServerCustomer(\(id))" }

  /// The customer's id only, never the client's key.
  public var customMirror: Mirror { Mirror(self, children: ["id": id]) }

  /// Checks one feature at an instant, through the cache under a key of its own.
  ///
  /// Reads at another instant need the organisation's `as_of` capability
  /// (``ErrorCode/capabilityRequired`` otherwise). They show the effects of time on the plans,
  /// grants and meters already in place (renewals, booked moves, grant expiries, meter resets),
  /// never a release nobody has rolled out yet: put a test customer on a track for testers to
  /// preview one.
  ///
  /// - Throws: ``ArgumentError`` when `asOf` is outside the years 0001 to 9999.
  public func check<Kind>(
    _ feature: Feature<Kind>, asOf: Date?, revalidate: Bool = false, timeout: TimeInterval? = nil
  ) async throws -> Kind.Check {
    try await handle.read(
      ["entitlements", requireFeature(feature.key)], revalidate: revalidate, asOf: asOf,
      timeout: timeout)
  }

  /// Checks the feature with this key at an instant.
  public func check(
    _ key: String, asOf: Date?, revalidate: Bool = false, timeout: TimeInterval? = nil
  ) async throws -> Check {
    try await handle.read(
      ["entitlements", requireFeature(key)], revalidate: revalidate, asOf: asOf, timeout: timeout)
  }

  /// Whether the customer is entitled to a feature at an instant, answering `default` instead of
  /// failing.
  public func isEntitled<Kind>(
    to feature: Feature<Kind>, default fallback: Bool, asOf: Date?, revalidate: Bool = false,
    timeout: TimeInterval? = nil
  ) async -> Bool {
    await handle.isEntitled(
      feature.key, default: fallback, revalidate: revalidate, asOf: asOf, timeout: timeout)
  }

  /// Every entitlement the customer holds at an instant.
  public func entitlements(asOf: Date?, revalidate: Bool = false, timeout: TimeInterval? = nil)
    async throws -> Entitlements
  {
    try await handle.read(["entitlements"], revalidate: revalidate, asOf: asOf, timeout: timeout)
  }

  /// The plans the customer holds at an instant, and the plans they can move to then.
  public func plans(asOf: Date?, revalidate: Bool = false, timeout: TimeInterval? = nil)
    async throws -> CustomerPlans
  {
    try await handle.read(["plans"], revalidate: revalidate, asOf: asOf, timeout: timeout)
  }

  /// The customer's meters at an instant, and a page of their usage log.
  public func usage(cursor: String? = nil, asOf: Date?, timeout: TimeInterval? = nil)
    async throws -> CustomerUsage
  {
    try await handle.usage(cursor: cursor, asOf: asOf, timeout: timeout)
  }

  /// Registers the customer, or stores the details given for one who already exists.
  ///
  /// Call it at sign-up and at sign-in with the latest details. Changing an existing customer's
  /// details needs `customers:write` or `customers:profile`.
  ///
  /// - Parameters:
  ///   - name: The customer's name.
  ///   - email: The customer's email address.
  ///   - metadata: Your metadata, merged into what Entitler holds; a `nil` value removes that key.
  ///   - visitor: The visitor id the person had while signed out, from the app's sign-up request,
  ///     so they keep their experiment arm.
  ///   - idempotencyKey: A key naming this registration. The SDK generates one otherwise.
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
  ///   - asOf: Reads the customer at another instant.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  public func details(cursor: String? = nil, asOf: Date? = nil, timeout: TimeInterval? = nil)
    async throws -> CustomerDetail
  {
    var request = try handle.request("GET", [], timeout: timeout)
    if let cursor { request.query = [("cursor", cursor)] }
    request.asOf = try validAsOf(asOf)
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

  /// Erases the customer, the account deletion app stores require: it ends any Stripe
  /// subscription now, then erases their details, usage and events. Erasing twice is safe.
  ///
  /// Store subscriptions are invisible to Entitler: cancel them through Apple or Google first.
  public func erase(idempotencyKey: String? = nil, timeout: TimeInterval? = nil) async throws {
    var request = try handle.request("DELETE", [], idempotencyKey: idempotencyKey, timeout: timeout)
    request.query = [("erase", "true")]
    try await handle.core.callWithoutAnswer(request)
  }

  /// Mints a customer token for an in-app client. Send it only to this customer's app.
  ///
  /// Without `scopes` it holds `entitlements:read` only. Ask for ``Scope/usageWrite`` only when
  /// the app records usage itself, and for ``Scope/billingSelf`` only for people who may buy for
  /// the customer, such as a workspace's owners.
  ///
  /// - Parameters:
  ///   - scopes: The scopes to hold, from `entitlements:read`, `usage:read`, `usage:write` and
  ///     `billing:self`.
  ///   - ttlSeconds: How long it lasts, 60 to 3600 (the API's default is an hour).
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  public func token(scopes: [Scope]? = nil, ttlSeconds: Int? = nil, timeout: TimeInterval? = nil)
    async throws -> IssuedCustomerToken
  {
    struct Body: Encodable {
      var scopes: [Scope]?
      var ttlSeconds: Int?
    }
    return try await handle.call(
      "POST", ["tokens"], body: Body(scopes: scopes, ttlSeconds: ttlSeconds),
      changesAnswers: false, timeout: timeout)
  }

  /// Puts the customer on a track by its name, the same in every environment, or back on All
  /// customers with `nil`.
  ///
  /// It needs `tracks:assign`, which the server key preset lacks: add that scope to the key, or
  /// it answers ``ErrorCode/scopeRequired``.
  @discardableResult
  public func setTrack(
    _ name: String?, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> CustomerTrack {
    struct Body: Encodable {
      var track: String?

      func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(track, forKey: .track)
      }

      enum CodingKeys: String, CodingKey {
        case track
      }
    }
    return try await handle.call(
      "PUT", ["track"], body: Body(track: try name.map { try require($0, Messages.track) }),
      idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// The payment provider's view of the customer (status, the SKU it bills, drift), for support
  /// tools. Billing pages read ``Customer/plans(revalidate:timeout:)``.
  public func billing(timeout: TimeInterval? = nil) async throws -> CustomerBilling {
    try await handle.call("GET", ["billing"], timeout: timeout)
  }

  /// Moves the customer to a plan, as the company decides: for a deal, a support ticket or a
  /// verified store purchase, under no self-serve rules.
  ///
  /// ```swift
  /// try await customer.setPlan(to: "enterprise", period: "yearly", billing: .end,
  ///   actor: "hubspot", idempotencyKey: deal.eventID)
  /// try await customer.setPlan(to: .sku(appStoreSKU), until: transaction.expirationDate)
  /// ```
  ///
  /// The plan the customer already holds, with the same period, billing and `until`, answers
  /// ``PlanChange/changed`` false, so a redelivered webhook is harmless. A store SKU never touches
  /// Stripe, and is refused with ``ErrorCode/billedElsewhere`` when Stripe already bills that
  /// product. Charging through the provider can fail with ``ErrorCode/paymentRequired``.
  ///
  /// - Parameters:
  ///   - plan: The plan by its key or public id, or the SKU the customer bought (which names its
  ///     own period).
  ///   - period: The period's key, such as `yearly`.
  ///   - when: ``ChangeTiming/now`` or ``ChangeTiming/end`` (at renewal); the project's policy
  ///     when left out.
  ///   - billing: ``BillingMode/provider`` (the API's default) charges through the provider that
  ///     bills the product; ``BillingMode/keep`` moves the customer while the provider keeps
  ///     billing; ``BillingMode/end`` ends the provider's subscription, as for an invoiced
  ///     contract.
  ///   - until: When the customer returns to the product's default plan, such as a store
  ///     transaction's expiry, so a missed store notification ends the plan.
  ///   - register: Registers a customer not registered yet.
  ///   - reason: Why, at most 200 characters, shown in the customer's activity.
  ///   - actor: The person or system that decided, 1 to 200 characters, such as a support agent's
  ///     id or `hubspot`.
  ///   - idempotencyKey: A key naming the event (this deal update, this store notification),
  ///     never the deal. The SDK generates one otherwise.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  @discardableResult
  public func setPlan(
    to plan: PlanChoice, period: String? = nil, when: ChangeTiming? = nil,
    billing: BillingMode? = nil, until: Date? = nil, register: Bool = false,
    reason: String? = nil, actor: String? = nil, idempotencyKey: String? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> PlanChange {
    struct Body: Encodable {
      var plan: String?
      var sku: SKU?
      var period: String?
      var when: ChangeTiming?
      var billing: BillingMode?
      var until: Date?
      var register: Bool?
      var reason: String?
      var actor: String?
    }
    var body = Body(
      period: period, when: when, billing: billing, until: until, register: register ? true : nil,
      reason: reason, actor: actor)
    switch plan {
    case .plan(let key): body.plan = try require(key, Messages.plan)
    case .sku(let sku): body.sku = sku
    }
    return try await handle.call(
      "PUT", ["plan"], body: body, idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Sets how many of an add-on the customer holds, as the company decides: adds it when they
  /// hold none, and removes it at 0.
  ///
  /// - Parameters:
  ///   - addOn: The add-on, by its key or public id.
  ///   - quantity: From 0 to 10,000.
  ///   - when: ``ChangeTiming/now`` or ``ChangeTiming/end``; the project's policy when left out.
  ///   - reason: Why, shown in the customer's activity.
  ///   - actor: The person or system that decided.
  ///   - idempotencyKey: A key naming the event. The SDK generates one otherwise.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  @discardableResult
  public func setAddOn(
    _ addOn: String, quantity: Int, when: ChangeTiming? = nil, reason: String? = nil,
    actor: String? = nil, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> PlanChange {
    struct Body: Encodable {
      var quantity: Int
      var when: ChangeTiming?
      var reason: String?
      var actor: String?
    }
    return try await handle.call(
      "PUT", ["add-ons", require(addOn, Messages.plan)],
      body: Body(quantity: quantity, when: when, reason: reason, actor: actor),
      idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Grants a feature beyond the customer's plan, answering the grant made, so a support tool
  /// keeps its id.
  ///
  /// ```swift
  /// let change = try await customer.grant(Features.sso, days: 30, reason: ticket.id, actor: agent.id)
  /// ```
  ///
  /// - Parameters:
  ///   - feature: The feature to grant.
  ///   - value: An amount from 0 to 999,999,999 or ``FeatureValue/unlimited``; leave it out for
  ///     an on/off feature.
  ///   - days: How many days it lasts, 0 to 3650; 0 or none for no end.
  ///   - reason: Why it was given, shown in the customer's activity.
  ///   - actor: The person or system that decided.
  ///   - idempotencyKey: A key naming the event. The SDK generates one otherwise.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  @discardableResult
  public func grant<Kind>(
    _ feature: Feature<Kind>, value: FeatureValue? = nil, days: Int? = nil, reason: String? = nil,
    actor: String? = nil, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> GrantChange {
    try await grant(
      feature.key, value: value, days: days, reason: reason, actor: actor,
      idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Grants the feature with this key beyond the customer's plan.
  @discardableResult
  public func grant(
    _ key: String, value: FeatureValue? = nil, days: Int? = nil, reason: String? = nil,
    actor: String? = nil, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> GrantChange {
    struct Body: Encodable {
      var feature: String
      var value: String?
      var days: Int?
      var reason: String?
      var actor: String?
    }
    let written: String? =
      switch value {
      case .amount(let amount): String(amount)
      case .unlimited: "unlimited"
      case .on, nil: nil
      }
    return try await handle.call(
      "POST", ["grants"],
      body: Body(
        feature: requireFeature(key), value: written, days: days, reason: reason, actor: actor),
      idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Revokes a grant. It stops counting now and stays in the customer's history.
  @discardableResult
  public func revokeGrant(
    id grantID: String, reason: String? = nil, actor: String? = nil,
    idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> GrantChange {
    try await handle.call(
      "DELETE", ["grants", require(grantID, Messages.grant)],
      body: Correction(reason: reason, actor: actor).orNil, idempotencyKey: idempotencyKey,
      timeout: timeout)
  }

  /// Moves a meter by an amount: `-500` gives back 500 credits without racing new usage. The
  /// meter never goes below 0.
  ///
  /// - Parameters:
  ///   - feature: The metered feature.
  ///   - amount: A whole number other than 0, from −(2^53 − 1) to 2^53 − 1.
  ///   - idempotencyKey: A key naming the event, so a double submit applies once.
  ///   - reason: Why, shown in the customer's activity.
  ///   - actor: The person or system that decided.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  @discardableResult
  public func adjustMeter(
    _ feature: Feature<Metered>, by amount: Int64, idempotencyKey: String, reason: String? = nil,
    actor: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    guard amount != 0, (-maxAmount...maxAmount).contains(amount) else {
      throw ArgumentError(message: Messages.adjustment)
    }
    return try await adjust(
      feature, Adjustment(by: amount, reason: reason, actor: actor), idempotencyKey: idempotencyKey,
      timeout: timeout)
  }

  /// Sets a meter to an amount used this period.
  ///
  /// - Parameters:
  ///   - feature: The metered feature.
  ///   - amount: A whole number from 0 to 2^53 − 1.
  ///   - idempotencyKey: A key naming the event, so a double submit applies once.
  ///   - reason: Why, shown in the customer's activity.
  ///   - actor: The person or system that decided.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  @discardableResult
  public func adjustMeter(
    _ feature: Feature<Metered>, to amount: Int64, idempotencyKey: String, reason: String? = nil,
    actor: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    guard (0...maxAmount).contains(amount) else {
      throw ArgumentError(message: Messages.adjustment)
    }
    return try await adjust(
      feature, Adjustment(to: amount, reason: reason, actor: actor), idempotencyKey: idempotencyKey,
      timeout: timeout)
  }

  /// Cancels a usage report: a correction that takes its amount off the meter.
  @discardableResult
  public func cancelUsage(
    id usageID: String, reason: String? = nil, actor: String? = nil,
    idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    try await handle.call(
      "DELETE", ["usage", require(usageID, Messages.usage)],
      body: Correction(reason: reason, actor: actor).orNil, idempotencyKey: idempotencyKey,
      timeout: timeout)
  }

  private func adjust(
    _ feature: Feature<Metered>, _ body: Adjustment, idempotencyKey: String,
    timeout: TimeInterval?
  ) async throws -> UsageResult {
    try await handle.call(
      "POST", ["meters", requireFeature(feature.key), "adjustments"], body: body,
      idempotencyKey: requireUsageKey(idempotencyKey), timeout: timeout)
  }
}

struct Adjustment: Encodable {
  var by: Int64?
  var to: Int64?
  var reason: String?
  var actor: String?
}

struct Correction: Encodable {
  var reason: String?
  var actor: String?

  var orNil: Correction? { reason == nil && actor == nil ? nil : self }
}
