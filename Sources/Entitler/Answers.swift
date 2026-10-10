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

/// A plan that would give a feature the customer lacks, with the same ``move`` and ``action`` as
/// ``MoveOption``, so an "Upgrade" button and the paywall share one rule.
public struct Upgrade: Codable, Hashable, Sendable {
  /// The plan's key.
  public let plan: String
  /// The plan's name.
  public let name: String
  /// How the customer would take it.
  public let move: Move
  /// Who can make the move.
  public let action: MoveAction
  /// Why the move is ``MoveAction/unavailable``, a sentence for the developer; else `nil`.
  public let reason: String?
}

/// A billing period: the stable ``key`` writes take, and the ``label`` to show.
public struct Period: Codable, Hashable, Sendable {
  /// The key, such as `monthly`, which stays the same however the label is shown.
  public let key: String
  /// The label to show, such as Monthly.
  public let label: String
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
  /// When not entitled, the plans that would give the feature; always empty in a snapshot,
  /// since offline gating never offers a purchase.
  public let upgrades: [Upgrade]

  enum CodingKeys: String, CodingKey {
    case key, type, entitled, value, sources, used, held, remaining, resetsAt, upgrades
  }

  /// Decodes an entitlement; a snapshot's claims carry no `upgrades`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    key = try container.decode(String.self, forKey: .key)
    type = try container.decode(FeatureType.self, forKey: .type)
    entitled = try container.decode(Bool.self, forKey: .entitled)
    value = try container.decode(FeatureValue.self, forKey: .value)
    sources = try container.decode([EntitlementSource].self, forKey: .sources)
    used = try container.decodeIfPresent(Int64.self, forKey: .used)
    held = try container.decodeIfPresent(Int64.self, forKey: .held)
    remaining = try container.decodeIfPresent(FeatureValue.self, forKey: .remaining)
    resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
    upgrades = try container.decodeIfPresent([Upgrade].self, forKey: .upgrades) ?? []
  }
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
  /// How often it is billed, or `nil` when Entitler sets no period.
  public let period: Period?
  /// When it renews, or `nil` when it does not.
  public let renewsAt: Date?
  /// The change booked for ``renewsAt``, or `nil`.
  public let pending: PendingChange?
  /// The store or provider that bills it, or `nil` when nothing does. A plan Apple or Google bills
  /// is changed in the store's own management page; one Stripe bills, in
  /// ``Customer/billingPortal(returnURL:timeout:)``.
  public let billedBy: Provider?
}

/// A change booked for a plan's renewal.
public enum PendingChange: Codable, Hashable, Sendable {
  /// A move to another plan.
  case move(to: PlanRef)
  /// A cancellation, moving to the product's default plan, or to none.
  case cancel(movingTo: PlanRef?)
  /// A change this SDK does not know yet.
  case unknown(String)

  enum CodingKeys: String, CodingKey {
    case type, plan, movingTo
  }

  /// Decodes the change from its `type`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)
    switch type {
    case "move": self = .move(to: try container.decode(PlanRef.self, forKey: .plan))
    case "cancel":
      self = .cancel(movingTo: try container.decodeIfPresent(PlanRef.self, forKey: .movingTo))
    default: self = .unknown(type)
    }
  }

  /// Encodes the change as the API writes it.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .move(let plan):
      try container.encode("move", forKey: .type)
      try container.encode(plan, forKey: .plan)
    case .cancel(let plan):
      try container.encode("cancel", forKey: .type)
      try container.encode(plan, forKey: .movingTo)
    case .unknown(let type):
      try container.encode(type, forKey: .type)
    }
  }
}

/// The plan or add-on of a ``MoveOption``.
public struct OptionPlan: Codable, Hashable, Sendable {
  /// The plan's public id.
  public let id: String
  /// The plan's key, such as `pro`.
  public let key: String
  /// The plan's name.
  public let name: String
  /// Whether it is a base plan or an add-on.
  public let kind: PlanKind
  /// The plan's description.
  public let description: String
  /// True for a product's default plan.
  public let isDefault: Bool

  enum CodingKeys: String, CodingKey {
    case id, key, name, kind, description
    case isDefault = "default"
  }
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
  /// The billing period it sells, or `nil` for none.
  public let period: Period?
  /// The connector, such as `stripe` or `apple`.
  public let connector: String
  /// The provider's ids.
  public let ids: [String: String]
  /// The price, when the provider reports one.
  public let price: ProviderPrice?
}

/// A plan or add-on a customer can move to, in ``CustomerPlans``: one button on a paywall or a
/// billing page.
public struct MoveOption: Codable, Hashable, Sendable {
  /// The plan or add-on.
  public let plan: OptionPlan
  /// The product it is in; `nil` for an add-on for every product.
  public let product: Product?
  /// The plan or add-on the move starts from, or `nil` for a sign-up.
  public let from: PlanRef?
  /// How it changes the customer's plans.
  public let move: Move
  /// Who can make it, which decides the button: ``MoveAction/buy`` calls
  /// ``Customer/subscribe(to:period:quantity:returnURL:register:idempotencyKey:timeout:)``.
  public let action: MoveAction
  /// Why it is ``MoveAction/unavailable``, a sentence for the developer; else `nil`.
  public let reason: String?
  /// When it would apply.
  public let when: ChangeTiming
  /// The plan's billing periods, from the catalogue, whatever sells them.
  public let periods: [Period]
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
  /// The billing period, or `nil` for a one-time plan.
  public let period: Period?
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
/// Pricing is always computed now, never at another instant.
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
  /// On the customer list, how many customers the environment holds.
  public let used: Int64?
  /// On the customer list, how many it may hold: an amount, or ``FeatureValue/unlimited``.
  public let limit: FeatureValue?
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
public struct UsageResult: Codable, Hashable, Sendable, Replaying {
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
  /// True when the API answered an earlier call's key: this call changed nothing, and this is
  /// the first call's answer.
  public internal(set) var replayed = false

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
public struct UsageEventError: Error, Codable, Hashable, Sendable {
  /// The code a single report would answer, or the SDK's own for an event it refused or a
  /// request that failed.
  public let code: ErrorCode
  /// The message, written for the developer.
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
  /// True when its request repeated an earlier one, so it changed nothing.
  public let replayed: Bool
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
public struct CustomerSummary: Codable, Hashable, Sendable, Replaying {
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
  /// True when the API answered an earlier call's key, so this call changed nothing.
  public internal(set) var replayed = false

  enum CodingKeys: String, CodingKey {
    case id, name, email, sample, createdAt, plan, plans, defaultPlan, status, kind, metadata
    case track, testCustomer
    case externalID = "externalId"
    case environmentID = "environmentId"
  }
}

/// A customer, as ``ServerCustomer/register(name:email:metadata:visitor:idempotencyKey:timeout:)``
/// answers.
public struct RegisteredCustomer: Codable, Hashable, Sendable, Replaying {
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
  /// True when the API answered an earlier call's key, so this call changed nothing.
  public internal(set) var replayed = false

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
  /// The billing period, or `nil` for none.
  public let period: Period?
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
  /// The key or person that gave it.
  public let by: String
  /// The person or system that decided, as the write named it.
  public let actor: String?
}

/// A grant made or revoked, as `grant` and ``ServerCustomer/revokeGrant(id:reason:actor:idempotencyKey:timeout:)`` answer.
public struct GrantChange: Codable, Hashable, Sendable, Replaying {
  /// The grant, so a support tool keeps its id.
  public let grant: Grant
  /// True when the API answered an earlier call's key, so this call changed nothing.
  public internal(set) var replayed = false

  enum CodingKeys: String, CodingKey { case grant }
}

/// What a plan change did, as ``Customer/cancel(addOn:product:idempotencyKey:timeout:)``,
/// ``Customer/undoPendingChange(addOn:product:idempotencyKey:timeout:)``,
/// ``ServerCustomer/setPlan(to:period:when:billing:until:register:reason:actor:idempotencyKey:timeout:)``
/// and ``ServerCustomer/setAddOn(_:quantity:when:reason:actor:idempotencyKey:timeout:)`` answer,
/// and a ``SubscribeStep/done(_:)`` step holds.
public struct PlanChange: Codable, Hashable, Sendable, Replaying {
  /// The product the change is in.
  public let product: Product?
  /// The plan or add-on the change leaves the customer on; `nil` when they hold none in that
  /// product.
  public let plan: PlanRef?
  /// An add-on's quantity after the change: 0 when removed; `nil` for a plan.
  public let quantity: Int64?
  /// Now, or at renewal.
  public let effective: ChangeEffect
  /// When it takes effect.
  public let at: Date
  /// When the customer returns to the product's default plan, from `setPlan`'s `until`.
  public let until: Date?
  /// False when nothing changed: nothing to cancel, nothing pending, or a plan already held.
  public let changed: Bool
  /// True when the API answered an earlier call's key, so this call changed nothing.
  public internal(set) var replayed = false

  enum CodingKeys: String, CodingKey {
    case product, plan, quantity, effective, at, until, changed
  }
}

/// The next step after ``Customer/subscribe(to:period:quantity:returnURL:register:idempotencyKey:timeout:)``.
public enum SubscribeStep: Codable, Hashable, Sendable, Replaying {
  /// The change is made.
  case done(PlanChange)
  /// Send the customer to the provider's page: Stripe Checkout, or a confirmation such as
  /// 3-D Secure. The plan changes once they pay. In an app, open it in
  /// `ASWebAuthenticationSession` with a universal link as the return URL.
  case pay(URL)
  /// The provider is still confirming a payment, such as a bank debit: show it as pending. The
  /// plan changes when it succeeds.
  case confirming
  /// A store bills the product, so the customer changes it in the store's own management page.
  case manage(billedBy: Provider)
  /// A step this SDK does not know yet, with its raw name.
  case unknown(String)

  enum CodingKeys: String, CodingKey {
    case next, url, billedBy
  }

  /// Decodes the step from its `next`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let next = try container.decode(String.self, forKey: .next)
    switch next {
    case "done": self = .done(try PlanChange(from: decoder))
    case "pay": self = .pay(try container.decode(URL.self, forKey: .url))
    case "confirming": self = .confirming
    case "manage": self = .manage(billedBy: try container.decode(Provider.self, forKey: .billedBy))
    default: self = .unknown(next)
    }
  }

  /// Encodes the step as the API writes it.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .done(let change):
      try container.encode("done", forKey: .next)
      try change.encode(to: encoder)
    case .pay(let url):
      try container.encode("pay", forKey: .next)
      try container.encode(url, forKey: .url)
    case .confirming: try container.encode("confirming", forKey: .next)
    case .manage(let provider):
      try container.encode("manage", forKey: .next)
      try container.encode(provider, forKey: .billedBy)
    case .unknown(let next): try container.encode(next, forKey: .next)
    }
  }

  /// True when the step is done and the API answered an earlier call's key.
  public var replayed: Bool {
    get {
      if case .done(let change) = self { return change.replayed }
      return false
    }
    set {
      if case .done(var change) = self {
        change.replayed = newValue
        self = .done(change)
      }
    }
  }
}

/// Whether reading the provider's state moved the customer, as ``Customer/syncBilling(timeout:)``
/// answers.
public struct BillingSync: Codable, Hashable, Sendable {
  /// True when the provider's state moved the customer to another plan or quantity.
  public let changed: Bool
}

/// An entry of a customer's activity.
public struct Activity: Codable, Hashable, Sendable {
  /// What happened, fit to show a person.
  public let text: String
  /// When.
  public let at: Date
}

/// A customer in full: subscriptions, entitlements, grants, usage log and activity.
public struct CustomerDetail: Codable, Hashable, Sendable, Replaying {
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
  /// The environment the answer comes from.
  public let environment: AnswerEnvironment
  /// True when ``Customers/create(id:name:email:plan:period:metadata:idempotencyKey:timeout:)``
  /// answered an earlier call's key, so this call changed nothing.
  public internal(set) var replayed = false

  enum CodingKeys: String, CodingKey {
    case customer, asOf, subscription, defaultPlan, products, addOns, entitlements, banked
    case moveOptions, grants, usage, activity, environment
  }
}

/// A customer's place on a track.
public struct CustomerTrack: Codable, Hashable, Sendable, Replaying {
  /// The customer's external id.
  public let customer: String
  /// Their track.
  public let track: Track
  /// Who put them there.
  public let source: TrackSource?
  /// The track they left.
  public let previousTrackID: String?
  /// True when the API answered an earlier call's key, so this call changed nothing.
  public internal(set) var replayed = false

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

/// The payment provider's page: the billing portal.
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
