// Generated from openapi.json by `swift run generate-wire`. Do not edit.

enum Wire {
  struct AddOnSource: Decodable, Sendable {
    var planId: String?
    var planKey: String?
    var planName: String?
    var quantity: Int64?
    var throughFeatureKey: String?
    var value: FeatureValue?
    var versionNumber: Int64?
  }
  struct CheckFeatureResponse: Decodable, Sendable {
    var asOf: Int64?
    var customer: EntitledCustomer?
    var entitlement: Entitlement?
    var nextChangeAt: Int64?
    var served: ServedCatalogue?
  }
  struct DefaultPlanSource: Decodable, Sendable {
    var planId: String?
    var planKey: String?
    var planName: String?
    var productId: String?
    var throughFeatureKey: String?
    var versionNumber: Int64?
  }
  struct EntitledCustomer: Decodable, Sendable {
    var customerId: String?
    var externalId: String?
  }
  typealias EntitledFeatureKind = String
  struct Entitlement: Decodable, Sendable {
    var entitled: Bool?
    var featureKey: String?
    var kind: EntitledFeatureKind?
    var meter: Meter?
    var sources: [EntitlementSource]?
    var upgrades: [Upgrade]?
    var value: FeatureValue?
  }
  struct EntitlementSource: Decodable, Sendable {
    var addOn: AddOnSource?
    var defaultPlan: DefaultPlanSource?
    var grant: GrantSource?
    var group: GroupSource?
    var plan: PlanSource?
  }
  struct FeatureValue: Decodable, Sendable {
    var configuration: Limit?
    var group: GroupValue?
    var metered: Limit?
    var `switch`: Bool?
  }
  struct GrantSource: Decodable, Sendable {
    var grantId: String?
    var throughFeatureKey: String?
    var until: Int64?
    var value: FeatureValue?
  }
  struct GroupMember: Decodable, Sendable {
    var configuration: Limit?
    var featureKey: String?
    var group: GroupValue?
    var metered: Limit?
    var `switch`: Bool?
  }
  struct GroupSource: Decodable, Sendable {
    var featureKeys: [String]?
  }
  struct GroupValue: Decodable, Sendable {
    var members: [GroupMember]?
  }
  struct Limit: Decodable, Sendable {
    var count: Int64?
    var unlimited: Unlimited?
  }
  struct ListEntitlementsResponse: Decodable, Sendable {
    var asOf: Int64?
    var customer: EntitledCustomer?
    var entitlements: [Entitlement]?
    var nextChangeAt: Int64?
    var served: ServedCatalogue?
  }
  struct Meter: Decodable, Sendable {
    var banked: Int64?
    var held: Int64?
    var remaining: Limit?
    var resetsAt: Int64?
    var used: Int64?
  }
  struct NothingServed: Decodable, Sendable {}
  struct PlanSource: Decodable, Sendable {
    var planId: String?
    var planKey: String?
    var planName: String?
    var productId: String?
    var throughFeatureKey: String?
    var value: FeatureValue?
    var versionNumber: Int64?
  }
  struct ServedCatalogue: Decodable, Sendable {
    var changeId: String?
    var nothing: NothingServed?
    var release: ServedRelease?
    var track: ServedTrack?
  }
  struct ServedRelease: Decodable, Sendable {
    var id: String?
    var number: Int64?
  }
  struct ServedTrack: Decodable, Sendable {
    var id: String?
    var name: String?
  }
  struct Unlimited: Decodable, Sendable {}
  struct Upgrade: Decodable, Sendable {
    var action: UpgradeAction?
    var kind: UpgradeKind?
    var move: UpgradeMove?
    var planId: String?
    var planKey: String?
    var planName: String?
    var productId: String?
  }
  typealias UpgradeAction = String
  typealias UpgradeKind = String
  typealias UpgradeMove = String

  static let entitlementsCheckFeature = Route(
    method: "GET", path: "/v1/customers/{customer.external_id}/entitlements/{feature_key}",
    query: ["target.team_id", "target.project_id", "target.environment_id", "as_of"])
  static let entitlementsListEntitlements = Route(
    method: "GET", path: "/v1/customers/{customer.external_id}/entitlements",
    query: ["target.team_id", "target.project_id", "target.environment_id", "as_of"])
}
