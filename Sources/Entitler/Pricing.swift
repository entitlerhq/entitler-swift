import Foundation

/// An amount of money: a whole number of the currency's minor unit, and how to show it.
public struct Amount: Hashable, Sendable {
  /// The amount in the currency's minor unit, such as cents.
  public let amount: Int64
  /// The lower-case currency code.
  public let currency: String
  /// The amount formatted for the request's locale, such as `$12.00`.
  public let display: String
}

/// The market prices are in.
public struct PricingMarket: Hashable, Sendable {
  /// The market's id.
  public let id: String
  /// The market's key.
  public let key: String
  /// The market's name.
  public let name: String
  /// The lower-case currency code its prices are in.
  public let currency: String
  /// `included` when its prices include tax, `added` when tax is added.
  public let tax: OpenName
}

/// A product on sale.
public struct PricedProduct: Hashable, Sendable {
  /// The product's id.
  public let id: String
  /// The product's key.
  public let key: String
  /// The product's name.
  public let name: String
  /// The plan a customer holds by default, or `nil`.
  public let defaultPlanID: String?
}

/// A billing period a plan is sold for.
public struct PricedPeriod: Hashable, Sendable {
  /// The period's id.
  public let id: String
  /// The period's key, such as `monthly`.
  public let key: String
  /// The period's label, such as `Monthly`.
  public let label: String
  /// How many units it lasts.
  public let count: Int64
  /// Its unit: `days`, `weeks` or `months`.
  public let unit: OpenName
}

/// One band of a tiered or per-unit price.
public struct PricedBand: Hashable, Sendable {
  /// The quantity the band runs up to, or `nil` for the last band.
  public let upTo: Int64?
  /// True when the amount is per unit, false when it is for the whole band.
  public let perUnit: Bool
  /// The band's amount, or `nil`.
  public let amount: Amount?
}

/// A plan's price for one period.
public struct PeriodPrice: Hashable, Sendable {
  /// The period's id, or `nil` for a price with no period.
  public let period: String?
  /// The price, or `nil` when the plan is not priced in the market.
  public let price: Amount?
  /// The bands of a price that depends on quantity; empty otherwise.
  public let bands: [PricedBand]
}

/// A day of the year.
public struct YearlyDate: Hashable, Sendable {
  /// The month, 1 to 12.
  public let month: Int64
  /// The day of the month.
  public let day: Int64
}

/// When a fee is charged.
public enum FeeSchedule: Hashable, Sendable {
  /// Once, on purchase.
  case onPurchase
  /// Every `months` months, the first `firstAfterMonths` months after purchase.
  case everyMonths(months: Int64, firstAfterMonths: Int64)
  /// On each of these dates every year.
  case yearly(dates: [YearlyDate])
}

/// A fee a plan charges or credits beside its price.
public struct PricedFee: Hashable, Sendable {
  /// The fee's key.
  public let key: String
  /// The fee's name.
  public let name: String
  /// `debit` charges the customer, `credit` pays them.
  public let direction: OpenName
  /// The fee's amount, or `nil`.
  public let price: Amount?
  /// When it is charged, or `nil`.
  public let schedule: FeeSchedule?
}

/// A feature a plan gives.
public struct PlanItem: Hashable, Sendable {
  /// The feature's key.
  public let feature: String
  /// The value the plan gives; ``FeatureValue/on`` for an on/off feature or a group, and `0` for
  /// money.
  public let value: FeatureValue
  /// A money value's limit in each market, by market id, or `nil` for a value that isn't money.
  public let markets: [String: Limit]?
  /// How much unused allowance carries over, or `nil`.
  public let bank: Limit?
  /// The benefit a group member's share counts for, in thousandths, or `nil`.
  public let benefitThousandths: Int64?
}

/// A store's price for a listing.
public struct ListingPrice: Hashable, Sendable {
  /// The amount in the currency's minor unit.
  public let amount: Int64
  /// The lower-case currency code.
  public let currency: String
  /// How often it renews: `day`, `week`, `month` or `year`.
  public let interval: OpenName
  /// How many intervals each renewal spans.
  public let intervalCount: Int64
  /// `inclusive` or `exclusive` of tax.
  public let tax: OpenName
}

/// A store or payment provider a plan is listed in.
public struct PricedChannel: Hashable, Sendable {
  /// The payment provider: `stripe`, `apple` or `google`.
  public let provider: OpenName
  /// The connection's id.
  public let connectionID: String
  /// The connection's name.
  public let name: String
  /// `live` or `test`.
  public let mode: OpenName
  /// True when the customer can buy it there now.
  public let purchasable: Bool
  /// The provider's ids for the listing, as the provider names them, such as `productId` and
  /// `subscriptionGroupId` for the App Store.
  public let ids: [String: String]
  /// The provider's price, or `nil`.
  public let price: ListingPrice?
}

/// Where a plan is listed for one period.
public struct PlanListing: Hashable, Sendable {
  /// The period's id, or `nil`.
  public let period: String?
  /// The stores and payment providers it is listed in.
  public let channels: [PricedChannel]
}

/// The trial a new subscriber gets.
public struct Trial: Hashable, Sendable {
  /// Its days.
  public let days: Int64
  /// Its months.
  public let months: Int64
}

/// How many of a plan a customer may hold.
public struct QuantityRule: Hashable, Sendable {
  /// The fewest.
  public let min: Int64
  /// The most, or `nil` for no limit.
  public let max: Int64?
}

/// A plan or add-on on sale, with its prices in the sheet's market.
public struct PricedPlan: Hashable, Sendable {
  /// The plan's id.
  public let id: String
  /// The plan's key.
  public let key: String
  /// The plan's name.
  public let name: String
  /// The plan's description.
  public let description: String
  /// `plan` or `add_on`.
  public let kind: OpenName
  /// The product's id, or `nil`.
  public let product: String?
  /// The plan version on sale.
  public let version: Int64
  /// True for the product's default plan.
  public let byDefault: Bool
  /// `active`, `legacy` or `archived`.
  public let status: OpenName
  /// True when only the company sells it.
  public let salesLed: Bool
  /// `free`, `priced`, or `not_priced` in the sheet's market.
  public let priceState: OpenName
  /// The trial a new subscriber gets, or `nil`.
  public let trial: Trial?
  /// How many a customer may hold, or `nil` when it has no quantity.
  public let quantity: QuantityRule?
  /// The periods it is sold for.
  public let periods: [PricedPeriod]
  /// Its price for each period.
  public let prices: [PeriodPrice]
  /// Its fees.
  public let fees: [PricedFee]
  /// The features it gives.
  public let items: [PlanItem]
  /// The plans it can be added to, for an add-on.
  public let availableOn: [String]
  /// Where it is listed for sale.
  public let listings: [PlanListing]
}

/// The plans on sale and their prices.
public struct PricingSheet: Hashable, Sendable, StaleMarking {
  /// The market prices are in, or `nil` when none was asked for.
  public let market: PricingMarket?
  /// The products on sale.
  public let products: [PricedProduct]
  /// The plans and add-ons on sale.
  public let plans: [PricedPlan]
  /// The catalogue the sheet comes from.
  public let served: Served
  /// True when the sheet is a testers' track.
  public let testers: Bool
  /// The customer's external id for a customer's sheet, else `nil`.
  public let customer: String?
  /// True only when the SDK answered from a kept copy because Entitler was unreachable.
  public internal(set) var stale = false
}

/// An offer's discount on a price line.
public struct LineDiscount: Hashable, Sendable {
  /// The offer's id.
  public let offerID: String
  /// The offer's key.
  public let offerKey: String
  /// The offer's name.
  public let offerName: String
  /// The discount, or `nil`.
  public let amount: Amount?
}

/// One plan's line on a customer's subscription.
public struct PriceLine: Hashable, Sendable {
  /// The plan's id.
  public let planID: String
  /// The plan version held.
  public let version: Int64
  /// The period's id, or `nil`.
  public let period: String?
  /// How many are held.
  public let quantity: Int64
  /// `free`, `priced` or `not_priced`.
  public let state: OpenName
  /// What the customer pays for the line, discounts taken off, or `nil`.
  public let price: Amount?
  /// The price of one, or `nil`.
  public let unitPrice: Amount?
  /// The price before discounts, or `nil`.
  public let listPrice: Amount?
  /// The discounts taken off.
  public let discounts: [LineDiscount]
}

/// A charge or credit a subscription will make.
public struct NextCharge: Hashable, Sendable {
  /// The fee's key.
  public let fee: String
  /// `debit` or `credit`.
  public let direction: OpenName
  /// When it happens.
  public let at: Date
  /// The amount, or `nil`.
  public let amount: Amount?
}

/// What a customer pays for one subscription.
public struct SubscriptionPrice: Hashable, Sendable {
  /// The subscription's id.
  public let subscriptionID: String
  /// The product's id, or `nil`.
  public let product: String?
  /// When it next renews.
  public let renewsAt: Date
  /// The lines it charges now.
  public let now: [PriceLine]
  /// The lines it will charge at renewal, or `nil` when nothing changes.
  public let atRenewal: [PriceLine]?
  /// The charges and credits coming.
  public let nextCharges: [NextCharge]
}

/// What a customer pays.
public struct CustomerPrices: Hashable, Sendable {
  /// The customer's market, or `nil`.
  public let market: PricingMarket?
  /// Each subscription's prices.
  public let subscriptions: [SubscriptionPrice]
}

/// A customer's pricing: the plans on sale to them, and what they pay now. Read the sheet's fields
/// straight from it, such as `pricing.plans`.
@dynamicMemberLookup
public struct CustomerPricing: Hashable, Sendable, StaleMarking {
  /// The plans on sale to the customer.
  public let sheet: PricingSheet
  /// What the customer pays for each subscription, or `nil` when Entitler has no prices for them.
  public let prices: CustomerPrices?
  /// True only when the SDK answered from a kept copy because Entitler was unreachable.
  public internal(set) var stale = false

  /// Reads a field of ``sheet``.
  public subscript<Value>(dynamicMember field: KeyPath<PricingSheet, Value>) -> Value {
    sheet[keyPath: field]
  }
}

extension Customer {
  /// Reads the plans on sale to the customer, and what they pay now.
  ///
  /// - Parameters:
  ///   - locale: The locale to format amounts' `display` for, sent as `Accept-Language`.
  ///   - revalidate: Asks Entitler whether a kept answer still stands before using it.
  ///   - timeout: How long each attempt may take, in seconds, instead of the client's timeout.
  public func pricing(
    locale: Locale? = nil, revalidate: Bool = false, timeout: TimeInterval? = nil
  ) async throws -> CustomerPricing {
    try await readPricing(
      core, Wire.pricingGetCustomerPricing.request(["external_id": id]), locale, revalidate,
      timeout, decodeCustomerPricing)
  }
}

func pricing(
  _ core: Core, market: String?, country: String?, locale: Locale?, revalidate: Bool,
  timeout: TimeInterval?
) async throws -> PricingSheet {
  let query = [("market", market), ("country", country)].compactMap { name, value in
    value.map { (name: name, value: $0) }
  }
  return try await readPricing(
    core, Wire.pricingGetPricing.request([:], query: query), locale, revalidate, timeout,
    decodePricing)
}

private func readPricing<Answer: Sendable & StaleMarking>(
  _ core: Core, _ request: Request, _ locale: Locale?, _ revalidate: Bool,
  _ timeout: TimeInterval?, _ decode: @escaping @Sendable (Data) throws -> Answer
) async throws -> Answer {
  var request = request
  if let locale { request.headers["Accept-Language"] = try languageTag(locale) }
  request.revalidate = revalidate
  request.timeout = timeout
  return try await core.cachedCall(request, decode: decode)
}

func languageTag(_ locale: Locale) throws -> String {
  let tag = String(locale.identifier.prefix { $0 != "@" }).replacingOccurrences(of: "_", with: "-")
  let subtags = tag.split(separator: "-", omittingEmptySubsequences: false)
  guard let language = subtags.first, (2...8).contains(language.count),
    language.allSatisfy({ $0.isASCII && $0.isLetter }),
    subtags.dropFirst().allSatisfy({
      (1...8).contains($0.count) && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }),
    subtags.count == 1 || subtags.last?.count != 1
  else { throw ArgumentError(message: Messages.locale) }
  return tag
}

func amount(_ value: Wire.Amount) -> Amount {
  Amount(amount: value.amount, currency: value.currency, display: value.display)
}

private func pricingMarket(_ value: Wire.PricingMarket) -> PricingMarket {
  PricingMarket(
    id: value.id, key: value.key, name: value.name, currency: value.currency,
    tax: openName(value.tax, prefix: "MARKET_TAX_"))
}

private func feeSchedule(_ value: Wire.FeeSchedule) -> FeeSchedule? {
  if value.onPurchase != nil { return .onPurchase }
  if let every = value.everyMonths {
    return .everyMonths(months: every.months, firstAfterMonths: every.firstAfterMonths)
  }
  if let yearly = value.yearlyOn {
    return .yearly(dates: yearly.dates.map { YearlyDate(month: $0.month, day: $0.day) })
  }
  return nil
}

private func listingIDs(_ value: Wire.ListingIds?) -> [String: String] {
  var ids: [String: String] = [:]
  if let apple = value?.apple {
    ids["productId"] = apple.productId
    ids["subscriptionGroupId"] = apple.subscriptionGroupId
  }
  if let google = value?.google {
    ids["productId"] = google.productId
    ids["basePlanId"] = google.basePlanId
    ids["offerId"] = google.offerId
    ids["purchaseOptionId"] = google.purchaseOptionId
  }
  if let stripe = value?.stripe { ids["priceId"] = stripe.priceId }
  return ids
}

private func channel(_ value: Wire.PricedChannel) -> PricedChannel {
  PricedChannel(
    provider: openName(value.provider, prefix: "PAYMENT_PROVIDER_"),
    connectionID: value.connectionId, name: value.name,
    mode: openName(value.mode, prefix: "CONNECTION_MODE_"), purchasable: value.purchasable,
    ids: listingIDs(value.ids),
    price: value.price.map(listingPrice))
}

func listingPrice(_ value: Wire.ListingPrice) -> ListingPrice {
  ListingPrice(
    amount: value.amount, currency: value.currency,
    interval: openName(value.interval, prefix: "LISTING_PRICE_INTERVAL_"),
    intervalCount: value.intervalCount, tax: openName(value.tax, prefix: "LISTING_TAX_BEHAVIOUR_"))
}

private func pricedPlan(_ value: Wire.PricedPlan) throws -> PricedPlan {
  PricedPlan(
    id: value.id, key: value.key, name: value.name, description: value.description,
    kind: openName(value.kind, prefix: "PLAN_KIND_"), product: value.productId,
    version: value.versionNumber, byDefault: value.byDefault,
    status: openName(value.status, prefix: "PLAN_STATUS_"), salesLed: value.salesLed,
    priceState: openName(value.priceState, prefix: "PLAN_PRICE_STATE_"),
    trial: value.trial.map { Trial(days: $0.days ?? 0, months: $0.months ?? 0) },
    quantity: value.quantity.map { QuantityRule(min: $0.min, max: $0.max) },
    periods: value.periods.map {
      PricedPeriod(
        id: $0.id, key: $0.key, label: $0.label, count: $0.count,
        unit: openName($0.unit, prefix: "PERIOD_UNIT_"))
    },
    prices: value.prices.map { price in
      PeriodPrice(
        period: price.periodId, price: price.price.map(amount),
        bands: price.bands.map {
          PricedBand(upTo: $0.upTo, perUnit: $0.perUnit, amount: $0.amount.map(amount))
        })
    },
    fees: value.fees.map {
      PricedFee(
        key: $0.key, name: $0.name, direction: openName($0.direction, prefix: "FEE_DIRECTION_"),
        price: $0.price.map(amount), schedule: $0.schedule.flatMap(feeSchedule))
    },
    items: try value.items.map {
      PlanItem(
        feature: $0.featureKey, value: try featureValue($0.value, entitled: true),
        markets: markets($0.value), bank: $0.bank.map(limit),
        benefitThousandths: $0.benefitThousandths)
    },
    availableOn: value.availableOn,
    listings: value.listings.map {
      PlanListing(period: $0.periodId, channels: $0.channels.map(channel))
    })
}

private func pricingSheet(_ value: Wire.PricingSheet) throws -> PricingSheet {
  PricingSheet(
    market: value.market.map(pricingMarket),
    products: value.products.map {
      PricedProduct(id: $0.id, key: $0.key, name: $0.name, defaultPlanID: $0.defaultPlanId)
    },
    plans: try at("plans") { try value.plans.map(pricedPlan) },
    served: try at("served") { try served(value.served) }, testers: value.testers,
    customer: value.customer)
}

private func priceLine(_ value: Wire.CustomerPriceLine) -> PriceLine {
  PriceLine(
    planID: value.planId, version: value.version, period: value.periodId,
    quantity: value.quantity, state: openName(value.state, prefix: "PLAN_PRICE_STATE_"),
    price: value.price.map(amount), unitPrice: value.unitPrice.map(amount),
    listPrice: value.listPrice.map(amount),
    discounts: value.discounts.map {
      LineDiscount(
        offerID: $0.offerId, offerKey: $0.offerKey, offerName: $0.offerName,
        amount: $0.amount.map(amount))
    })
}

private func subscriptionPrice(_ value: Wire.SubscriptionPrice) -> SubscriptionPrice {
  SubscriptionPrice(
    subscriptionID: value.subscriptionId, product: value.productId,
    renewsAt: date(value.renewsAt), now: value.now.map(priceLine),
    atRenewal: value.atRenewal.map { $0.lines.map(priceLine) },
    nextCharges: value.nextCharges.map {
      NextCharge(
        fee: $0.feeKey, direction: openName($0.direction, prefix: "FEE_DIRECTION_"),
        at: date($0.at), amount: $0.amount.map(amount))
    })
}

func decodePricing(_ body: Data) throws -> PricingSheet {
  let answer = try wire(Wire.GetPricingResponse.self, body)
  return try at("pricing") { try pricingSheet(given(answer.pricing)) }
}

func decodeCustomerPricing(_ body: Data) throws -> CustomerPricing {
  let answer = try wire(Wire.GetCustomerPricingResponse.self, body)
  return CustomerPricing(
    sheet: try at("pricing") { try pricingSheet(given(answer.pricing)) },
    prices: answer.prices.map {
      CustomerPrices(
        market: $0.market.map(pricingMarket),
        subscriptions: $0.subscriptions.map(subscriptionPrice))
    })
}
