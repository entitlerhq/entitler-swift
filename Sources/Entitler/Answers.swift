import Foundation

/// A feature's type, extensible: a type this SDK does not list is kept as it is.
public struct FeatureType: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
  /// The type as the SDK spells it, such as `metered`.
  public let rawValue: String

  /// Creates a type from its spelling.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// The type's spelling.
  public var description: String { rawValue }

  /// On or off.
  public static let `switch` = FeatureType(rawValue: "switch")
  /// A setting: an amount, or unlimited.
  public static let configuration = FeatureType(rawValue: "configuration")
  /// A meter with an allowance.
  public static let metered = FeatureType(rawValue: "metered")
  /// A group of other features.
  public static let group = FeatureType(rawValue: "group")
}

/// A feature's value.
public enum FeatureValue: Hashable, Sendable {
  /// On.
  case on
  /// An amount; `0` is off or none.
  case amount(Int64)
  /// Unlimited.
  case unlimited
}

/// An amount, or unlimited.
public enum Limit: Hashable, Sendable {
  /// An amount.
  case amount(Int64)
  /// Unlimited.
  case unlimited
}

/// The track a customer is on.
public struct ServedTrack: Hashable, Sendable {
  /// The track's id.
  public let id: String
  /// The track's name.
  public let name: String
}

/// The release or change an answer comes from.
public enum ServedSource: Hashable, Sendable {
  /// A release, by its id and number.
  case release(id: String, number: Int64)
  /// An unreleased change, for a track that follows one.
  case change(id: String)
  /// Nothing is released yet.
  case nothing
}

/// The catalogue an answer comes from.
public struct Served: Hashable, Sendable {
  /// The track the customer is on, or `nil` when the answer names none.
  public let track: ServedTrack?
  /// The release or change that answered.
  public let source: ServedSource
}

/// A plan's share of a feature's value.
public struct PlanSource: Hashable, Sendable {
  /// The plan's id.
  public let planID: String
  /// The plan's key.
  public let plan: String
  /// The plan's name.
  public let name: String
  /// The product's id, or `nil` when the answer names none.
  public let product: String?
  /// The plan version held.
  public let version: Int64
  /// True when held because it is the product's default plan.
  public let byDefault: Bool
  /// The plan's share of the value, or `nil` when the answer names none.
  public let value: FeatureValue?
  /// The group whose membership passed this value on, or `nil`.
  public let through: String?
}

/// An add-on's share of a feature's value.
public struct AddOnSource: Hashable, Sendable {
  /// The add-on's id.
  public let planID: String
  /// The add-on's key.
  public let plan: String
  /// The add-on's name.
  public let name: String
  /// The add-on version held.
  public let version: Int64
  /// How many are held.
  public let quantity: Int64
  /// The add-on's share of the value, or `nil` when the answer names none.
  public let value: FeatureValue?
  /// The group whose membership passed this value on, or `nil`.
  public let through: String?
}

/// A grant's share of a feature's value.
public struct GrantSource: Hashable, Sendable {
  /// The grant's id.
  public let grant: String
  /// When the grant ends, or `nil`.
  public let until: Date?
  /// The grant's share of the value, or `nil` when the answer names none.
  public let value: FeatureValue?
  /// The group whose membership passed this value on, or `nil`.
  public let through: String?
}

/// Where part of a feature's value comes from.
public enum EntitlementSource: Hashable, Sendable {
  /// A plan, the product's default plan included.
  case plan(PlanSource)
  /// An add-on.
  case addOn(AddOnSource)
  /// A grant.
  case grant(GrantSource)
  /// A group, decided by its member features.
  case group(features: [String])
}

/// A name the API may add to, kept as it is when this SDK does not list it.
public struct OpenName: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
  /// The name, such as `upgrade`.
  public let rawValue: String

  /// Creates a name.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// The name.
  public var description: String { rawValue }
}

/// A plan or add-on that would give the customer a feature they lack.
public struct Upgrade: Hashable, Sendable {
  /// `plan` or `add_on`.
  public let kind: OpenName
  /// The plan's id.
  public let planID: String
  /// The plan's key.
  public let plan: String
  /// The plan's name.
  public let name: String
  /// The product's id, or `nil` when the answer names none.
  public let product: String?
  /// How the customer would move to it: `subscribe`, `upgrade`, `switch`, `add` or `replace`.
  public let move: OpenName
  /// Who can make the move: `buy`, the customer alone; `contact`, only the company.
  public let action: OpenName
}

/// A metered feature's meter.
public struct Meter: Hashable, Sendable {
  /// How much the customer used this period or window.
  public let used: Int64
  /// How much open holds reserve; counted in ``remaining``.
  public let held: Int64
  /// Credits banked from earlier periods.
  public let banked: Int64
  /// How much is left.
  public let remaining: Limit
  /// When the meter starts again, or `nil`.
  public let resetsAt: Date?
}

/// One feature's entitlement: Entitler's decision, the value and where it comes from.
public struct Entitlement: Hashable, Sendable {
  /// The feature's key.
  public let key: String
  /// The feature's type.
  public let type: FeatureType
  /// Entitler's decision: whether the customer may use the feature now.
  public let entitled: Bool
  /// The customer's value; for an on/off feature or a group, ``FeatureValue/on`` or `0`.
  public let value: FeatureValue
  /// Where the value comes from.
  public let sources: [EntitlementSource]
  /// Plans and add-ons that would give the customer the feature.
  public let upgrades: [Upgrade]
  /// The meter, for a metered feature.
  public let meter: Meter?
}

/// Where an answer comes from, and for whom.
public struct AnswerContext: Hashable, Sendable {
  /// The customer's external id: the id your app uses for them.
  public let customer: String
  /// Entitler's id for the customer, or `nil` before they are registered.
  public let customerID: String?
  /// The instant the answer was computed for.
  public let asOf: Date
  /// When the answer next changes on its own, such as a grant ending, or `nil`.
  public let nextChangeAt: Date?
  /// The catalogue the answer comes from.
  public let served: Served
}

/// The answer to a check: the entitlement, where it comes from, and whether it is stale. Read the
/// entitlement's fields straight from it, such as `check.entitled`.
@dynamicMemberLookup
public struct Check: Hashable, Sendable, StaleMarking {
  /// The feature's entitlement.
  public let entitlement: Entitlement
  /// Where the answer comes from, and for whom.
  public let context: AnswerContext
  /// True only when the SDK answered from a kept copy because Entitler was unreachable.
  public internal(set) var stale = false

  /// Reads a field of ``entitlement``.
  public subscript<Value>(dynamicMember field: KeyPath<Entitlement, Value>) -> Value {
    entitlement[keyPath: field]
  }

  /// Reads a field of ``context``.
  public subscript<Value>(dynamicMember field: KeyPath<AnswerContext, Value>) -> Value {
    context[keyPath: field]
  }
}

/// The answer to a check of a metered feature, with its meter.
@dynamicMemberLookup
public struct MeteredCheck: Hashable, Sendable, StaleMarking {
  /// The feature's entitlement.
  public let entitlement: Entitlement
  /// The meter.
  public let meter: Meter
  /// Where the answer comes from, and for whom.
  public let context: AnswerContext
  /// True only when the SDK answered from a kept copy because Entitler was unreachable.
  public internal(set) var stale = false

  /// Reads a field of ``entitlement``.
  public subscript<Value>(dynamicMember field: KeyPath<Entitlement, Value>) -> Value {
    entitlement[keyPath: field]
  }

  /// Reads a field of ``context``.
  public subscript<Value>(dynamicMember field: KeyPath<AnswerContext, Value>) -> Value {
    context[keyPath: field]
  }
}

/// A customer's entitlement list, groups included, each item with Entitler's decision.
@dynamicMemberLookup
public struct Entitlements: Hashable, Sendable, StaleMarking, RandomAccessCollection {
  /// Every entitlement, groups included.
  public let entitlements: [Entitlement]
  /// Where the answer comes from, and for whom.
  public let context: AnswerContext
  /// True only when the SDK answered from a kept copy because Entitler was unreachable.
  public internal(set) var stale = false

  /// The first index.
  public var startIndex: Int { entitlements.startIndex }
  /// The index past the last.
  public var endIndex: Int { entitlements.endIndex }
  /// The entitlement at an index.
  public subscript(position: Int) -> Entitlement { entitlements[position] }

  /// The feature's entitlement, or `nil` when the list does not hold it.
  public subscript(feature: String) -> Entitlement? {
    entitlements.first { $0.key == feature }
  }

  /// Entitler's decision for the feature, and `false` when the list does not hold it.
  public func has(_ feature: String) -> Bool {
    self[feature]?.entitled ?? false
  }

  /// Reads a field of ``context``.
  public subscript<Value>(dynamicMember field: KeyPath<AnswerContext, Value>) -> Value {
    context[keyPath: field]
  }
}
