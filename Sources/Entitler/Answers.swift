import Foundation

/// The environment an answer comes from.
public struct AnswerEnvironment: Codable, Hashable, Sendable {
  /// The environment's id.
  public let id: String
  /// The environment's name, such as `development`.
  public let name: String
  /// Whether it is a test or a live environment.
  public let kind: EnvironmentKind
}

/// A track: the catalogue on sale to its customers.
public struct Track: Codable, Hashable, Sendable {
  /// The track's id.
  public let id: String
  /// The track's name, such as `All customers`.
  public let name: String
}

/// The experiment a customer or visitor is in, and their arm.
public struct ExperimentAssignment: Codable, Hashable, Sendable {
  /// The experiment's id.
  public let id: String
  /// The arm they see.
  public let arm: Arm
}

/// A plan or add-on, as answers name one.
public struct PlanRef: Codable, Hashable, Sendable {
  /// The plan's public id.
  public let id: String
  /// The plan's key, such as `pro`.
  public let key: String
  /// The plan's name.
  public let name: String
  /// Whether it is a base plan or an add-on, where the answer says.
  public let kind: PlanKind?
  /// The version held, where the answer says.
  public let version: Int64?
  /// The product's key, where the answer says.
  public let product: String?
}

/// A product: plans in one product exclude each other.
public struct Product: Codable, Hashable, Sendable {
  /// The product's key.
  public let key: String
  /// The product's name.
  public let name: String
}

/// Where an entitlement comes from.
public struct EntitlementSource: Codable, Hashable, Sendable {
  /// The kind of source.
  public let type: EntitlementSourceType
  /// The plan or add-on's key, for a plan or add-on.
  public let plan: String?
  /// The plan or add-on's name, for a plan or add-on.
  public let name: String?
  /// The plan or add-on's version, for a plan or add-on.
  public let version: Int64?
  /// Whether the plan is held because it is the default, for a plan.
  public let byDefault: Bool?
  /// How many of the add-on are held, for an add-on.
  public let quantity: Int64?
  /// The grant's id, for a grant.
  public let grant: String?
  /// When the grant ends, for a grant; `nil` when it never does.
  public let until: Date?
  /// The value this source gives.
  public let value: FeatureValue?
  /// The group's members that decide it, for a group.
  public let features: [String]?
}

/// A plan that would give a feature the customer lacks.
public struct Upgrade: Codable, Hashable, Sendable {
  /// The plan's key.
  public let plan: String
  /// The plan's name.
  public let name: String
  /// How the customer would take it.
  public let move: UpgradeMove
  /// Whether only the vendor can make the move.
  public let salesLed: Bool
}

/// Whether a customer is entitled to one feature, with its value and sources.
///
/// `check(_:timeout:)` answers a ``MeteredCheck`` for metered features instead.
public struct Check: Codable, Hashable, Sendable, StaleMarking {
  /// The customer's external id.
  public let customer: String
  /// The instant the answer is for.
  public let asOf: Date
  /// The feature's key.
  public let feature: String
  /// The feature's type.
  public let type: FeatureType
  /// Whether the customer is entitled: Entitler's decision, never derived from ``value``.
  public let entitled: Bool
  /// The feature's value for the customer.
  public let value: FeatureValue
  /// Where the value comes from.
  public let sources: [EntitlementSource]
  /// For a metered feature, how much is used this period.
  public let used: Int64?
  /// For a metered feature, how much open holds reserve.
  public let held: Int64?
  /// For a metered feature, how much is left.
  public let remaining: FeatureValue?
  /// For a metered feature, when the meter resets; `nil` when it never does.
  public let resetsAt: Date?
  /// When not entitled, the plans that would give the feature.
  public let upgrades: [Upgrade]
  /// The environment the answer comes from.
  public let environment: AnswerEnvironment
  /// The customer's track.
  public let track: Track
  /// The release the track serves, or `nil` when it follows a change.
  public let release: Int64?
  /// The change the track follows, or `nil` when it serves a release.
  public let change: String?
  /// Whether test money is taken: a track for testers, or a test environment.
  public let testers: Bool
  /// The experiment the customer is in, if any.
  public let experiment: ExperimentAssignment?
  /// True only when the SDK answered from a kept copy because Entitler was unreachable.
  public internal(set) var stale = false

  enum CodingKeys: String, CodingKey {
    case customer, asOf, feature, type, entitled, value, sources, used, held, remaining, resetsAt
    case upgrades, environment, track, release, change, testers, experiment
  }
}

/// Whether a customer is entitled to a metered feature, with its meter.
public struct MeteredCheck: Codable, Hashable, Sendable, StaleMarking {
  /// The customer's external id.
  public let customer: String
  /// The instant the answer is for.
  public let asOf: Date
  /// The feature's key.
  public let feature: String
  /// The feature's type.
  public let type: FeatureType
  /// Whether the customer is entitled: Entitler's decision, never derived from ``value``.
  public let entitled: Bool
  /// The allowance.
  public let value: FeatureValue
  /// Where the allowance comes from.
  public let sources: [EntitlementSource]
  /// How much is used this period.
  public let used: Int64
  /// How much open holds reserve, counted in ``remaining``.
  public let held: Int64
  /// How much is left.
  public let remaining: FeatureValue
  /// When the meter resets; `nil` when it never does.
  public let resetsAt: Date?
  /// When not entitled, the plans that would give the feature.
  public let upgrades: [Upgrade]
  /// The environment the answer comes from.
  public let environment: AnswerEnvironment
  /// The customer's track.
  public let track: Track
  /// The release the track serves, or `nil` when it follows a change.
  public let release: Int64?
  /// The change the track follows, or `nil` when it serves a release.
  public let change: String?
  /// Whether test money is taken: a track for testers, or a test environment.
  public let testers: Bool
  /// The experiment the customer is in, if any.
  public let experiment: ExperimentAssignment?
  /// True only when the SDK answered from a kept copy because Entitler was unreachable.
  public internal(set) var stale = false

  enum CodingKeys: String, CodingKey {
    case customer, asOf, feature, type, entitled, value, sources, used, held, remaining, resetsAt
    case upgrades, environment, track, release, change, testers, experiment
  }
}

/// One feature a customer holds, in ``Entitlements``.
public struct Entitlement: Codable, Hashable, Sendable {
  /// The feature's key.
  public let key: String
  /// The feature's type.
  public let type: FeatureType
  /// Whether the customer is entitled: Entitler's decision, never derived from ``value``.
  public let entitled: Bool
  /// The feature's value for the customer.
  public let value: FeatureValue
  /// Where the value comes from; a group's source names its members.
  public let sources: [EntitlementSource]
  /// For a metered feature, how much is used this period.
  public let used: Int64?
  /// For a metered feature, how much open holds reserve.
  public let held: Int64?
  /// For a metered feature, how much is left.
  public let remaining: FeatureValue?
  /// For a metered feature, when the meter resets.
  public let resetsAt: Date?
}

/// Every entitlement a customer holds, groups included, with Entitler's decision on each.
public struct Entitlements: Codable, Hashable, Sendable, StaleMarking {
  /// The customer's external id.
  public let customer: String
  /// The instant the answer is for.
  public let asOf: Date
  /// The entitlements, groups included.
  public let items: [Entitlement]
  /// The environment the answer comes from; `nil` in a verified snapshot, which names only its id.
  public let environment: AnswerEnvironment?
  /// The customer's track.
  public let track: Track
  /// The release the track serves, or `nil` when it follows a change.
  public let release: Int64?
  /// The change the track follows, or `nil` when it serves a release.
  public let change: String?
  /// Whether test money is taken: a track for testers, or a test environment.
  public let testers: Bool
  /// The experiment the customer is in, if any.
  public let experiment: ExperimentAssignment?
  /// True only when the SDK answered from a kept copy because Entitler was unreachable.
  public internal(set) var stale = false

  enum CodingKeys: String, CodingKey {
    case customer, asOf, environment, track, release, change, testers, experiment
    case items = "entitlements"
  }

  /// The entitlement to a feature, or `nil` when the list does not hold it.
  public subscript<Kind>(feature: Feature<Kind>) -> Entitlement? { self[feature.key] }

  /// The entitlement to the feature with this key, or `nil` when the list does not hold it.
  public subscript(key: String) -> Entitlement? { items.first { $0.key == key } }

  /// Whether the customer is entitled to a feature: false when the list does not hold it.
  ///
  /// Groups carry Entitler's decision, so this never expands a group itself.
  public func has<Kind>(_ feature: Feature<Kind>) -> Bool { has(feature.key) }

  /// Whether the customer is entitled to the feature with this key.
  public func has(_ key: String) -> Bool { self[key]?.entitled ?? false }
}

/// A plan the customer holds, in ``CustomerPlans``.
public struct HeldPlan: Codable, Hashable, Sendable {
  /// The plan.
  public let plan: PlanRef
  /// The product it is in; `nil` for an add-on for every product.
  public let product: Product?
  /// The version held.
  public let version: Int64?
  /// Whether it is held because it is the product's default.
  public let byDefault: Bool
}

/// What a move would change about a feature.
public struct Impact: Codable, Hashable, Sendable {
  /// How the feature changes.
  public let kind: ImpactKind
  /// A sentence fit to show the customer.
  public let text: String
}

/// A price read through a payment provider.
public struct ProviderPrice: Codable, Hashable, Sendable {
  /// The amount in the currency's smallest unit.
  public let amount: Int64
  /// The ISO currency code, lower case.
  public let currency: String
  /// How often it is charged; `nil` when charged once.
  public let interval: PriceInterval?
  /// How many intervals each charge covers.
  public let intervalCount: Int64
  /// Whether the amount includes tax.
  public let tax: TaxBehaviour
}

/// A way to buy a plan through a connector, such as a Stripe price or an App Store product.
public struct OfferedSKU: Codable, Hashable, Sendable {
  /// The billing period it sells.
  public let period: String
  /// The connector, such as `stripe` or `apple`.
  public let connector: String
  /// The provider's ids.
  public let ids: [String: String]
  /// The price, when the provider reports one.
  public let price: ProviderPrice?
}

/// A plan or add-on a customer can move to, in ``CustomerPlans``.
public struct MoveOption: Codable, Hashable, Sendable {
  /// The plan or add-on.
  public let plan: PlanRef
  /// The product it is in.
  public let product: Product?
  /// How it changes the customer's plans.
  public let move: MoveKind
  /// The plan or add-on it replaces.
  public let from: PlanRef?
  /// Up, down or across.
  public let direction: MoveDirection
  /// How the path to it is sold.
  public let mode: SellingMode
  /// Whether the customer can take it alone.
  public let selfServe: Bool
  /// Why it cannot be taken now, fit to show the customer.
  public let disabledReason: String?
  /// When it would apply.
  public let when: ChangeTiming
  /// What it would change.
  public let impact: [Impact]
  /// The ways to buy it.
  public let skus: [OfferedSKU]
}

/// The plans and add-ons a customer holds, and every one they can move to.
public struct CustomerPlans: Codable, Hashable, Sendable, StaleMarking {
  /// The customer's external id.
  public let customer: String
  /// The instant the answer is for.
  public let asOf: Date
  /// The plans and add-ons they hold.
  public let held: [HeldPlan]
  /// Every plan and add-on their paths reach.
  public let options: [MoveOption]
  /// The environment the answer comes from.
  public let environment: AnswerEnvironment
  /// The customer's track.
  public let track: Track
  /// The release the track serves, or `nil` when it follows a change.
  public let release: Int64?
  /// The change the track follows, or `nil` when it serves a release.
  public let change: String?
  /// Whether test money is taken: a track for testers, or a test environment.
  public let testers: Bool
  /// The experiment the customer is in, if any.
  public let experiment: ExperimentAssignment?
  /// True only when the SDK answered from a kept copy because Entitler was unreachable.
  public internal(set) var stale = false

  enum CodingKeys: String, CodingKey {
    case customer, asOf, held, options, environment, track, release, change, testers, experiment
  }
}

/// A product as the pricing names it.
public struct PublishedProduct: Codable, Hashable, Sendable {
  /// The product's key.
  public let key: String
  /// The product's name.
  public let name: String
  /// The key of the product's default plan.
  public let defaultPlan: String?
}

/// A billing period a plan is sold for.
public struct BillingPeriod: Codable, Hashable, Sendable {
  /// The period's label, such as `monthly`.
  public let label: String
  /// How many units it lasts.
  public let count: Int64
  /// The unit.
  public let unit: TimeUnit
}

/// One of the environment's payment connections.
public struct Channel: Codable, Hashable, Sendable {
  /// The provider.
  public let provider: Provider
  /// The connection's id.
  public let connectionID: String

  enum CodingKeys: String, CodingKey {
    case provider
    case connectionID = "connectionId"
  }
}

/// How a plan's period sells on one connection.
public struct ChannelListing: Codable, Hashable, Sendable {
  /// The connection.
  public let channel: Channel
  /// The connection's name.
  public let name: String
  /// For Stripe, whether it takes live or test money.
  public let mode: ConnectionMode?
  /// Whether it can be bought there.
  public let purchasable: Bool
  /// The ids to buy it with, or `nil` when unlisted.
  public let ids: [String: String]?
  /// For Stripe, the price read through the connection.
  public let price: ProviderPrice?
}

/// How one billing period of a plan sells on each connection.
public struct PeriodListing: Codable, Hashable, Sendable {
  /// The billing period's label.
  public let period: String
  /// One entry per connection, oldest first.
  public let channels: [ChannelListing]
}

/// A plan on sale, in ``Pricing``.
public struct PricingPlan: Codable, Hashable, Sendable {
  /// The plan's public id.
  public let id: String
  /// The plan's key.
  public let key: String
  /// The plan's name.
  public let name: String
  /// The plan's description.
  public let description: String
  /// A base plan or an add-on.
  public let kind: PlanKind
  /// The product's key, or `nil` for an add-on for every product.
  public let product: String?
  /// Whether only the vendor sells it.
  public let salesLed: Bool
  /// Whether it is on sale or kept for those who hold it.
  public let status: PlanStatus
  /// Its version.
  public let version: Int64?
  /// Whether it is the product's default plan.
  public let isDefault: Bool
  /// The billing periods it is sold for.
  public let periods: [BillingPeriod]
  /// For an add-on, the plans it goes with.
  public let attachesTo: [String]
  /// Its features and their values, by key.
  public let features: [String: FeatureValue]
  /// How each period sells on each connection.
  public let listings: [PeriodListing]

  enum CodingKeys: String, CodingKey {
    case id, key, name, description, kind, product, salesLed, status, version, periods
    case attachesTo, features, listings
    case isDefault = "default"
  }
}

/// The plans on sale, for a pricing page.
///
/// Pricing is always computed now, whatever ``EntitlerOptions/asOf`` says.
public struct Pricing: Codable, Hashable, Sendable, StaleMarking {
  /// The environment the answer comes from.
  public let environment: AnswerEnvironment
  /// The track whose catalogue is on sale.
  public let track: Track
  /// The release the track serves, or `nil` when it follows a change.
  public let release: Int64?
  /// The change the track follows, or `nil` when it serves a release.
  public let change: String?
  /// Whether test money is taken: a track for testers, or a test environment.
  public let testers: Bool
  /// The experiment the visitor or customer is in, if any.
  public let experiment: ExperimentAssignment?
  /// The customer's external id, or `nil` for a signed-out visitor.
  public let customer: String?
  /// The key of the default plan.
  public let defaultPlan: String?
  /// The products.
  public let products: [PublishedProduct]
  /// The plans on sale.
  public let plans: [PricingPlan]
  /// True only when the SDK answered from a kept copy because Entitler was unreachable.
  public internal(set) var stale = false

  enum CodingKeys: String, CodingKey {
    case environment, track, release, change, testers, experiment, customer, defaultPlan
    case products, plans
  }
}

/// How often a meter resets.
public struct MeterWindow: Codable, Hashable, Sendable {
  /// How many units.
  public let count: Int64
  /// The unit.
  public let unit: TimeUnit
}

/// A feature on sale, in ``FeatureList``.
public struct FeatureListing: Codable, Hashable, Sendable {
  /// The feature's id.
  public let id: String
  /// The feature's key.
  public let key: String
  /// The feature's name.
  public let name: String
  /// The feature's type.
  public let type: FeatureType
  /// The feature's description.
  public let description: String
  /// The unit it is counted in, or empty.
  public let unit: String
  /// For a metered feature with its own window, how often it resets.
  public let resetEvery: MeterWindow?
  /// Whether the feature is archived.
  public let archived: Bool
  /// For a group, its direct members' keys.
  public let includes: [String]
}

/// The features of the catalogue the All customers track serves.
public struct FeatureList: Codable, Hashable, Sendable, StaleMarking {
  /// The environment the answer comes from.
  public let environment: AnswerEnvironment
  /// The track read.
  public let track: Track
  /// The release the track serves, or `nil` when it follows a change.
  public let release: Int64?
  /// The change the track follows, or `nil` when it serves a release.
  public let change: String?
  /// The features.
  public let features: [FeatureListing]
  /// True only when the SDK answered from a kept copy because Entitler was unreachable.
  public internal(set) var stale = false

  enum CodingKeys: String, CodingKey {
    case environment, track, release, change, features
  }
}

/// A page of a paged answer.
public struct Page<Item: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
  /// The items on this page.
  public let items: [Item]
  /// The cursor of the next page, or `nil` on the last page.
  public let next: String?
}

/// An entry of the usage log.
public struct UsageEvent: Codable, Hashable, Sendable {
  /// The report's id.
  public let id: String
  /// The feature's key.
  public let feature: String
  /// For a report, the amount used; for a meter set, how much it moved the meter.
  public let amount: Int64
  /// A report or a meter set.
  public let kind: UsageEventKind
  /// For a meter set, the value the meter was set to.
  public let setTo: Int64?
  /// Where it was reported from.
  public let source: UsageSource
  /// Who reported it, when the credential may know.
  public let actor: String?
  /// When it was recorded.
  public let at: Date
  /// When the report was cancelled, or `nil` while it stands.
  public let cancelledAt: Date?
}

/// One metered feature's use, in ``CustomerUsage``.
public struct FeatureUsage: Codable, Hashable, Sendable {
  /// The feature's key.
  public let feature: String
  /// The feature's type.
  public let type: FeatureType
  /// Whether the customer is entitled.
  public let entitled: Bool
  /// The allowance.
  public let value: FeatureValue
  /// Where the allowance comes from.
  public let sources: [EntitlementSource]
  /// How much is used this period.
  public let used: Int64
  /// How much open holds reserve.
  public let held: Int64
  /// How much is left, or `nil` when not entitled.
  public let remaining: FeatureValue?
  /// When the meter resets.
  public let resetsAt: Date?
}

/// A customer's meters and the first page of their usage log.
public struct CustomerUsage: Codable, Hashable, Sendable {
  /// The customer's external id.
  public let customer: String
  /// The instant the answer is for.
  public let asOf: Date
  /// When the meters start again.
  public let metersStartAgainAt: Date?
  /// Each metered feature's use.
  public let features: [FeatureUsage]
  /// A page of the usage log, newest first.
  public let log: Page<UsageEvent>
  /// The environment the answer comes from.
  public let environment: AnswerEnvironment
  /// The customer's track.
  public let track: Track
  /// The release the track serves, or `nil` when it follows a change.
  public let release: Int64?
  /// The change the track follows, or `nil` when it serves a release.
  public let change: String?
  /// Whether test money is taken: a track for testers, or a test environment.
  public let testers: Bool
  /// The experiment the customer is in, if any.
  public let experiment: ExperimentAssignment?
}

/// What a usage write did: the check after it, plus the outcome.
///
/// A refusal is an answer, not an error: see ``outcome`` and ``refusal``.
public struct UsageResult: Codable, Hashable, Sendable {
  /// The customer's external id.
  public let customer: String
  /// The instant the answer is for.
  public let asOf: Date
  /// The feature's key.
  public let feature: String
  /// The feature's type.
  public let type: FeatureType
  /// Whether the customer is entitled.
  public let entitled: Bool
  /// The allowance.
  public let value: FeatureValue
  /// Where the allowance comes from.
  public let sources: [EntitlementSource]
  /// How much is used this period.
  public let used: Int64?
  /// How much open holds reserve.
  public let held: Int64?
  /// How much is left.
  public let remaining: FeatureValue?
  /// When the meter resets.
  public let resetsAt: Date?
  /// When refused, the plans that would raise the allowance.
  public let upgrades: [Upgrade]
  /// What happened.
  public let outcome: UsageOutcome
  /// Why it was refused, or `nil` when it was not.
  public let refusal: UsageRefusal?
  /// The report this created, repeated, settled or cancelled.
  public let id: String?
  /// The hold this created, settled, released or repeated.
  public let holdID: String?
  /// The mode the report was recorded in.
  public let mode: UsageMode
  /// The amount asked for, or the original's on a replay.
  public let amount: Int64
  /// How much this request moved the meter.
  public let meterChange: Int64
  /// How far ``used`` is past the allowance; 0 within it or when unlimited.
  public let overBy: Int64
  /// Whether the report's period had closed when it arrived, so it missed the meter.
  public let late: Bool
  /// When the usage happened.
  public let occurredAt: Date?
  /// When the hold expires; `nil` for a report.
  public let expiresAt: Date?
  /// Where the usage was reported from.
  public let reportedAs: UsageSource
  /// The environment the answer comes from.
  public let environment: AnswerEnvironment
  /// The customer's track.
  public let track: Track
  /// The release the track serves, or `nil` when it follows a change.
  public let release: Int64?
  /// The change the track follows, or `nil` when it serves a release.
  public let change: String?
  /// Whether test money is taken: a track for testers, or a test environment.
  public let testers: Bool
  /// The experiment the customer is in, if any.
  public let experiment: ExperimentAssignment?

  enum CodingKeys: String, CodingKey {
    case customer, asOf, feature, type, entitled, value, sources, used, held, remaining, resetsAt
    case upgrades, outcome, refusal, id, mode, amount, meterChange, overBy, late, occurredAt
    case expiresAt, reportedAs, environment, track, release, change, testers, experiment
    case holdID = "holdId"
  }
}

/// A usage hold, as ``Customer/hold(id:timeout:)`` reads it.
public struct UsageHold: Codable, Hashable, Sendable {
  /// The hold's id.
  public let id: String
  /// The customer's external id.
  public let customer: String
  /// The feature's key.
  public let feature: String
  /// The amount held.
  public let amount: Int64
  /// Open, settled, released or expired.
  public let state: HoldState
  /// When it expires on its own.
  public let expiresAt: Date
  /// The amount it was settled with.
  public let settledAmount: Int64?
  /// The report its settlement recorded.
  public let usageID: String?
  /// When it was placed.
  public let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id, customer, feature, amount, state, expiresAt, settledAmount, createdAt
    case usageID = "usageId"
  }
}

/// Why one event of a batch was not recorded.
public struct UsageEventError: Codable, Hashable, Sendable {
  /// The code a single report would answer.
  public let code: ErrorCode
  /// The message, fit to show a person.
  public let message: String
}

/// What happened to one event of a batch.
public struct UsageEventResult: Codable, Hashable, Sendable {
  /// The event's position in the input, from 0.
  public let index: Int
  /// Recorded, duplicate or error.
  public let outcome: UsageEventOutcome
  /// The report recorded, or the one a duplicate repeats.
  public let id: String?
  /// Whether the event's period had closed when it arrived.
  public let late: Bool
  /// Why it was not recorded.
  public let error: UsageEventError?
  /// The event's idempotency key, to resend it safely.
  public let idempotencyKey: String
}

/// What a batch did: one result per event, in input order, and the totals.
public struct UsageBatchResult: Codable, Hashable, Sendable {
  /// One result per event, in input order.
  public let results: [UsageEventResult]
  /// How many events were recorded.
  public let recorded: Int
  /// How many were replays.
  public let duplicates: Int
  /// How many failed.
  public let errors: Int
}

/// A customer as lists and changes describe them.
public struct CustomerSummary: Codable, Hashable, Sendable {
  /// Entitler's id for the customer.
  public let id: String
  /// The id your app uses for the customer.
  public let externalID: String
  /// The customer's name.
  public let name: String
  /// The customer's email address.
  public let email: String
  /// The environment's id.
  public let environmentID: String
  /// Whether the customer is a sample.
  public let sample: Bool
  /// When the customer was registered.
  public let createdAt: Date
  /// Their plan, when they hold one.
  public let plan: PlanRef?
  /// Every plan they hold, one per product.
  public let plans: [PlanRef]
  /// The default plan.
  public let defaultPlan: PlanRef?
  /// Their status.
  public let status: String
  /// How they pay.
  public let kind: CustomerKind
  /// Your metadata.
  public let metadata: [String: String]
  /// Their track.
  public let track: Track
  /// Whether every purchase they made used test money.
  public let testCustomer: Bool

  enum CodingKeys: String, CodingKey {
    case id, name, email, sample, createdAt, plan, plans, defaultPlan, status, kind, metadata
    case track, testCustomer
    case externalID = "externalId"
    case environmentID = "environmentId"
  }
}

/// A customer, as ``ServerCustomer/register(name:email:metadata:visitor:idempotencyKey:timeout:)``
/// answers.
public struct RegisteredCustomer: Codable, Hashable, Sendable {
  /// Entitler's id for the customer.
  public let id: String
  /// The id your app uses for the customer.
  public let externalID: String
  /// The environment's id.
  public let environmentID: String
  /// When the customer was registered.
  public let createdAt: Date
  /// Whether this call registered them.
  public let created: Bool

  enum CodingKeys: String, CodingKey {
    case id, createdAt, created
    case externalID = "externalId"
    case environmentID = "environmentId"
  }
}

/// Where a plan or add-on was bought.
public struct Purchase: Codable, Hashable, Sendable {
  /// Real or test money.
  public let money: Money
  /// The connection it was bought through.
  public let channel: Channel?
  /// The release it was bought from.
  public let release: Int64?
  /// The change it was bought from.
  public let change: String?
  /// The experiment arm it was bought in.
  public let arm: Arm?
}

/// An add-on a customer holds.
public struct HeldAddOn: Codable, Hashable, Sendable {
  /// The add-on.
  public let plan: PlanRef
  /// The version held.
  public let version: Int64
  /// How many are held.
  public let quantity: Int64
  /// Whether it can be held more than once.
  public let countable: Bool
  /// When it was added.
  public let addedAt: Date
  /// The add-on it moves to at the end of the period.
  public let movingTo: PlanRef?
  /// Where it was bought.
  public let purchase: Purchase
}

/// The provider's billing period for a subscription.
public struct ProviderPeriod: Codable, Hashable, Sendable {
  /// The provider, such as `stripe`.
  public let provider: String
  /// When the period started.
  public let startsAt: Date
  /// When it ends.
  public let endsAt: Date
  /// When the trial ends.
  public let trialEndsAt: Date?
  /// When the provider cancels it.
  public let cancelsAt: Date?
}

/// A change booked for the end of the period.
public struct PendingChange: Codable, Hashable, Sendable {
  /// A move or a cancellation.
  public let type: PendingChangeType
  /// For a move, the plan it moves to.
  public let plan: PlanRef?
  /// For a cancellation, the default plan it moves to.
  public let movingTo: PlanRef?
}

/// A move made in Entitler only, while the provider bills the plan held before.
public struct PlanOverride: Codable, Hashable, Sendable {
  /// The plan held before.
  public let from: PlanRef
  /// The billing period held before.
  public let period: String
  /// The connection that bills it.
  public let billedBy: Channel?
  /// When the override was made.
  public let since: Date
  /// Who made it.
  public let by: String
}

/// A customer's subscription in one product.
public struct Subscription: Codable, Hashable, Sendable {
  /// The product.
  public let product: Product
  /// The plan held.
  public let plan: PlanRef
  /// Its version.
  public let version: Int64
  /// The cohort, when the plan has them.
  public let cohort: Int64?
  /// The billing period.
  public let period: String
  /// When it started.
  public let startedAt: Date
  /// When it renews.
  public let renewsAt: Date
  /// The provider's period, when a provider bills it.
  public let billing: ProviderPeriod?
  /// The add-ons held with it.
  public let addOns: [HeldAddOn]
  /// A change booked for the end of the period.
  public let pending: PendingChange?
  /// Where it was bought.
  public let purchase: Purchase
  /// An override, if one is in force.
  public let override: PlanOverride?
}

/// A customer's holdings in one product.
public struct ProductHolding: Codable, Hashable, Sendable {
  /// The product.
  public let product: Product
  /// Its default plan.
  public let defaultPlan: PlanRef?
  /// The subscription held in it.
  public let subscription: Subscription?
}

/// A grant of a feature beyond the customer's plan.
public struct Grant: Codable, Hashable, Sendable {
  /// The grant's id.
  public let id: String
  /// The feature's key.
  public let feature: String
  /// The value granted, as the API writes it.
  public let value: String
  /// When it started.
  public let from: Date
  /// When it ends, or `nil` when it never does.
  public let until: Date?
  /// When it was revoked.
  public let revokedAt: Date?
  /// Why it was given.
  public let reason: String
  /// Who gave it.
  public let by: String
}

/// An entry of a customer's activity.
public struct Activity: Codable, Hashable, Sendable {
  /// What happened, fit to show a person.
  public let text: String
  /// When.
  public let at: Date
}

/// A customer in full: subscriptions, entitlements, grants, usage log and activity.
///
/// Billing changes answer this too, with ``selfServe``.
public struct CustomerDetail: Codable, Hashable, Sendable {
  /// The customer.
  public let customer: CustomerSummary
  /// The instant the answer is for.
  public let asOf: Date
  /// The newest subscription.
  public let subscription: Subscription?
  /// The default plan.
  public let defaultPlan: PlanRef?
  /// Their holdings in each product.
  public let products: [ProductHolding]
  /// The add-ons they hold.
  public let addOns: [HeldAddOn]
  /// Their entitlements.
  public let entitlements: [Entitlement]
  /// Banked credits, by feature key.
  public let banked: [String: Int64]
  /// The moves open to them.
  public let moveOptions: [MoveOption]
  /// Their grants.
  public let grants: [Grant]
  /// A page of their usage log.
  public let usage: Page<UsageEvent>
  /// Their activity.
  public let activity: [Activity]
  /// For a billing change, whether the customer could have made it themselves.
  public let selfServe: Bool?
  /// The environment the answer comes from.
  public let environment: AnswerEnvironment
}

/// A customer's place on a track.
public struct CustomerTrack: Codable, Hashable, Sendable {
  /// The customer's external id.
  public let customer: String
  /// Their track.
  public let track: Track
  /// Who put them there.
  public let source: TrackSource?
  /// The track they left.
  public let previousTrackID: String?

  enum CodingKeys: String, CodingKey {
    case customer, track, source
    case previousTrackID = "previousTrackId"
  }
}

/// A paid plan the provider bills that Entitler does not hold.
public struct BillingDrift: Codable, Hashable, Sendable {
  /// The plan the provider bills.
  public let billedPlan: String
  /// The plan Entitler holds.
  public let heldPlan: String?
  /// When the drift was seen.
  public let observedAt: Date
}

/// How the provider bills one product.
public struct ProductBilling: Codable, Hashable, Sendable {
  /// The product's key.
  public let product: String?
  /// The subscription's status.
  public let status: BillingStatus?
  /// The SKU billed.
  public let sku: OfferedSKU?
  /// How many items the subscription has.
  public let items: Int64
  /// Any drift.
  public let drift: BillingDrift?
}

/// Whether a payment provider bills the customer, and how.
public struct CustomerBilling: Codable, Hashable, Sendable {
  /// The provider, or `nil` when none bills them.
  public let provider: String?
  /// The newest subscription's status.
  public let status: BillingStatus?
  /// The SKU it bills.
  public let sku: OfferedSKU?
  /// How many items it has.
  public let items: Int64
  /// Any drift.
  public let drift: BillingDrift?
  /// Every subscription the provider bills, by product.
  public let products: [ProductBilling]?
}

/// A connection, as provider answers name it.
public struct ProviderConnection: Codable, Hashable, Sendable {
  /// The connection's id.
  public let id: String
  /// Its name.
  public let name: String
  /// The provider.
  public let provider: Provider
}

/// The plan a provider item or payment sells.
public struct ProviderSale: Codable, Hashable, Sendable {
  /// The plan's key.
  public let plan: String
  /// Its version.
  public let version: Int64?
  /// The billing period.
  public let period: String
  /// A base plan or an add-on.
  public let kind: PlanKind
  /// The product's key.
  public let product: String?
}

/// An item of a provider subscription.
public struct ProviderItem: Codable, Hashable, Sendable {
  /// The provider's id for the item.
  public let id: String
  /// The provider's ids for what it sells.
  public let ids: [String: String]
  /// The quantity.
  public let quantity: Int64
  /// The listing that sells it, if any.
  public let sale: ProviderSale?
}

/// A period of a provider subscription.
public struct ProviderSubscriptionPeriod: Codable, Hashable, Sendable {
  /// When it starts.
  public let startsAt: Date
  /// When it ends.
  public let endsAt: Date
}

/// A subscription as the provider last reported it.
public struct ProviderSubscription: Codable, Hashable, Sendable {
  /// The provider's id.
  public let id: String
  /// The provider's status.
  public let status: String
  /// Whether it bills.
  public let billing: Bool
  /// Its period.
  public let period: ProviderSubscriptionPeriod?
  /// When its trial ends.
  public let trialEndsAt: Date?
  /// When it is cancelled.
  public let cancelsAt: Date?
  /// Its items.
  public let items: [ProviderItem]
}

/// An amount of money.
public struct MoneyAmount: Codable, Hashable, Sendable {
  /// The amount in the currency's smallest unit.
  public let value: Int64
  /// The ISO currency code.
  public let currency: String
}

/// A one-time payment as the provider last reported it.
public struct ProviderPayment: Codable, Hashable, Sendable {
  /// The provider's id.
  public let id: String
  /// The provider's ids for what it bought.
  public let ids: [String: String]
  /// The quantity.
  public let quantity: Int64
  /// The amount paid.
  public let amount: MoneyAmount?
  /// Paid or refunded.
  public let status: ProviderPaymentStatus
  /// When it was paid.
  public let paidAt: Date
  /// The listing that sells it, if any.
  public let sale: ProviderSale?
}

/// A customer's subscriptions and payments in one connection.
public struct ProviderState: Codable, Hashable, Sendable {
  /// The subscriptions.
  public let subscriptions: [ProviderSubscription]
  /// The one-time payments.
  public let payments: [ProviderPayment]
}

/// One connection's view of a customer.
public struct ProviderConnectionState: Codable, Hashable, Sendable {
  /// The connection.
  public let connection: ProviderConnection
  /// When it was last read.
  public let readAt: Date
  /// What it reported.
  public let state: ProviderState
}

/// The facts behind an alert.
public struct AlertFacts: Codable, Hashable, Sendable {
  /// The customer's external id.
  public let customer: String?
  /// The connection's id.
  public let connection: String
  /// The provider.
  public let provider: Provider
  /// The product's key.
  public let product: String?
  /// The plans involved.
  public let plans: [String]?
  /// The plan involved.
  public let plan: String?
  /// The plan held.
  public let held: String?
  /// The plan's id.
  public let planID: String?
  /// The held plan's id.
  public let heldID: String?
  /// The provider's ids.
  public let ids: String?
  /// A count.
  public let count: Int64?
  /// Where it was bought.
  public let boughtThrough: String?
  /// Why a purchase was refused.
  public let refusal: AlertRefusal?
  /// The reason, fit to show a person.
  public let reason: String?
  /// The provider's customer id.
  public let providerCustomer: String?

  enum CodingKeys: String, CodingKey {
    case customer, connection, provider, product, plans, plan, held, ids, count, boughtThrough
    case refusal, reason, providerCustomer
    case planID = "planId"
    case heldID = "heldId"
  }
}

/// A customer named by an alert.
public struct AlertCustomer: Codable, Hashable, Sendable {
  /// The customer's external id.
  public let externalID: String
  /// The customer's name.
  public let name: String

  enum CodingKeys: String, CodingKey {
    case name
    case externalID = "externalId"
  }
}

/// A rule a payment provider breaks.
public struct Alert: Codable, Hashable, Sendable {
  /// The alert's id.
  public let id: String
  /// The rule broken.
  public let rule: AlertRule
  /// A title fit to show a person.
  public let title: String
  /// A message fit to show a person.
  public let message: String
  /// The facts behind it.
  public let facts: AlertFacts
  /// The customer.
  public let customer: AlertCustomer?
  /// The connection.
  public let connection: ProviderConnection
  /// When it opened.
  public let openedAt: Date
  /// When it was last seen.
  public let seenAt: Date
  /// When it was resolved.
  public let resolvedAt: Date?
  /// Who resolved it.
  public let resolvedBy: AlertResolver?
}

/// A customer's subscriptions and payments in each provider, and the alerts they raise.
public struct CustomerProviders: Codable, Hashable, Sendable {
  /// Each connection's view.
  public let connections: [ProviderConnectionState]
  /// The open alerts.
  public let alerts: [Alert]
  /// The provider customers linked to them.
  public let linked: [String]?
}

/// Where to send the customer: a checkout or a billing portal.
public struct ProviderPage: Codable, Hashable, Sendable {
  /// The provider, such as `stripe`.
  public let provider: String
  /// The page's address.
  public let url: URL
}

/// A signed entitlements snapshot, for checks without a connection.
public struct IssuedSnapshot: Codable, Hashable, Sendable {
  /// The compact JWS. Verify it with ``verifySnapshot(_:expecting:)``.
  public let token: String
  /// When it expires.
  public let expiresAt: Date
  /// The id of the key that signed it.
  public let keyID: String

  enum CodingKeys: String, CodingKey {
    case token, expiresAt
    case keyID = "keyId"
  }
}

/// A customer token for an in-app client.
public struct IssuedCustomerToken: Codable, Hashable, Sendable {
  /// The token. Send it to the customer's app and nowhere else.
  public let token: String
  /// The customer's external id.
  public let customer: String
  /// The scopes it holds.
  public let scopes: [Scope]
  /// When it expires.
  public let expiresAt: Date

  enum CodingKeys: String, CodingKey {
    case token, customer, scopes, expiresAt
  }

  /// Decodes the token, keeping only the scopes this SDK knows.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    token = try container.decode(String.self, forKey: .token)
    customer = try container.decode(String.self, forKey: .customer)
    scopes = Scope.known(try container.decode([String].self, forKey: .scopes))
    expiresAt = try container.decode(Date.self, forKey: .expiresAt)
  }
}

/// A payment a plan change waits on, from `402 payment_required`.
public struct Payment: Codable, Hashable, Sendable {
  /// Why it has not succeeded.
  public let status: PaymentStatus
  /// The provider's page where the customer pays or confirms it.
  public let url: String?
}

/// A plan and billing period a listing leaves blank.
public struct ListingGap: Codable, Hashable, Sendable {
  /// Why it is blank.
  public let kind: ListingGapKind
  /// The plan's id.
  public let plan: String
  /// The plan's key.
  public let key: String
  /// The billing period.
  public let period: String
  /// The connection.
  public let channel: Channel?
}

/// A listing whose price fails the checks.
public struct ListingProblem: Codable, Hashable, Sendable {
  /// The connection.
  public let channel: Channel
  /// The plan's key.
  public let plan: String
  /// The billing period.
  public let period: String
  /// The provider's ids.
  public let ids: [String: String]
  /// What is wrong.
  public let problem: ListingProblemKind
}

extension Check: MeterChecked {
  var hasValidMeters: Bool { remaining.isMeterAmount }
}

extension MeteredCheck: MeterChecked {
  var hasValidMeters: Bool { remaining != .on }
}

extension Entitlement: MeterChecked {
  var hasValidMeters: Bool { remaining.isMeterAmount }
}

extension Entitlements: MeterChecked {
  var hasValidMeters: Bool { items.allSatisfy(\.hasValidMeters) }
}

extension FeatureUsage: MeterChecked {
  var hasValidMeters: Bool { remaining.isMeterAmount }
}

extension CustomerUsage: MeterChecked {
  var hasValidMeters: Bool { features.allSatisfy(\.hasValidMeters) }
}

extension UsageResult: MeterChecked {
  var hasValidMeters: Bool { remaining.isMeterAmount }
}
