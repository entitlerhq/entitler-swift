// Generated from openapi.json by `swift run generate-wire`. Do not edit.

enum Wire {
  struct AddOnSource: Decodable, Sendable {
    var `planId`: String
    var `planKey`: String
    var `planName`: String
    var `quantity`: Int64
    var `throughFeatureKey`: String?
    var `value`: FeatureValue?
    var `versionNumber`: Int64
  }
  struct CheckFeatureResponse: Decodable, Sendable {
    var `asOf`: Int64
    var `customer`: EntitledCustomer?
    var `entitlement`: Entitlement?
    var `nextChangeAt`: Int64?
    var `served`: ServedCatalogue?
  }
  struct CreateHoldResponse: Decodable, Sendable {
    var `tracked`: TrackedUsage?
  }
  struct CreateTokenResponse: Decodable, Sendable {
    var `customerId`: String?
    var `expiresAt`: Int64
    var `scopes`: [CustomerTokenScope]
    var `token`: String
    var `tokenId`: String
  }
  struct Customer: Decodable, Sendable {
    var `attributes`: [CustomerAttribute]
    var `createdAt`: Int64
    var `email`: String?
    var `environmentId`: String
    var `externalId`: String
    var `id`: String
    var `identityProviderId`: String?
    var `marketId`: String?
    var `money`: CustomerMoney
    var `name`: String?
    var `projectId`: String
    var `revision`: Int64
    var `trackId`: String?
    var `updatedAt`: Int64
  }
  struct CustomerAttribute: Decodable, Sendable {
    var `key`: String
    var `value`: String
  }
  typealias CustomerMoney = String
  typealias CustomerTokenScope = String
  struct DefaultPlanSource: Decodable, Sendable {
    var `planId`: String
    var `planKey`: String
    var `planName`: String
    var `productId`: String?
    var `throughFeatureKey`: String?
    var `versionNumber`: Int64
  }
  struct EntitledCustomer: Decodable, Sendable {
    var `customerId`: String?
    var `externalId`: String
  }
  typealias EntitledFeatureKind = String
  struct Entitlement: Decodable, Sendable {
    var `entitled`: Bool
    var `featureKey`: String
    var `kind`: EntitledFeatureKind
    var `meter`: Meter?
    var `sources`: [EntitlementSource]
    var `upgrades`: [Upgrade]
    var `value`: FeatureValue?
  }
  struct EntitlementSource: Decodable, Sendable {
    var `addOn`: AddOnSource?
    var `defaultPlan`: DefaultPlanSource?
    var `grant`: GrantSource?
    var `group`: GroupSource?
    var `plan`: PlanSource?
  }
  struct EraseCustomerResponse: Decodable, Sendable {
    var `erased`: Int64
  }
  struct FeatureValue: Decodable, Sendable {
    var `configuration`: Limit?
    var `group`: GroupValue?
    var `metered`: Limit?
    var `switch`: Bool?
  }
  struct GetCustomerResponse: Decodable, Sendable {
    var `customer`: Customer?
  }
  struct GrantSource: Decodable, Sendable {
    var `grantId`: String
    var `throughFeatureKey`: String?
    var `until`: Int64?
    var `value`: FeatureValue?
  }
  struct GroupMember: Decodable, Sendable {
    var `configuration`: Limit?
    var `featureKey`: String
    var `group`: GroupValue?
    var `metered`: Limit?
    var `switch`: Bool?
  }
  struct GroupSource: Decodable, Sendable {
    var `featureKeys`: [String]
  }
  struct GroupValue: Decodable, Sendable {
    var `members`: [GroupMember]
  }
  struct Limit: Decodable, Sendable {
    var `count`: Int64?
    var `unlimited`: Unlimited?
  }
  struct ListEntitlementsResponse: Decodable, Sendable {
    var `asOf`: Int64
    var `customer`: EntitledCustomer?
    var `entitlements`: [Entitlement]
    var `nextChangeAt`: Int64?
    var `served`: ServedCatalogue?
  }
  struct Meter: Decodable, Sendable {
    var `banked`: Int64
    var `held`: Int64
    var `remaining`: Limit?
    var `resetsAt`: Int64?
    var `used`: Int64
  }
  struct NothingServed: Decodable, Sendable {}
  struct PlanSource: Decodable, Sendable {
    var `planId`: String
    var `planKey`: String
    var `planName`: String
    var `productId`: String?
    var `throughFeatureKey`: String?
    var `value`: FeatureValue?
    var `versionNumber`: Int64
  }
  struct RegisterCustomerResponse: Decodable, Sendable {
    var `created`: Bool
    var `customer`: Customer?
  }
  struct ReleaseHoldResponse: Decodable, Sendable {
    var `tracked`: TrackedUsage?
  }
  struct ReportUsageResponse: Decodable, Sendable {
    var `tracked`: TrackedUsage?
  }
  struct ServedCatalogue: Decodable, Sendable {
    var `changeId`: String?
    var `nothing`: NothingServed?
    var `release`: ServedRelease?
    var `track`: ServedTrack?
  }
  struct ServedRelease: Decodable, Sendable {
    var `id`: String
    var `number`: Int64
  }
  struct ServedTrack: Decodable, Sendable {
    var `id`: String
    var `name`: String
  }
  struct SettleHoldResponse: Decodable, Sendable {
    var `tracked`: TrackedUsage?
  }
  struct TrackedUsage: Decodable, Sendable {
    var `asOf`: Int64
    var `customer`: EntitledCustomer?
    var `entitlement`: Entitlement?
    var `served`: ServedCatalogue?
    var `usage`: UsageResult?
  }
  struct Unlimited: Decodable, Sendable {}
  struct UpdateCustomerResponse: Decodable, Sendable {
    var `customer`: Customer?
  }
  struct Upgrade: Decodable, Sendable {
    var `action`: UpgradeAction
    var `kind`: UpgradeKind
    var `move`: UpgradeMove
    var `planId`: String
    var `planKey`: String
    var `planName`: String
    var `productId`: String?
  }
  typealias UpgradeAction = String
  typealias UpgradeKind = String
  typealias UpgradeMove = String
  typealias UsageMode = String
  typealias UsageOutcome = String
  typealias UsageRefusal = String
  struct UsageResult: Decodable, Sendable {
    var `amount`: Int64
    var `expiresAtMs`: Int64?
    var `holdId`: String?
    var `late`: Bool
    var `meterChange`: Int64
    var `mode`: UsageMode
    var `occurredAtMs`: Int64?
    var `outcome`: UsageOutcome
    var `overBy`: Int64
    var `refusal`: UsageRefusal?
    var `replayed`: Bool
    var `usageId`: String?
  }

  static let customerTokensCreateToken = Route(
    method: "POST", path: "/v1/customers/{external_id}/tokens", query: [])
  static let customersEraseCustomer = Route(
    method: "POST", path: "/v1/customers/{external_id}:erase", query: [])
  static let customersGetCustomer = Route(
    method: "GET", path: "/v1/customers/{external_id}",
    query: ["target.team_id", "target.project_id", "target.environment_id"])
  static let customersRegisterCustomer = Route(
    method: "PUT", path: "/v1/customers/{customer.external_id}", query: [])
  static let customersUpdateCustomer = Route(
    method: "PATCH", path: "/v1/customers/{external_id}", query: [])
  static let entitlementsCheckFeature = Route(
    method: "GET", path: "/v1/customers/{customer.external_id}/entitlements/{feature_key}",
    query: ["target.team_id", "target.project_id", "target.environment_id", "as_of"])
  static let entitlementsListEntitlements = Route(
    method: "GET", path: "/v1/customers/{customer.external_id}/entitlements",
    query: ["target.team_id", "target.project_id", "target.environment_id", "as_of"])
  static let usageCreateHold = Route(
    method: "POST", path: "/v1/customers/{customer.external_id}/usage/holds", query: [])
  static let usageReleaseHold = Route(
    method: "DELETE", path: "/v1/customers/{customer.external_id}/usage/holds/{hold_id}",
    query: ["target.team_id", "target.project_id", "target.environment_id"])
  static let usageReportUsage = Route(
    method: "POST", path: "/v1/customers/{customer.external_id}/usage", query: [])
  static let usageSettleHold = Route(
    method: "POST", path: "/v1/customers/{customer.external_id}/usage/holds/{hold_id}:settle",
    query: [])
}
