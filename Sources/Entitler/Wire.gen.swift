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
  struct BilledPlan: Decodable, Sendable {
    var `billingConnectionId`: String?
    var `cohortId`: String?
    var `periodId`: String?
    var `planId`: String
    var `since`: Int64
    var `versionNumber`: Int64
  }
  struct BilledProduct: Decodable, Sendable {
    var `connectionId`: String
    var `drift`: BillingDrift?
    var `items`: Int64
    var `productId`: String?
    var `renews`: Bool
    var `sku`: BilledSku?
    var `status`: ProviderSubscriptionStatus
  }
  struct BilledSku: Decodable, Sendable {
    var `periodId`: String?
    var `price`: ListingPrice?
    var `priceId`: String
  }
  struct BillingDrift: Decodable, Sendable {
    var `billedPlanId`: String
    var `heldPlanId`: String?
    var `observedAt`: Int64
    var `productId`: String?
  }
  struct BillingPeriodReset: Decodable, Sendable {}
  struct CancelPendingAddOnChangeResponse: Decodable, Sendable {
    var `confirming`: PaymentConfirming?
    var `done`: MoveResult?
    var `pay`: PaymentStep?
  }
  struct CancelPendingChangeResponse: Decodable, Sendable {
    var `confirming`: PaymentConfirming?
    var `done`: MoveResult?
    var `pay`: PaymentStep?
  }
  struct CancelReportResponse: Decodable, Sendable {
    var `tracked`: TrackedUsage?
  }
  struct CancelSubscriptionResponse: Decodable, Sendable {
    var `confirming`: PaymentConfirming?
    var `done`: MoveResult?
    var `pay`: PaymentStep?
  }
  struct Cancellation: Decodable, Sendable {
    var `chargedBack`: Amount?
    var `endsAt`: Int64
    var `exitFee`: Amount?
  }
  struct CheckFeatureResponse: Decodable, Sendable {
    var `asOf`: Int64
    var `customer`: EntitledCustomer?
    var `entitlement`: Entitlement?
    var `nextChangeAt`: Int64?
    var `served`: ServedCatalogue?
  }
  struct ChooseSubscriptionResponse: Decodable, Sendable {
    var `confirming`: PaymentConfirming?
    var `done`: MoveResult?
    var `pay`: PaymentStep?
  }
  typealias ConnectionMode = String
  struct CreateGrantResponse: Decodable, Sendable {
    var `grant`: Grant?
    var `revision`: Int64
  }
  struct CreateHoldResponse: Decodable, Sendable {
    var `tracked`: TrackedUsage?
  }
  struct CreatePortalSessionResponse: Decodable, Sendable {
    var `url`: String
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
  struct CustomerBilling: Decodable, Sendable {
    var `connectionId`: String?
    var `drift`: BillingDrift?
    var `items`: Int64
    var `linked`: Bool
    var `products`: [BilledProduct]
    var `renews`: Bool
    var `sku`: BilledSku?
    var `status`: ProviderSubscriptionStatus
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
  typealias DeviceAtLimit = String
  struct DeviceLimit: Decodable, Sendable {
    var `atLimit`: DeviceAtLimit
    var `kind`: DeviceLimitKind
    var `lockoutMinutes`: [Int64]
    var `lockoutQuietDays`: Int64?
  }
  typealias DeviceLimitKind = String
  typealias DiscountGivenBy = String
  typealias Effective = String
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
  struct Feature: Decodable, Sendable {
    var `archived`: Bool
    var `id`: String
    var `key`: String
    var `kind`: FeatureKind
    var `version`: FeatureVersion?
  }
  struct FeatureImpact: Decodable, Sendable {
    var `featureKey`: String
    var `from`: FeatureValue?
    var `kind`: ImpactKind
    var `to`: FeatureValue?
  }
  typealias FeatureKind = String
  struct FeatureValue: Decodable, Sendable {
    var `configuration`: Limit?
    var `group`: GroupValue?
    var `metered`: Limit?
    var `money`: MarketLimits?
    var `switch`: Bool?
  }
  struct FeatureVersion: Decodable, Sendable {
    var `changeId`: String?
    var `description`: String
    var `deviceLimit`: DeviceLimit?
    var `lateDays`: Int64?
    var `measure`: Measure?
    var `members`: GroupValue?
    var `name`: String
    var `number`: Int64
    var `reset`: MeterReset?
    var `rounding`: Rounding?
    var `sharesLimit`: Bool
    var `unit`: String
    var `zones`: [Zone]
  }
  typealias FeeDirection = String
  struct FeeSchedule: Decodable, Sendable {
    var `everyMonths`: EveryMonths?
    var `onPurchase`: OnPurchase?
    var `yearlyOn`: YearlyOn?
  }
  struct GetBillingResponse: Decodable, Sendable {
    var `billing`: CustomerBilling?
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
  struct HeldAddOn: Decodable, Sendable {
    var `addedAt`: Int64
    var `billingConnectionId`: String?
    var `cohortId`: String?
    var `cohortNumber`: Int64?
    var `lockedUntil`: Int64?
    var `money`: CustomerMoney
    var `movingToPlanId`: String?
    var `planId`: String
    var `planKey`: String
    var `planName`: String
    var `purchaseSource`: String?
    var `quantity`: Int64
    var `required`: Bool
    var `versionNumber`: Int64
  }
  struct HeldDiscount: Decodable, Sendable {
    var `amount`: Amount?
    var `applied`: Bool
    var `fees`: [OfferFee]
    var `givenAt`: Int64
    var `givenBy`: DiscountGivenBy
    var `minimumStayMonths`: Int64?
    var `offerId`: String
    var `offerKey`: String
    var `offerName`: String
    var `percentThousandths`: Int64?
    var `periodIds`: [String]
    var `periodsLeft`: Int64?
    var `planIds`: [String]
    var `startsAt`: Int64?
    var `until`: Int64?
  }
  struct HeldPlan: Decodable, Sendable {
    var `billingConnectionId`: String?
    var `byDefault`: Bool
    var `cohortId`: String?
    var `cohortNumber`: Int64?
    var `lockedUntil`: Int64?
    var `money`: CustomerMoney
    var `periodId`: String?
    var `planId`: String
    var `planKey`: String
    var `planName`: String
    var `purchaseSource`: String?
    var `versionNumber`: Int64
  }
  struct HeldTerm: Decodable, Sendable {
    var `endsAt`: Int64
    var `then`: TermThen
  }
  struct Holdings: Decodable, Sendable {
    var `grants`: [Grant]
    var `lanes`: [LaneHolding]
  }
  typealias ImpactKind = String
  struct LaneHolding: Decodable, Sendable {
    var `addOns`: [HeldAddOn]
    var `billed`: BilledPlan?
    var `cancellation`: Cancellation?
    var `cancelsAt`: Int64?
    var `collection`: SubscriptionCollection
    var `contractStartedAt`: Int64?
    var `discounts`: [HeldDiscount]
    var `paidUntil`: Int64?
    var `paymentAmount`: Amount?
    var `paymentDays`: Int64?
    var `paymentDueAt`: Int64?
    var `pending`: PendingChange?
    var `periodsAhead`: Int64
    var `plan`: HeldPlan?
    var `productId`: String?
    var `renewsAt`: Int64?
    var `scheduledChanges`: [ScheduledChange]
    var `startedAt`: Int64?
    var `term`: HeldTerm?
    var `trialEndsAt`: Int64?
    var `until`: Int64?
  }
  struct Limit: Decodable, Sendable {
    var `count`: Int64?
    var `unlimited`: Unlimited?
  }
  struct ListAvailablePlansResponse: Decodable, Sendable {
    var `asOf`: Int64
    var `customerId`: String?
    var `holdings`: Holdings?
    var `options`: [PlanOption]
  }
  struct ListEntitlementsResponse: Decodable, Sendable {
    var `asOf`: Int64
    var `customer`: EntitledCustomer?
    var `entitlements`: [Entitlement]
    var `nextChangeAt`: Int64?
    var `served`: ServedCatalogue?
  }
  struct ListFeaturesOnSaleResponse: Decodable, Sendable {
    var `features`: [Feature]
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
  struct Measure: Decodable, Sendable {
    var `decimals`: Int64?
    var `money`: Money?
  }
  struct Meter: Decodable, Sendable {
    var `banked`: Int64
    var `held`: Int64
    var `remaining`: Limit?
    var `resetsAt`: Int64?
    var `used`: Int64
  }
  struct MeterReset: Decodable, Sendable {
    var `billingPeriod`: BillingPeriodReset?
    var `window`: MeterWindow?
  }
  struct MeterWindow: Decodable, Sendable {
    var `anchor`: WindowAnchor
    var `count`: Int64
    var `unit`: WindowUnit
  }
  struct Money: Decodable, Sendable {}
  struct MoveResult: Decodable, Sendable {
    var `change`: PlanChange?
    var `customerId`: String
    var `holdings`: Holdings?
    var `money`: CustomerMoney
    var `revision`: Int64
  }
  typealias MoveTiming = String
  struct NextCharge: Decodable, Sendable {
    var `amount`: Amount?
    var `at`: Int64
    var `direction`: FeeDirection
    var `feeKey`: String
  }
  struct NothingServed: Decodable, Sendable {}
  struct OfferFee: Decodable, Sendable {
    var `feeKey`: String
    var `planId`: String
  }
  struct OnPurchase: Decodable, Sendable {}
  typealias OptionKind = String
  struct PaymentConfirming: Decodable, Sendable {}
  typealias PaymentProvider = String
  struct PaymentStep: Decodable, Sendable {
    var `status`: PaymentStepStatus
    var `url`: String
  }
  typealias PaymentStepStatus = String
  struct PendingCancel: Decodable, Sendable {}
  struct PendingChange: Decodable, Sendable {
    var `at`: Int64
    var `cancel`: PendingCancel?
    var `move`: PendingPlanMove?
  }
  struct PendingPlanMove: Decodable, Sendable {
    var `periodId`: String?
    var `planId`: String
    var `until`: Int64?
  }
  struct PeriodPrice: Decodable, Sendable {
    var `bands`: [PricedBand]
    var `periodId`: String?
    var `price`: Amount?
  }
  typealias PeriodUnit = String
  struct PlanChange: Decodable, Sendable {
    var `at`: Int64
    var `changed`: Bool
    var `effective`: Effective
    var `plan`: HeldPlan?
    var `policy`: SubscriptionMovePolicy
    var `productId`: String?
    var `quantity`: Int64?
    var `until`: Int64?
  }
  typealias PlanDirection = String
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
  struct PlanOption: Decodable, Sendable {
    var `direction`: PlanDirection
    var `impact`: [FeatureImpact]
    var `kind`: OptionKind
    var `periodIds`: [String]
    var `planId`: String
    var `planKey`: String
    var `planName`: String
    var `productId`: String?
    var `replacesPlanId`: String?
    var `selling`: Selling
    var `timing`: MoveTiming
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
  typealias ProviderSubscriptionStatus = String
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
  struct RemoveAddOnResponse: Decodable, Sendable {
    var `confirming`: PaymentConfirming?
    var `done`: MoveResult?
    var `pay`: PaymentStep?
  }
  struct ReportUsageResponse: Decodable, Sendable {
    var `tracked`: TrackedUsage?
  }
  struct RevokeGrantResponse: Decodable, Sendable {
    var `changed`: Bool
    var `grant`: Grant?
    var `revision`: Int64
  }
  typealias Rounding = String
  struct ScheduledChange: Decodable, Sendable {
    var `acceptanceRequired`: Bool
    var `accepted`: Bool
    var `amount`: Amount?
    var `effectiveAt`: Int64
    var `planId`: String
    var `rolloutId`: String
    var `versionNumber`: Int64
  }
  typealias Selling = String
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
  struct SetAddOnResponse: Decodable, Sendable {
    var `confirming`: PaymentConfirming?
    var `done`: MoveResult?
    var `pay`: PaymentStep?
  }
  struct SetPlanResponse: Decodable, Sendable {
    var `confirming`: PaymentConfirming?
    var `done`: MoveResult?
    var `pay`: PaymentStep?
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
  typealias SubscriptionCollection = String
  typealias SubscriptionMovePolicy = String
  struct SubscriptionPrice: Decodable, Sendable {
    var `atRenewal`: CustomerPriceLines?
    var `nextCharges`: [NextCharge]
    var `now`: [CustomerPriceLine]
    var `productId`: String?
    var `renewsAt`: Int64
    var `subscriptionId`: String
  }
  struct SwitchOn: Decodable, Sendable {}
  struct SyncBillingResponse: Decodable, Sendable {
    var `changed`: Bool
  }
  typealias TermThen = String
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
  typealias WindowAnchor = String
  typealias WindowUnit = String
  struct YearlyDate: Decodable, Sendable {
    var `day`: Int64
    var `month`: Int64
  }
  struct YearlyOn: Decodable, Sendable {
    var `dates`: [YearlyDate]
  }
  struct Zone: Decodable, Sendable {
    var `key`: String
    var `name`: String
  }

  static let billingCreatePortalSession = Route(
    method: "POST", path: "/v1/customers/{external_id}/billing/portal-sessions", query: [])
  static let billingGetBilling = Route(
    method: "GET", path: "/v1/customers/{external_id}/billing",
    query: ["target.team_id", "target.project_id", "target.environment_id"])
  static let billingSyncBilling = Route(
    method: "POST", path: "/v1/customers/{external_id}/billing:sync", query: [])
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
  static let pricingListFeaturesOnSale = Route(
    method: "GET", path: "/v1/pricing/features",
    query: ["target.team_id", "target.project_id", "target.environment_id"])
  static let snapshotKeys = Route(method: "GET", path: "/v1/snapshot-keys", query: [])
  static let snapshotsCreateSnapshot = Route(
    method: "POST", path: "/v1/customers/{external_id}/snapshots", query: [])
  static let subscriptionsCancelPendingAddOnChange = Route(
    method: "POST", path: "/v1/customers/{external_id}/add-ons/{plan_key}:cancelPendingChange",
    query: [])
  static let subscriptionsCancelPendingChange = Route(
    method: "POST", path: "/v1/customers/{external_id}/subscription:cancelPendingChange", query: [])
  static let subscriptionsCancelSubscription = Route(
    method: "POST", path: "/v1/customers/{external_id}/subscription:cancel", query: [])
  static let subscriptionsChooseSubscription = Route(
    method: "POST", path: "/v1/customers/{external_id}/subscription", query: [])
  static let subscriptionsListAvailablePlans = Route(
    method: "GET", path: "/v1/customers/{external_id}/plans",
    query: ["target.team_id", "target.project_id", "target.environment_id", "as_of"])
  static let subscriptionsRemoveAddOn = Route(
    method: "POST", path: "/v1/customers/{external_id}/add-ons/{plan_key}:remove", query: [])
  static let subscriptionsSetAddOn = Route(
    method: "PUT", path: "/v1/customers/{external_id}/add-ons/{plan_key}", query: [])
  static let subscriptionsSetPlan = Route(
    method: "PUT", path: "/v1/customers/{external_id}/plan", query: [])
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
