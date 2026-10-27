import Foundation

/// An add-on the customer holds.
public struct HeldAddOn: Hashable, Sendable {
  /// The add-on's id.
  public let id: String
  /// The add-on's key.
  public let key: String
  /// The add-on's name.
  public let name: String
  /// The add-on's version the customer holds.
  public let version: Int64
  /// `real` when the customer pays real money for it, `test` in test mode.
  public let money: OpenName
  /// How many the customer holds.
  public let quantity: Int64
  /// True when the plan requires it, so the customer can't remove it.
  public let required: Bool
  /// When it was added.
  public let addedAt: Date
}

/// A discount the customer holds.
public struct HeldDiscount: Hashable, Sendable {
  /// The offer's key.
  public let offerKey: String
  /// The offer's name.
  public let offerName: String
  /// A fixed amount off, or `nil`.
  public let amount: Amount?
  /// A percentage off in thousandths of a percent, or `nil`.
  public let percentThousandths: Int64?
  /// When it ends, or `nil`.
  public let until: Date?
  /// True when it applies to what the customer pays now.
  public let applied: Bool
}

/// A change booked for the next renewal.
public struct PendingChange: Hashable, Sendable {
  /// When it takes effect.
  public let at: Date
  /// True when the subscription ends then.
  public let cancel: Bool
  /// The id of the plan the customer moves to, or `nil`.
  public let plan: String?
  /// The id of the billing period they move to, or `nil`.
  public let period: String?
}

/// A subscription's cancellation.
public struct Cancellation: Hashable, Sendable {
  /// When it ends.
  public let endsAt: Date
  /// The fee for leaving early, or `nil`.
  public let exitFee: Amount?
  /// What discounts given for staying cost back, or `nil`.
  public let chargedBack: Amount?
}

/// What the customer pays next.
public struct LanePayment: Hashable, Sendable {
  /// The amount, or `nil`.
  public let amount: Amount?
  /// When it is due, or `nil`.
  public let dueAt: Date?
  /// The days an invoice gives to pay, or `nil`.
  public let days: Int64?
}

/// What the customer holds in one product.
public struct Lane: Hashable, Sendable {
  /// The product's id, or `nil`.
  public let product: String?
  /// The plan held, or `nil`.
  public let plan: HeldPlan?
  /// The add-ons held.
  public let addOns: [HeldAddOn]
  /// When the subscription started, or `nil`.
  public let startedAt: Date?
  /// When it next renews, or `nil`.
  public let renewsAt: Date?
  /// When the trial ends, or `nil`.
  public let trialEndsAt: Date?
  /// When it is cancelled from, or `nil`.
  public let cancelsAt: Date?
  /// When it is paid until, or `nil`.
  public let paidUntil: Date?
  /// When the plan ends, such as a store purchase's expiry, or `nil`.
  public let until: Date?
  /// Who collects payment: `provider`, `business` or `not_charged`.
  public let collection: OpenName
  /// The change booked for the next renewal, or `nil`.
  public let pending: PendingChange?
  /// The cancellation, or `nil`.
  public let cancellation: Cancellation?
  /// The discounts held.
  public let discounts: [HeldDiscount]
  /// What the customer pays next.
  public let payment: LanePayment
}

/// What the customer holds: a lane per product, and their grants.
public struct Holdings: Hashable, Sendable {
  /// A lane per product.
  public let lanes: [Lane]
  /// The grants.
  public let grants: [Grant]
}

/// What moving to a plan would do to one feature.
public struct FeatureImpact: Hashable, Sendable {
  /// The feature's key.
  public let feature: String
  /// `gains`, `loses` or `changes`.
  public let kind: OpenName
  /// The value now, or `nil`.
  public let from: FeatureValue?
  /// The value after the move, or `nil`.
  public let to: FeatureValue?
  /// A money value's limits now, by market id, or `nil`.
  public let fromMarkets: [String: Limit]?
  /// A money value's limits after the move, by market id, or `nil`.
  public let toMarkets: [String: Limit]?
}

/// A plan, named.
public struct NamedPlan: Hashable, Sendable {
  /// The plan's id.
  public let id: String
  /// The plan's key.
  public let key: String
  /// The plan's name.
  public let name: String
}

/// A plan or add-on the customer can move to.
public struct PlanOption: Hashable, Sendable {
  /// The plan.
  public let plan: NamedPlan
  /// The product's id, or `nil`.
  public let product: String?
  /// `subscribe`, `move`, `add` or `replace`.
  public let kind: OpenName
  /// `up`, `cross` or `down`.
  public let direction: OpenName
  /// `self_serve`, or `sales_led` when only the company sells it.
  public let selling: OpenName
  /// `now_keep`, `now_new` or `period_end`.
  public let timing: OpenName
  /// The ids of the billing periods it is sold for.
  public let periods: [String]
  /// The id of the plan it replaces, or `nil`.
  public let replaces: String?
  /// What moving would do to each feature.
  public let impact: [FeatureImpact]
}

/// The plans the customer can move to, and what they hold now.
public struct CustomerPlans: Hashable, Sendable, StaleMarking {
  /// The instant the answer was computed for.
  public let asOf: Date
  /// Entitler's id for the customer, or `nil` before they are registered.
  public let customerID: String?
  /// The plans and add-ons they can move to.
  public let options: [PlanOption]
  /// What they hold, or `nil`.
  public let holdings: Holdings?
  /// True only when the SDK answered from a kept copy because Entitler was unreachable.
  public internal(set) var stale = false
}

/// The billed plan's price at the payment provider.
public struct BilledSKU: Hashable, Sendable {
  /// The provider's price id.
  public let priceID: String
  /// The id of the billing period, or `nil`.
  public let period: String?
  /// The provider's price, or `nil`.
  public let price: ListingPrice?
}

/// A difference between what the payment provider bills and what the customer holds.
public struct BillingDrift: Hashable, Sendable {
  /// The id of the plan billed.
  public let billedPlan: String
  /// The id of the plan held, or `nil`.
  public let heldPlan: String?
  /// The product's id, or `nil`.
  public let product: String?
  /// When it was seen.
  public let observedAt: Date
}

/// One product's billing at the payment provider.
public struct BilledProduct: Hashable, Sendable {
  /// The product's id, or `nil`.
  public let product: String?
  /// The billing connection's id.
  public let connectionID: String
  /// The provider's subscription status, such as `active`, `trialing` or `past_due`.
  public let status: OpenName
  /// How many items the subscription bills.
  public let items: Int64
  /// True when it renews.
  public let renews: Bool
  /// The billed price, or `nil`.
  public let sku: BilledSKU?
  /// A difference from what the customer holds, or `nil`.
  public let drift: BillingDrift?
}

/// The customer's billing at the payment provider.
public struct CustomerBilling: Hashable, Sendable {
  /// True when the customer is linked to a payment provider. An unlinked customer answers
  /// status `unspecified` and no products.
  public let linked: Bool
  /// The billing connection's id, or `nil`.
  public let connectionID: String?
  /// The provider's subscription status: `active`, `trialing`, `past_due`, `incomplete`,
  /// `incomplete_expired`, `canceled`, `unpaid` or `paused`.
  public let status: OpenName
  /// How many items the subscription bills.
  public let items: Int64
  /// True when it renews.
  public let renews: Bool
  /// The billed price, or `nil`.
  public let sku: BilledSKU?
  /// A difference from what the customer holds, or `nil`.
  public let drift: BillingDrift?
  /// Each product's billing.
  public let products: [BilledProduct]
}

extension Customer {
  /// Reads the plans the customer can move to, each with what moving would do, and what they
  /// hold now: a lane per product with its plan, add-ons, dates and booked changes, and their
  /// grants. In an app it needs the `billing:self` scope.
  public func plans(asOf: Date? = nil, revalidate: Bool = false, timeout: TimeInterval? = nil)
    async throws -> CustomerPlans
  {
    var request = try Wire.subscriptionsListAvailablePlans.request(
      ["external_id": id], query: try asOfQuery(asOf))
    request.revalidate = revalidate
    request.timeout = timeout
    return try await core.cachedCall(request, decode: decodePlans)
  }

  /// Opens the payment provider's page for payment details and invoices, and answers its URL. It
  /// changes no plan. In an app it needs the `billing:self` scope and the customer portal on the
  /// team's plan, and takes one call every 10 seconds per customer.
  ///
  /// - Parameter returnURL: Where the provider's page sends the customer back to.
  public func billingPortal(returnURL: URL, timeout: TimeInterval? = nil) async throws -> URL {
    var request = try Wire.billingCreatePortalSession.request(["external_id": id])
    request.body = try JSONEncoder().encode(["returnUrl": returnURL.absoluteString])
    request.timeout = timeout
    return try await core.call(request, decode: decodePortal).answer
  }

  /// Reads the customer's state from the payment provider now, so the screen they return to after
  /// paying shows the plan they paid for, then read ``plans(asOf:revalidate:timeout:)``. In an app
  /// it needs the `billing:self` scope and the customer portal on the team's plan, and takes one
  /// call every 10 seconds per customer.
  ///
  /// - Returns: True when the provider's state changed what the customer holds.
  @discardableResult
  public func syncBilling(timeout: TimeInterval? = nil) async throws -> Bool {
    var request = try Wire.billingSyncBilling.request(["external_id": id])
    request.body = Data("{}".utf8)
    request.retryable = true
    request.timeout = timeout
    return try await core.call(request) { try wire(Wire.SyncBillingResponse.self, $0).changed }
      .answer
  }
}

extension ServerCustomer {
  /// Reads the customer's billing at the payment provider. A customer Entitler links to no
  /// provider answers `linked` false. Billing screens read ``Customer/plans(asOf:revalidate:timeout:)``.
  public func billing(timeout: TimeInterval? = nil) async throws -> CustomerBilling {
    var request = try Wire.billingGetBilling.request(["external_id": id])
    request.timeout = timeout
    return try await core.call(request, decode: decodeBilling).answer
  }
}

func holdings(_ value: Wire.Holdings) throws -> Holdings {
  Holdings(lanes: value.lanes.map(lane), grants: try at("grants") { try value.grants.map(grant) })
}

private func lane(_ value: Wire.LaneHolding) -> Lane {
  Lane(
    product: value.productId, plan: value.plan.map(heldPlan),
    addOns: value.addOns.map {
      HeldAddOn(
        id: $0.planId, key: $0.planKey, name: $0.planName, version: $0.versionNumber,
        money: openName($0.money, prefix: "CUSTOMER_MONEY_"), quantity: $0.quantity,
        required: $0.required, addedAt: date($0.addedAt))
    },
    startedAt: value.startedAt.map(date), renewsAt: value.renewsAt.map(date),
    trialEndsAt: value.trialEndsAt.map(date), cancelsAt: value.cancelsAt.map(date),
    paidUntil: value.paidUntil.map(date), until: value.until.map(date),
    collection: openName(value.collection, prefix: "SUBSCRIPTION_COLLECTION_"),
    pending: value.pending.map {
      PendingChange(
        at: date($0.at), cancel: $0.cancel != nil, plan: $0.move?.planId,
        period: $0.move?.periodId)
    },
    cancellation: value.cancellation.map {
      Cancellation(
        endsAt: date($0.endsAt), exitFee: $0.exitFee.map(amount),
        chargedBack: $0.chargedBack.map(amount))
    },
    discounts: value.discounts.map {
      HeldDiscount(
        offerKey: $0.offerKey, offerName: $0.offerName, amount: $0.amount.map(amount),
        percentThousandths: $0.percentThousandths, until: $0.until.map(date),
        applied: $0.applied)
    },
    payment: LanePayment(
      amount: value.paymentAmount.map(amount), dueAt: value.paymentDueAt.map(date),
      days: value.paymentDays))
}

private func planOption(_ value: Wire.PlanOption) throws -> PlanOption {
  PlanOption(
    plan: NamedPlan(id: value.planId, key: value.planKey, name: value.planName),
    product: value.productId, kind: openName(value.kind, prefix: "OPTION_KIND_"),
    direction: openName(value.direction, prefix: "PLAN_DIRECTION_"),
    selling: openName(value.selling, prefix: "SELLING_"),
    timing: openName(value.timing, prefix: "MOVE_TIMING_"), periods: value.periodIds,
    replaces: value.replacesPlanId,
    impact: try value.impact.map {
      FeatureImpact(
        feature: $0.featureKey, kind: openName($0.kind, prefix: "IMPACT_KIND_"),
        from: try $0.from.map { try featureValue($0, entitled: true) },
        to: try $0.to.map { try featureValue($0, entitled: true) }, fromMarkets: markets($0.from),
        toMarkets: markets($0.to))
    })
}

func decodePlans(_ body: Data) throws -> CustomerPlans {
  let answer = try wire(Wire.ListAvailablePlansResponse.self, body)
  return CustomerPlans(
    asOf: date(answer.asOf), customerID: answer.customerId,
    options: try at("options") { try answer.options.map(planOption) },
    holdings: try at("holdings") { try answer.holdings.map(holdings) })
}

private func sku(_ value: Wire.BilledSku) -> BilledSKU {
  BilledSKU(priceID: value.priceId, period: value.periodId, price: value.price.map(listingPrice))
}

private func drift(_ value: Wire.BillingDrift) -> BillingDrift {
  BillingDrift(
    billedPlan: value.billedPlanId, heldPlan: value.heldPlanId, product: value.productId,
    observedAt: date(value.observedAt))
}

private let providerStatus = "PROVIDER_SUBSCRIPTION_STATUS_"

func decodeBilling(_ body: Data) throws -> CustomerBilling {
  guard let billing = try wire(Wire.GetBillingResponse.self, body).billing else {
    return CustomerBilling(
      linked: false, connectionID: nil, status: OpenName(rawValue: "unspecified"), items: 0,
      renews: false, sku: nil, drift: nil, products: [])
  }
  return CustomerBilling(
    linked: billing.linked, connectionID: billing.connectionId,
    status: openName(billing.status, prefix: providerStatus), items: billing.items,
    renews: billing.renews, sku: billing.sku.map(sku), drift: billing.drift.map(drift),
    products: billing.products.map {
      BilledProduct(
        product: $0.productId, connectionID: $0.connectionId,
        status: openName($0.status, prefix: providerStatus), items: $0.items, renews: $0.renews,
        sku: $0.sku.map(sku), drift: $0.drift.map(drift))
    })
}

func decodePortal(_ body: Data) throws -> URL {
  let answer = try wire(Wire.CreatePortalSessionResponse.self, body)
  return try at("url") { try given(URL(string: answer.url)) }
}
