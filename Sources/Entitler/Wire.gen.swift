// Generated from openapi.json by `swift run generate-wire`. Do not edit.

enum Wire {
  struct Actor: Decodable, Sendable {
    var `id`: String
    var `type`: ActorType
  }
  typealias ActorType = String
  struct AddOnSource: Decodable, Sendable {
    var `planId`: String
    var `planKey`: String
    var `planName`: String
    var `quantity`: Int64
    var `throughFeatureKey`: String?
    var `value`: FeatureValue?
    var `versionNumber`: Int64
  }
  struct AdjustMeterResponse: Decodable, Sendable {
    var `saturated`: Bool
    var `tracked`: TrackedUsage?
  }
  struct Amount: Decodable, Sendable {
    var `amount`: Int64
    var `currency`: String
    var `display`: String
  }
  struct AppleListingIds: Decodable, Sendable {
    var `productId`: String
    var `subscriptionGroupId`: String?
  }
  struct AssignTrackResponse: Decodable, Sendable {
    var `assignment`: CustomerTrack?
    var `changed`: Bool
    var `endedTestHoldings`: Int64
  }
  typealias AssignmentSource = String
  struct CancelReportResponse: Decodable, Sendable {
    var `tracked`: TrackedUsage?
  }
  struct CheckFeatureResponse: Decodable, Sendable {
    var `asOf`: Int64
    var `customer`: EntitledCustomer?
    var `entitlement`: Entitlement?
    var `nextChangeAt`: Int64?
    var `served`: ServedCatalogue?
  }
  typealias ConnectionMode = String
  struct CreateGrantResponse: Decodable, Sendable {
    var `grant`: Grant?
    var `revision`: Int64
  }
  struct CreateHoldResponse: Decodable, Sendable {
    var `tracked`: TrackedUsage?
  }
  struct CreateSnapshotResponse: Decodable, Sendable {
    var `expiresAt`: Int64
    var `keyId`: String
    var `token`: String
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
  struct CustomerLineDiscount: Decodable, Sendable {
    var `amount`: Amount?
    var `offerId`: String
    var `offerKey`: String
    var `offerName`: String
  }
  typealias CustomerMoney = String
  struct CustomerPriceLine: Decodable, Sendable {
    var `discounts`: [CustomerLineDiscount]
    var `listPrice`: Amount?
    var `periodId`: String?
    var `planId`: String
    var `price`: Amount?
    var `quantity`: Int64
    var `state`: PlanPriceState
    var `unitPrice`: Amount?
    var `version`: Int64
  }
  struct CustomerPriceLines: Decodable, Sendable {
    var `lines`: [CustomerPriceLine]
  }
  struct CustomerPrices: Decodable, Sendable {
    var `market`: PricingMarket?
    var `subscriptions`: [SubscriptionPrice]
  }
  typealias CustomerTokenScope = String
  struct CustomerTrack: Decodable, Sendable {
    var `customerId`: String
    var `externalId`: String
    var `money`: CustomerMoney
    var `previousTrackId`: String?
    var `revision`: Int64
    var `source`: AssignmentSource
    var `trackId`: String?
  }
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
    var `currency`: String
    var `decimals`: Int64
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
  struct EveryMonths: Decodable, Sendable {
    var `firstAfterMonths`: Int64
    var `months`: Int64
  }
  struct FeatureValue: Decodable, Sendable {
    var `configuration`: Limit?
    var `group`: GroupValue?
    var `metered`: Limit?
    var `money`: MarketLimits?
    var `switch`: Bool?
  }
  typealias FeeDirection = String
  struct FeeSchedule: Decodable, Sendable {
    var `everyMonths`: EveryMonths?
    var `onPurchase`: OnPurchase?
    var `yearlyOn`: YearlyOn?
  }
  struct GetCustomerPricingResponse: Decodable, Sendable {
    var `prices`: CustomerPrices?
    var `pricing`: PricingSheet?
  }
  struct GetCustomerResponse: Decodable, Sendable {
    var `customer`: Customer?
  }
  struct GetPricingResponse: Decodable, Sendable {
    var `pricing`: PricingSheet?
  }
  struct GoogleListingIds: Decodable, Sendable {
    var `basePlanId`: String?
    var `offerId`: String?
    var `productId`: String
    var `purchaseOptionId`: String?
  }
  struct Grant: Decodable, Sendable {
    var `featureKey`: String
    var `from`: Int64
    var `grantedBy`: Actor?
    var `id`: String
    var `reason`: String
    var `revokeReason`: String?
    var `revokedAt`: Int64?
    var `revokedBy`: Actor?
    var `until`: Int64?
    var `value`: GrantValue?
  }
  struct GrantSource: Decodable, Sendable {
    var `grantId`: String
    var `throughFeatureKey`: String?
    var `until`: Int64?
    var `value`: FeatureValue?
  }
  struct GrantValue: Decodable, Sendable {
    var `limit`: Limit?
    var `on`: SwitchOn?
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
  struct ListingIds: Decodable, Sendable {
    var `apple`: AppleListingIds?
    var `google`: GoogleListingIds?
    var `stripe`: StripeListingIds?
  }
  struct ListingPrice: Decodable, Sendable {
    var `amount`: Int64
    var `currency`: String
    var `interval`: ListingPriceInterval
    var `intervalCount`: Int64
    var `tax`: ListingTaxBehaviour
  }
  typealias ListingPriceInterval = String
  typealias ListingTaxBehaviour = String
  struct MarketLimit: Decodable, Sendable {
    var `limit`: Limit?
    var `marketId`: String
  }
  struct MarketLimits: Decodable, Sendable {
    var `limits`: [MarketLimit]
  }
  typealias MarketTax = String
  struct Meter: Decodable, Sendable {
    var `banked`: Int64
    var `held`: Int64
    var `remaining`: Limit?
    var `resetsAt`: Int64?
    var `used`: Int64
  }
  struct NextCharge: Decodable, Sendable {
    var `amount`: Amount?
    var `at`: Int64
    var `direction`: FeeDirection
    var `feeKey`: String
  }
  struct NothingServed: Decodable, Sendable {}
  struct OnPurchase: Decodable, Sendable {}
  typealias PaymentProvider = String
  struct PeriodPrice: Decodable, Sendable {
    var `bands`: [PricedBand]
    var `periodId`: String?
    var `price`: Amount?
  }
  typealias PeriodUnit = String
  struct PlanItem: Decodable, Sendable {
    var `bank`: Limit?
    var `benefitThousandths`: Int64?
    var `featureKey`: String
    var `value`: FeatureValue?
  }
  typealias PlanKind = String
  struct PlanListing: Decodable, Sendable {
    var `channels`: [PricedChannel]
    var `periodId`: String?
  }
  typealias PlanPriceState = String
  struct PlanSource: Decodable, Sendable {
    var `planId`: String
    var `planKey`: String
    var `planName`: String
    var `productId`: String?
    var `throughFeatureKey`: String?
    var `value`: FeatureValue?
    var `versionNumber`: Int64
  }
  typealias PlanStatus = String
  struct PricedBand: Decodable, Sendable {
    var `amount`: Amount?
    var `perUnit`: Bool
    var `upTo`: Int64?
  }
  struct PricedChannel: Decodable, Sendable {
    var `connectionId`: String
    var `ids`: ListingIds?
    var `mode`: ConnectionMode
    var `name`: String
    var `price`: ListingPrice?
    var `provider`: PaymentProvider
    var `purchasable`: Bool
  }
  struct PricedFee: Decodable, Sendable {
    var `direction`: FeeDirection
    var `key`: String
    var `name`: String
    var `price`: Amount?
    var `schedule`: FeeSchedule?
  }
  struct PricedPeriod: Decodable, Sendable {
    var `count`: Int64
    var `id`: String
    var `key`: String
    var `label`: String
    var `unit`: PeriodUnit
  }
  struct PricedPlan: Decodable, Sendable {
    var `availableOn`: [String]
    var `byDefault`: Bool
    var `description`: String
    var `fees`: [PricedFee]
    var `id`: String
    var `items`: [PlanItem]
    var `key`: String
    var `kind`: PlanKind
    var `listings`: [PlanListing]
    var `name`: String
    var `periods`: [PricedPeriod]
    var `priceState`: PlanPriceState
    var `prices`: [PeriodPrice]
    var `productId`: String?
    var `quantity`: QuantityRule?
    var `salesLed`: Bool
    var `status`: PlanStatus
    var `trial`: TrialLength?
    var `versionNumber`: Int64
  }
  struct PricedProduct: Decodable, Sendable {
    var `defaultPlanId`: String?
    var `id`: String
    var `key`: String
    var `name`: String
  }
  struct PricingMarket: Decodable, Sendable {
    var `currency`: String
    var `id`: String
    var `key`: String
    var `name`: String
    var `tax`: MarketTax
  }
  struct PricingSheet: Decodable, Sendable {
    var `customer`: String?
    var `market`: PricingMarket?
    var `plans`: [PricedPlan]
    var `products`: [PricedProduct]
    var `served`: ServedCatalogue?
    var `testers`: Bool
  }
  struct QuantityRule: Decodable, Sendable {
    var `max`: Int64?
    var `min`: Int64
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
  struct RevokeGrantResponse: Decodable, Sendable {
    var `changed`: Bool
    var `grant`: Grant?
    var `revision`: Int64
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
  struct SnapshotKeySet: Decodable, Sendable {
    var `keys`: [[String: String]]
  }
  struct StripeListingIds: Decodable, Sendable {
    var `priceId`: String
  }
  struct SubscriptionPrice: Decodable, Sendable {
    var `atRenewal`: CustomerPriceLines?
    var `nextCharges`: [NextCharge]
    var `now`: [CustomerPriceLine]
    var `productId`: String?
    var `renewsAt`: Int64
    var `subscriptionId`: String
  }
  struct SwitchOn: Decodable, Sendable {}
  struct TrackedUsage: Decodable, Sendable {
    var `asOf`: Int64
    var `customer`: EntitledCustomer?
    var `entitlement`: Entitlement?
    var `served`: ServedCatalogue?
    var `usage`: UsageResult?
  }
  struct TrialLength: Decodable, Sendable {
    var `days`: Int64?
    var `months`: Int64?
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
    var `saturated`: Bool
    var `usageId`: String?
  }
  struct YearlyDate: Decodable, Sendable {
    var `day`: Int64
    var `month`: Int64
  }
  struct YearlyOn: Decodable, Sendable {
    var `dates`: [YearlyDate]
  }

  static let customerTokensCreateToken = Route(
    method: "POST", path: "/v1/customers/{external_id}/tokens", query: [])
  static let customerTracksAssignTrack = Route(
    method: "PUT", path: "/v1/customers/{external_id}/track", query: [])
  static let customersEraseCustomer = Route(
    method: "POST", path: "/v1/customers/{external_id}:erase", query: [])
  static let customersGetCustomer = Route(
    method: "GET", path: "/v1/customers/{external_id}",
    query: ["target.team_id", "target.project_id", "target.environment_id"])
  static let customersRegisterCustomer = Route(
    method: "PUT", path: "/v1/customers/{external_id}", query: [])
  static let customersUpdateCustomer = Route(
    method: "PATCH", path: "/v1/customers/{external_id}", query: [])
  static let entitlementsCheckFeature = Route(
    method: "GET", path: "/v1/customers/{external_id}/entitlements/{feature_key}",
    query: ["target.team_id", "target.project_id", "target.environment_id", "as_of"])
  static let entitlementsListEntitlements = Route(
    method: "GET", path: "/v1/customers/{external_id}/entitlements",
    query: ["target.team_id", "target.project_id", "target.environment_id", "as_of"])
  static let grantsCreateGrant = Route(
    method: "POST", path: "/v1/customers/{external_id}/grants", query: [])
  static let grantsRevokeGrant = Route(
    method: "POST", path: "/v1/customers/{external_id}/grants/{grant_id}:revoke", query: [])
  static let pricingGetCustomerPricing = Route(
    method: "GET", path: "/v1/customers/{external_id}/pricing",
    query: ["target.team_id", "target.project_id", "target.environment_id"])
  static let pricingGetPricing = Route(
    method: "GET", path: "/v1/pricing",
    query: ["target.team_id", "target.project_id", "target.environment_id", "market", "country"])
  static let snapshotKeys = Route(method: "GET", path: "/v1/snapshot-keys", query: [])
  static let snapshotsCreateSnapshot = Route(
    method: "POST", path: "/v1/customers/{external_id}/snapshots", query: [])
  static let usageAdjustMeter = Route(
    method: "POST", path: "/v1/customers/{external_id}/meters/{feature_key}:adjust", query: [])
  static let usageCancelReport = Route(
    method: "POST", path: "/v1/customers/{external_id}/usage/{usage_id}:cancel", query: [])
  static let usageCreateHold = Route(
    method: "POST", path: "/v1/customers/{external_id}/usage/holds", query: [])
  static let usageReleaseHold = Route(
    method: "DELETE", path: "/v1/customers/{external_id}/usage/holds/{hold_id}",
    query: ["target.team_id", "target.project_id", "target.environment_id"])
  static let usageReportUsage = Route(
    method: "POST", path: "/v1/customers/{external_id}/usage", query: [])
  static let usageSettleHold = Route(
    method: "POST", path: "/v1/customers/{external_id}/usage/holds/{hold_id}:settle", query: [])
}
