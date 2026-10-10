/// A feature's type.
public enum FeatureType: RawRepresentable, Hashable, Sendable, Codable {
  /// Turned on or off.
  case boolean
  /// A setting with an amount, such as seats.
  case config
  /// Counted against an allowance.
  case metered
  /// A group of other features.
  case group
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "boolean": self = .boolean
    case "config": self = .config
    case "metered": self = .metered
    case "group": self = .group
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .boolean: "boolean"
    case .config: "config"
    case .metered: "metered"
    case .group: "group"
    case .unknown(let value): value
    }
  }
}

/// The kind of an environment.
public enum EnvironmentKind: RawRepresentable, Hashable, Sendable, Codable {
  /// Sample customers and test money only.
  case test
  /// Real customers and real money.
  case live
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "test": self = .test
    case "live": self = .live
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .test: "test"
    case .live: "live"
    case .unknown(let value): value
    }
  }
}

/// An experiment's arm.
public enum Arm: RawRepresentable, Hashable, Sendable, Codable {
  /// Sees the track's release.
  case control
  /// Sees the release with the experiment's change.
  case variant
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "control": self = .control
    case "variant": self = .variant
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .control: "control"
    case .variant: "variant"
    case .unknown(let value): value
    }
  }
}

/// Whether a plan is a base plan or an add-on.
public enum PlanKind: RawRepresentable, Hashable, Sendable, Codable {
  /// A base plan.
  case plan
  /// An add-on.
  case addOn
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "plan": self = .plan
    case "addon": self = .addOn
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .plan: "plan"
    case .addOn: "addon"
    case .unknown(let value): value
    }
  }
}

/// When a change takes effect.
public enum ChangeTiming: RawRepresentable, Hashable, Sendable, Codable {
  /// At once.
  case now
  /// At renewal.
  case end
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "now": self = .now
    case "end": self = .end
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .now: "now"
    case .end: "end"
    case .unknown(let value): value
    }
  }
}

/// How a move changes the customer's plans.
public enum Move: RawRepresentable, Hashable, Sendable, Codable {
  /// Subscribes from no plan in a product.
  case subscribe
  /// Moves up to another plan.
  case upgrade
  /// Moves down to another plan.
  case downgrade
  /// Moves to another plan, neither up nor down.
  case `switch`
  /// Adds an add-on.
  case add
  /// Replaces an add-on with another.
  case replace
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "subscribe": self = .subscribe
    case "upgrade": self = .upgrade
    case "downgrade": self = .downgrade
    case "switch": self = .switch
    case "add": self = .add
    case "replace": self = .replace
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .subscribe: "subscribe"
    case .upgrade: "upgrade"
    case .downgrade: "downgrade"
    case .switch: "switch"
    case .add: "add"
    case .replace: "replace"
    case .unknown(let value): value
    }
  }
}

/// Who can make a move.
public enum MoveAction: RawRepresentable, Hashable, Sendable, Codable {
  /// The customer can make it alone: show a button that calls `subscribe`.
  case buy
  /// A sales-led move, which only the company can make: show a way to contact sales.
  case contact
  /// Neither can make it now; the reason says why.
  case unavailable
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "buy": self = .buy
    case "contact": self = .contact
    case "unavailable": self = .unavailable
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .buy: "buy"
    case .contact: "contact"
    case .unavailable: "unavailable"
    case .unknown(let value): value
    }
  }
}

/// When a plan change took effect or will.
public enum ChangeEffect: RawRepresentable, Hashable, Sendable, Codable {
  /// At once.
  case now
  /// At renewal, at the change's instant.
  case renewal
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "now": self = .now
    case "renewal": self = .renewal
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .now: "now"
    case .renewal: "renewal"
    case .unknown(let value): value
    }
  }
}

/// How a company plan change meets the payment provider.
public enum BillingMode: RawRepresentable, Hashable, Sendable, Codable {
  /// Charges the change through the provider that bills the product.
  case provider
  /// Moves the customer in Entitler while the provider keeps billing the plan it bills.
  case keep
  /// Ends the provider's subscription when the change takes effect; the customer then holds the plan outside any provider.
  case end
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "provider": self = .provider
    case "keep": self = .keep
    case "end": self = .end
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .provider: "provider"
    case .keep: "keep"
    case .end: "end"
    case .unknown(let value): value
    }
  }
}

/// How a move changes a feature.
public enum ImpactKind: RawRepresentable, Hashable, Sendable, Codable {
  /// The customer gains it.
  case gains
  /// The customer loses it.
  case loses
  /// Its value changes.
  case changes
  /// It stays the same.
  case same
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "gains": self = .gains
    case "loses": self = .loses
    case "changes": self = .changes
    case "same": self = .same
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .gains: "gains"
    case .loses: "loses"
    case .changes: "changes"
    case .same: "same"
    case .unknown(let value): value
    }
  }
}

/// How often a price is charged.
public enum PriceInterval: RawRepresentable, Hashable, Sendable, Codable {
  /// Daily.
  case day
  /// Weekly.
  case week
  /// Monthly.
  case month
  /// Yearly.
  case year
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "day": self = .day
    case "week": self = .week
    case "month": self = .month
    case "year": self = .year
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .day: "day"
    case .week: "week"
    case .month: "month"
    case .year: "year"
    case .unknown(let value): value
    }
  }
}

/// Whether a price includes tax.
public enum TaxBehaviour: RawRepresentable, Hashable, Sendable, Codable {
  /// Tax is included.
  case inclusive
  /// Tax is added.
  case exclusive
  /// Not specified.
  case unspecified
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "inclusive": self = .inclusive
    case "exclusive": self = .exclusive
    case "unspecified": self = .unspecified
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .inclusive: "inclusive"
    case .exclusive: "exclusive"
    case .unspecified: "unspecified"
    case .unknown(let value): value
    }
  }
}

/// Whether a plan is on sale.
public enum PlanStatus: RawRepresentable, Hashable, Sendable, Codable {
  /// On sale.
  case active
  /// Kept for those who hold it.
  case legacy
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "active": self = .active
    case "legacy": self = .legacy
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .active: "active"
    case .legacy: "legacy"
    case .unknown(let value): value
    }
  }
}

/// A unit of a billing period or meter window.
public enum TimeUnit: RawRepresentable, Hashable, Sendable, Codable {
  /// Hours.
  case hours
  /// Days.
  case days
  /// Weeks.
  case weeks
  /// Months.
  case months
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "hours": self = .hours
    case "days": self = .days
    case "weeks": self = .weeks
    case "months": self = .months
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .hours: "hours"
    case .days: "days"
    case .weeks: "weeks"
    case .months: "months"
    case .unknown(let value): value
    }
  }
}

/// Whether a payment connection takes real or test money.
public enum ConnectionMode: RawRepresentable, Hashable, Sendable, Codable {
  /// Real money.
  case live
  /// Test money.
  case test
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "live": self = .live
    case "test": self = .test
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .live: "live"
    case .test: "test"
    case .unknown(let value): value
    }
  }
}

/// A payment provider.
public enum Provider: RawRepresentable, Hashable, Sendable, Codable {
  /// Stripe.
  case stripe
  /// Apple's App Store.
  case apple
  /// Google Play.
  case google
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "stripe": self = .stripe
    case "apple": self = .apple
    case "google": self = .google
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .stripe: "stripe"
    case .apple: "apple"
    case .google: "google"
    case .unknown(let value): value
    }
  }
}

/// What a usage log entry records.
public enum UsageEventKind: RawRepresentable, Hashable, Sendable, Codable {
  /// A usage report.
  case use
  /// A meter set.
  case adjust
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "use": self = .use
    case "adjust": self = .adjust
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .use: "use"
    case .adjust: "adjust"
    case .unknown(let value): value
    }
  }
}

/// Where usage was reported from.
public enum UsageSource: RawRepresentable, Hashable, Sendable, Codable {
  /// A server key.
  case api
  /// A customer token or an identity token.
  case client
  /// The dashboard.
  case dashboard
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "api": self = .api
    case "client": self = .client
    case "dashboard": self = .dashboard
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .api: "api"
    case .client: "client"
    case .dashboard: "dashboard"
    case .unknown(let value): value
    }
  }
}

/// What a usage write did.
public enum UsageOutcome: RawRepresentable, Hashable, Sendable, Codable {
  /// The usage was recorded.
  case recorded
  /// A replay of an earlier request, which stands.
  case duplicate
  /// Nothing was recorded; see ``UsageResult/refusal``.
  case refused
  /// The amount is held.
  case held
  /// The hold was settled.
  case settled
  /// The hold was released.
  case released
  /// The report was cancelled.
  case cancelled
  /// The meter was set.
  case adjusted
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "recorded": self = .recorded
    case "duplicate": self = .duplicate
    case "refused": self = .refused
    case "held": self = .held
    case "settled": self = .settled
    case "released": self = .released
    case "cancelled": self = .cancelled
    case "adjusted": self = .adjusted
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .recorded: "recorded"
    case .duplicate: "duplicate"
    case .refused: "refused"
    case .held: "held"
    case .settled: "settled"
    case .released: "released"
    case .cancelled: "cancelled"
    case .adjusted: "adjusted"
    case .unknown(let value): value
    }
  }
}

/// Why a gated report or a hold was refused.
public enum UsageRefusal: RawRepresentable, Hashable, Sendable, Codable {
  /// The customer is not entitled to the feature.
  case notEntitled
  /// The amount does not fit the allowance.
  case overAllowance
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "not_entitled": self = .notEntitled
    case "over_allowance": self = .overAllowance
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .notEntitled: "not_entitled"
    case .overAllowance: "over_allowance"
    case .unknown(let value): value
    }
  }
}

/// How a usage report meets the allowance.
public enum UsageMode: RawRepresentable, Hashable, Sendable, Codable {
  /// Records only if the amount fits the allowance, else answers refused.
  case gate
  /// Always records, and says how far past the allowance the meter is.
  case observe
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "gate": self = .gate
    case "observe": self = .observe
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .gate: "gate"
    case .observe: "observe"
    case .unknown(let value): value
    }
  }
}

/// The state of a usage hold.
public enum HoldState: RawRepresentable, Hashable, Sendable, Codable {
  /// Counting against the allowance.
  case open
  /// Settled with the real amount.
  case settled
  /// Released.
  case released
  /// Expired before it was settled or released.
  case expired
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "open": self = .open
    case "settled": self = .settled
    case "released": self = .released
    case "expired": self = .expired
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .open: "open"
    case .settled: "settled"
    case .released: "released"
    case .expired: "expired"
    case .unknown(let value): value
    }
  }
}

/// What happened to one event of a batch.
public enum UsageEventOutcome: RawRepresentable, Hashable, Sendable, Codable {
  /// The event was recorded.
  case recorded
  /// The key was used before for the same event.
  case duplicate
  /// The event was not recorded; see ``UsageEventResult/error``.
  case error
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "recorded": self = .recorded
    case "duplicate": self = .duplicate
    case "error": self = .error
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .recorded: "recorded"
    case .duplicate: "duplicate"
    case .error: "error"
    case .unknown(let value): value
    }
  }
}

/// How a customer pays.
public enum CustomerKind: RawRepresentable, Hashable, Sendable, Codable {
  /// A recurring subscription.
  case recurring
  /// One-time purchases.
  case oneTime
  /// A change is under way.
  case changing
  /// The default plan.
  case `default`
  /// Nothing.
  case none
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "recurring": self = .recurring
    case "one_time": self = .oneTime
    case "changing": self = .changing
    case "default": self = .default
    case "none": self = .none
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .recurring: "recurring"
    case .oneTime: "one_time"
    case .changing: "changing"
    case .default: "default"
    case .none: "none"
    case .unknown(let value): value
    }
  }
}

/// The status of a provider subscription.
public enum BillingStatus: RawRepresentable, Hashable, Sendable, Codable {
  /// The first payment has not succeeded.
  case incomplete
  /// The first payment never succeeded.
  case incompleteExpired
  /// In a trial.
  case trialing
  /// Active.
  case active
  /// A renewal payment failed.
  case pastDue
  /// Cancelled.
  case canceled
  /// Unpaid.
  case unpaid
  /// Paused.
  case paused
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "incomplete": self = .incomplete
    case "incomplete_expired": self = .incompleteExpired
    case "trialing": self = .trialing
    case "active": self = .active
    case "past_due": self = .pastDue
    case "canceled": self = .canceled
    case "unpaid": self = .unpaid
    case "paused": self = .paused
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .incomplete: "incomplete"
    case .incompleteExpired: "incomplete_expired"
    case .trialing: "trialing"
    case .active: "active"
    case .pastDue: "past_due"
    case .canceled: "canceled"
    case .unpaid: "unpaid"
    case .paused: "paused"
    case .unknown(let value): value
    }
  }
}

/// Who put a customer on their track.
public enum TrackSource: RawRepresentable, Hashable, Sendable, Codable {
  /// The vendor's server.
  case server
  /// A person in the dashboard.
  case dashboard
  /// A verified sandbox build of the app.
  case storeSandbox
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "server": self = .server
    case "dashboard": self = .dashboard
    case "store_sandbox": self = .storeSandbox
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .server: "server"
    case .dashboard: "dashboard"
    case .storeSandbox: "store_sandbox"
    case .unknown(let value): value
    }
  }
}

/// Whether a purchase used real or test money.
public enum Money: RawRepresentable, Hashable, Sendable, Codable {
  /// Money that is charged.
  case real
  /// Test money, never charged.
  case test
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "real": self = .real
    case "test": self = .test
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .real: "real"
    case .test: "test"
    case .unknown(let value): value
    }
  }
}

/// Why a payment has not succeeded.
public enum PaymentStatus: RawRepresentable, Hashable, Sendable, Codable {
  /// The card was declined.
  case declined
  /// The customer must confirm it.
  case requiresAction
  /// The provider is still processing it.
  case processing
  /// The provider gave no reason.
  case pending
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "declined": self = .declined
    case "requires_action": self = .requiresAction
    case "processing": self = .processing
    case "pending": self = .pending
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .declined: "declined"
    case .requiresAction: "requires_action"
    case .processing: "processing"
    case .pending: "pending"
    case .unknown(let value): value
    }
  }
}

/// Why a listing leaves a plan and period blank.
public enum ListingGapKind: RawRepresentable, Hashable, Sendable, Codable {
  /// The listing stops selling it.
  case stopsSelling
  /// Nothing lists it.
  case unlisted
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "stops_selling": self = .stopsSelling
    case "unlisted": self = .unlisted
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .stopsSelling: "stops_selling"
    case .unlisted: "unlisted"
    case .unknown(let value): value
    }
  }
}

/// Why a listing's price fails the checks.
public enum ListingProblemKind: RawRepresentable, Hashable, Sendable, Codable {
  /// The price does not exist.
  case priceNotFound
  /// The price is inactive.
  case priceInactive
  /// The price's interval differs from the period.
  case intervalMismatch
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "price_not_found": self = .priceNotFound
    case "price_inactive": self = .priceInactive
    case "interval_mismatch": self = .intervalMismatch
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .priceNotFound: "price_not_found"
    case .priceInactive: "price_inactive"
    case .intervalMismatch: "interval_mismatch"
    case .unknown(let value): value
    }
  }
}

/// Where an entitlement comes from.
public enum EntitlementSourceType: RawRepresentable, Hashable, Sendable, Codable {
  /// A plan the customer holds.
  case plan
  /// An add-on the customer holds.
  case addOn
  /// A grant.
  case grant
  /// Banked credits.
  case banked
  /// A group's members.
  case group
  /// A value this SDK does not know yet.
  case unknown(String)

  /// Creates the value from the API's string.
  public init(rawValue: String) {
    switch rawValue {
    case "plan": self = .plan
    case "addon": self = .addOn
    case "grant": self = .grant
    case "banked": self = .banked
    case "group": self = .group
    default: self = .unknown(rawValue)
    }
  }

  /// The API's string for the value.
  public var rawValue: String {
    switch self {
    case .plan: "plan"
    case .addOn: "addon"
    case .grant: "grant"
    case .banked: "banked"
    case .group: "group"
    case .unknown(let value): value
    }
  }
}
