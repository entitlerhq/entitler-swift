import Foundation

/// A plan the customer holds after a move.
public struct HeldPlan: Hashable, Sendable {
  /// The plan's id.
  public let id: String
  /// The plan's key.
  public let key: String
  /// The plan's name.
  public let name: String
  /// The plan's version the customer holds.
  public let version: Int64
  /// True when it is the product's default plan, held because the customer holds no other.
  public let byDefault: Bool
  /// `real` when the customer pays real money for it, `test` in test mode.
  public let money: OpenName
  /// The id of the billing period it renews on, or `nil`.
  public let period: String?
}

/// What a move changed in one product.
public struct PlanChange: Hashable, Sendable {
  /// The product's id, or `nil`.
  public let product: String?
  /// The plan held in it after the move, or `nil` when it holds none.
  public let plan: HeldPlan?
  /// The add-on's quantity after the move, or `nil` for a plan.
  public let quantity: Int64?
  /// `now` when the move took effect at once, `renewal` when it is booked for the next renewal.
  public let effective: OpenName
  /// When it takes effect.
  public let at: Date
  /// When the plan ends, such as a store purchase's expiry, or `nil`.
  public let until: Date?
  /// False when the customer held that already, so the move changed nothing.
  public let changed: Bool
  /// How the move compares with what the customer held: `upgrade`, `downgrade`, `crossgrade`,
  /// `longer` or `shorter`.
  public let policy: OpenName
}

/// A move that is done.
public struct MoveResult: Hashable, Sendable {
  /// Entitler's id for the customer.
  public let customerID: String
  /// The customer's revision after the move, to pass as the next write's `expectedRevision`.
  public let revision: Int64
  /// `real` for a customer who pays real money, `test` for one in test mode.
  public let money: OpenName
  /// What the move changed, or `nil`.
  public let change: PlanChange?
  /// What the customer holds after the move, or `nil`.
  public let holdings: Holdings?
}

/// The answer to a move.
public enum MoveStep: Hashable, Sendable {
  /// The move is done.
  case done(MoveResult)
  /// The customer has to pay: send them to `url`. `status` is `checkout`, `confirmation`,
  /// `requires_action`, `declined` or `pending`.
  case pay(url: URL, status: OpenName)
  /// The payment provider is still confirming the payment, so read the customer's plans again
  /// later.
  case confirming
}

/// An offer a customer takes when they subscribe.
public enum OfferTaken: Hashable, Sendable {
  /// The offer, by its key.
  case key(String)
  /// A code the customer typed.
  case code(String)
}

/// An offer the company gives with a plan, at its own value or at the value passed.
public struct OfferChoice: Hashable, Sendable {
  /// The offer's key.
  public var key: String
  /// A fixed amount off, in the currency's smallest unit, instead of the offer's own.
  public var amount: Int64?
  /// A percentage off in thousandths of a percent, such as `12_500` for 12.5 %, instead of the
  /// offer's own.
  public var percentThousandths: Int64?

  /// Creates an offer choice.
  public init(key: String, amount: Int64? = nil, percentThousandths: Int64? = nil) {
    self.key = key
    self.amount = amount
    self.percentThousandths = percentThousandths
  }
}

/// When a move takes effect, extensible: a value this SDK does not list is sent as it is.
public struct MoveTiming: RawRepresentable, Hashable, Sendable {
  /// The timing as the SDK spells it, such as `now`.
  public let rawValue: String

  /// Creates a timing from its spelling.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// At once.
  public static let now = MoveTiming(rawValue: "now")
  /// At the next renewal.
  public static let periodEnd = MoveTiming(rawValue: "period_end")
}

extension Customer {
  /// Subscribes the customer to a plan, or moves them to it, as they would from your app. Never
  /// retried, since a retry could charge twice.
  ///
  /// ```swift
  /// switch try await entitler.me.subscribe(to: "pro", period: "pe_monthly", returnURL: back) {
  /// case .done(let result): show(result.change)
  /// case .pay(let url, _): await UIApplication.shared.open(url)
  /// case .confirming: showPending()
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - plan: The plan's key.
  ///   - period: The id of the billing period to buy. Defaults to the plan's first.
  ///   - quantity: How many seats or units to buy, 1 or more.
  ///   - offer: An offer the customer takes, by its key or by a code they typed.
  ///   - market: The key of the market to price the plan in.
  ///   - country: The ISO 3166-1 country code whose market prices the plan, instead of `market`.
  ///   - returnURL: Where the payment provider sends the customer back to after paying.
  ///   - register: Registers a customer not registered yet, if the credential may register them.
  ///   - reason: Why, kept with the change.
  ///   - expectedRevision: The customer's revision this was decided on. When the record has
  ///     changed since, the move fails with an ``APIError`` and changes nothing.
  public func subscribe(
    to plan: String, period: String? = nil, quantity: Int64? = nil, offer: OfferTaken? = nil,
    market: String? = nil, country: String? = nil, returnURL: URL? = nil, register: Bool? = nil,
    reason: String? = nil, expectedRevision: Int64? = nil, timeout: TimeInterval? = nil
  ) async throws -> MoveStep {
    var body = MoveBody(
      plan: PlanKey(planKey: try require(plan, Messages.plan)), periodId: period,
      quantity: try quantity.map(positiveQuantity), returnUrl: returnURL?.absoluteString,
      register: register == true ? true : nil)
    switch offer {
    case .key(let key): body.offer = TakenBody(offerKey: try require(key, Messages.offer))
    case .code(let code): body.offer = TakenBody(code: code)
    case nil: break
    }
    try body.place(market: market, country: country)
    return try await move(
      Wire.subscriptionsChooseSubscription, [:], body, reason, expectedRevision, retryable: false,
      timeout)
  }

  /// Cancels the customer's subscription in a product.
  ///
  /// - Parameters:
  ///   - product: The product's id. Leave it out when the project has one product.
  ///   - endsAt: When the subscription ends. Leave it out for the project's cancellation policy to
  ///     decide.
  @discardableResult
  public func cancel(
    product: String? = nil, endsAt: Date? = nil, reason: String? = nil,
    expectedRevision: Int64? = nil, timeout: TimeInterval? = nil
  ) async throws -> MoveStep {
    try await move(
      Wire.subscriptionsCancelSubscription, [:],
      MoveBody(
        productId: product, endsAt: try endsAt.map { try epochSeconds($0, Messages.endsAt) }),
      reason, expectedRevision, retryable: expectedRevision == nil, timeout)
  }

  /// Undoes the change booked for the customer's next renewal in a product, such as a downgrade
  /// or a cancellation.
  @discardableResult
  public func undoPendingChange(
    product: String? = nil, reason: String? = nil, expectedRevision: Int64? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> MoveStep {
    try await move(
      Wire.subscriptionsCancelPendingChange, [:], MoveBody(productId: product), reason,
      expectedRevision, retryable: expectedRevision == nil, timeout)
  }

  func move(
    _ route: Route, _ variables: [String: String], _ body: MoveBody, _ reason: String?,
    _ expectedRevision: Int64?, retryable: Bool, _ timeout: TimeInterval?
  ) async throws -> MoveStep {
    var body = body
    body.reason = reason
    body.expectedRevision = try revision(expectedRevision)
    var request = try route.request(variables.merging(["external_id": id]) { $1 })
    request.body = try JSONEncoder().encode(body)
    request.retryable = retryable
    request.timeout = timeout
    return try await core.call(request, decode: decodeMove).answer
  }
}

extension ServerCustomer {
  /// Moves the customer to a plan, as the company: with offers, at a time of its choosing, and
  /// with or without billing. Retried only without `expectedRevision`.
  ///
  /// ```swift
  /// try await customer.setPlan("enterprise", period: "pe_yearly", when: .now, reason: "Order 118")
  /// ```
  ///
  /// - Parameters:
  ///   - period: The id of the billing period to move to. Defaults to the one the customer holds,
  ///     else the plan's first.
  ///   - when: ``MoveTiming/now``, or ``MoveTiming/periodEnd`` to book it for renewal. The
  ///     project's policy decides when left out.
  ///   - until: When the plan ends, such as a store purchase's expiry.
  ///   - offers: Offers given with the plan.
  ///   - latestVersion: Moves the customer to the plan's latest version even when they hold an
  ///     earlier one.
  ///   - keepBilling: Keeps the payment provider billing as it does, so the move changes only
  ///     entitlements.
  ///   - endBilling: Ends the payment provider's billing for the plan the customer leaves.
  ///   - waiveExitCharges: Waives the exit fees and charge-backs leaving early would cost.
  @discardableResult
  public func setPlan(
    _ plan: String, period: String? = nil, when: MoveTiming? = nil, until: Date? = nil,
    offers: [OfferChoice] = [], market: String? = nil, country: String? = nil,
    latestVersion: Bool = false, keepBilling: Bool = false, endBilling: Bool = false,
    waiveExitCharges: Bool = false, register: Bool = false, reason: String? = nil,
    expectedRevision: Int64? = nil, timeout: TimeInterval? = nil
  ) async throws -> MoveStep {
    var body = MoveBody(
      set: PlanKey(planKey: try require(plan, Messages.plan)), periodId: period,
      when: when.map(moveWhen), until: try until.map { try epochSeconds($0, Messages.until) },
      offers: offers.isEmpty ? nil : try offers.map(offerChoice),
      latestVersion: flag(latestVersion),
      keepBilling: flag(keepBilling), endBilling: flag(endBilling),
      waiveExitCharges: flag(waiveExitCharges), register: flag(register))
    try body.place(market: market, country: country)
    return try await move(
      Wire.subscriptionsSetPlan, [:], body, reason, expectedRevision,
      retryable: expectedRevision == nil, timeout)
  }

  /// Ends the customer's plan in a product. Retried only without `expectedRevision`.
  @discardableResult
  public func endPlan(
    in product: String, when: MoveTiming? = nil, endBilling: Bool = false,
    waiveExitCharges: Bool = false, reason: String? = nil, expectedRevision: Int64? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> MoveStep {
    try await move(
      Wire.subscriptionsSetPlan, [:],
      MoveBody(
        end: ProductID(productId: try require(product, Messages.product)),
        when: when.map(moveWhen), endBilling: flag(endBilling),
        waiveExitCharges: flag(waiveExitCharges)),
      reason, expectedRevision, retryable: expectedRevision == nil, timeout)
  }

  /// Gives the customer an add-on, or changes how many they hold. Retried only without
  /// `expectedRevision`.
  ///
  /// - Parameters:
  ///   - quantity: How many to hold, 1 or more. Defaults to 1.
  ///   - replaces: The key of an add-on this one replaces.
  @discardableResult
  public func setAddOn(
    _ addOn: String, quantity: Int64? = nil, replaces: String? = nil, register: Bool = false,
    reason: String? = nil, expectedRevision: Int64? = nil, timeout: TimeInterval? = nil
  ) async throws -> MoveStep {
    try await move(
      Wire.subscriptionsSetAddOn, ["plan_key": try require(addOn, Messages.addOn)],
      MoveBody(
        quantity: try quantity.map(positiveQuantity),
        replaces: try replaces.map { PlanKey(planKey: try require($0, Messages.addOn)) },
        register: flag(register)),
      reason, expectedRevision, retryable: expectedRevision == nil, timeout)
  }

  /// Removes an add-on from the customer. Retried only without `expectedRevision`.
  @discardableResult
  public func removeAddOn(
    _ addOn: String, reason: String? = nil, expectedRevision: Int64? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> MoveStep {
    try await move(
      Wire.subscriptionsRemoveAddOn, ["plan_key": try require(addOn, Messages.addOn)],
      MoveBody(), reason, expectedRevision, retryable: expectedRevision == nil, timeout)
  }

  /// Undoes the change booked for an add-on at the next renewal. Retried only without
  /// `expectedRevision`.
  @discardableResult
  public func undoAddOnChange(
    _ addOn: String, reason: String? = nil, expectedRevision: Int64? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> MoveStep {
    try await move(
      Wire.subscriptionsCancelPendingAddOnChange,
      ["plan_key": try require(addOn, Messages.addOn)], MoveBody(), reason, expectedRevision,
      retryable: expectedRevision == nil, timeout)
  }
}

struct PlanKey: Encodable {
  var planKey: String
}

struct ProductID: Encodable {
  var productId: String
}

struct TakenBody: Encodable {
  var offerKey: String?
  var code: String?
}

struct OfferChoiceBody: Encodable {
  struct Value: Encodable {
    var amount: Int64?
    var percentThousandths: Int64?
  }

  var offerKey: String
  var value: Value?
}

struct MoveBody: Encodable {
  var plan: PlanKey?
  var set: PlanKey?
  var end: ProductID?
  var productId: String?
  var periodId: String?
  var quantity: Int64?
  var offer: TakenBody?
  var replaces: PlanKey?
  var when: String?
  var until: Int64?
  var offers: [OfferChoiceBody]?
  var endsAt: Int64?
  var market: String?
  var country: String?
  var returnUrl: String?
  var latestVersion: Bool?
  var keepBilling: Bool?
  var endBilling: Bool?
  var waiveExitCharges: Bool?
  var register: Bool?
  var reason: String?
  var expectedRevision: Revision?

  mutating func place(market: String?, country: String?) throws {
    guard market == nil || country == nil else { throw ArgumentError(message: Messages.place) }
    self.market = market
    self.country = country
  }
}

private func flag(_ on: Bool) -> Bool? { on ? true : nil }

private func positiveQuantity(_ quantity: Int64) throws -> Int64 {
  guard quantity >= 1 else { throw ArgumentError(message: Messages.quantity) }
  return quantity
}

private func moveWhen(_ timing: MoveTiming) -> String {
  "SUBSCRIPTION_MOVE_WHEN_" + timing.rawValue.uppercased()
}

private func offerChoice(_ offer: OfferChoice) throws -> OfferChoiceBody {
  let key = try require(offer.key, Messages.offer)
  if let amount = offer.amount, amount < 0 { throw ArgumentError(message: Messages.offerAmount) }
  if let percent = offer.percentThousandths, !(0...100_000).contains(percent) {
    throw ArgumentError(message: Messages.percentThousandths)
  }
  guard offer.amount != nil || offer.percentThousandths != nil else {
    return OfferChoiceBody(offerKey: key)
  }
  return OfferChoiceBody(
    offerKey: key,
    value: .init(amount: offer.amount, percentThousandths: offer.percentThousandths))
}

func epochSeconds(_ date: Date, _ message: String) throws -> Int64 {
  let seconds = date.timeIntervalSince1970.rounded(.down)
  guard seconds >= 0, let value = Int64(exactly: seconds) else {
    throw ArgumentError(message: message)
  }
  return value
}

func heldPlan(_ value: Wire.HeldPlan) -> HeldPlan {
  HeldPlan(
    id: value.planId, key: value.planKey, name: value.planName, version: value.versionNumber,
    byDefault: value.byDefault, money: openName(value.money, prefix: "CUSTOMER_MONEY_"),
    period: value.periodId)
}

func decodeMove(_ body: Data) throws -> MoveStep {
  let answer = try wire(Wire.SetPlanResponse.self, body)
  if let pay = answer.pay {
    let url = try at("pay") { try at("url") { try given(URL(string: pay.url)) } }
    return .pay(url: url, status: openName(pay.status, prefix: "PAYMENT_STEP_STATUS_"))
  }
  if answer.confirming != nil { return .confirming }
  let done = try at("done") { try given(answer.done) }
  return .done(
    MoveResult(
      customerID: done.customerId, revision: done.revision,
      money: openName(done.money, prefix: "CUSTOMER_MONEY_"),
      change: done.change.map {
        PlanChange(
          product: $0.productId, plan: $0.plan.map(heldPlan), quantity: $0.quantity,
          effective: openName($0.effective, prefix: "EFFECTIVE_"), at: date($0.at),
          until: $0.until.map(date), changed: $0.changed,
          policy: openName($0.policy, prefix: "SUBSCRIPTION_MOVE_POLICY_"))
      }, holdings: try at("holdings") { try done.holdings.map(holdings) }))
}
