import Foundation
import Testing

@testable import Entitler

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

let pricingSheetJSON = #"""
  {"market": {"id": "mk_au", "key": "au", "name": "Australia", "currency": "aud",
      "tax": "MARKET_TAX_INCLUDED"},
    "products": [{"id": "pr_1", "key": "app", "name": "App", "defaultPlanId": "pl_0"}],
    "plans": [{"id": "pl_1", "key": "pro", "name": "Pro", "description": "For teams",
      "kind": "PLAN_KIND_PLAN", "productId": "pr_1", "versionNumber": 3, "byDefault": false,
      "status": "PLAN_STATUS_ACTIVE", "salesLed": false, "priceState": "PLAN_PRICE_STATE_PRICED",
      "trial": {"days": 14}, "quantity": {"min": 1},
      "periods": [{"id": "pe_1", "key": "monthly", "label": "Monthly", "count": 1,
        "unit": "PERIOD_UNIT_MONTHS"}],
      "prices": [{"periodId": "pe_1", "price": {"amount": 1200, "currency": "aud", "display": "A$12.00"},
        "bands": [{"upTo": 10, "perUnit": true, "amount": {"amount": 120, "currency": "aud", "display": "A$1.20"}}]}],
      "fees": [{"key": "setup", "name": "Setup", "direction": "FEE_DIRECTION_DEBIT",
        "price": {"amount": 500, "currency": "aud", "display": "A$5.00"},
        "schedule": {"everyMonths": {"months": 12, "firstAfterMonths": 1}}}],
      "items": [{"featureKey": "seats", "value": {"configuration": {"count": 5}}, "bank": {"unlimited": {}}},
        {"featureKey": "spend", "value": {"money": {"limits": [{"marketId": "mk_au", "limit": {"count": 5000}}]}},
          "benefitThousandths": 500}],
      "availableOn": [],
      "listings": [{"periodId": "pe_1", "channels": [
        {"provider": "PAYMENT_PROVIDER_APPLE", "connectionId": "co_1", "name": "App Store",
          "mode": "CONNECTION_MODE_LIVE", "purchasable": true,
          "ids": {"apple": {"productId": "com.example.pro", "subscriptionGroupId": "21"}},
          "price": {"amount": 1299, "currency": "aud", "interval": "LISTING_PRICE_INTERVAL_MONTH",
            "intervalCount": 1, "tax": "LISTING_TAX_BEHAVIOUR_INCLUSIVE"}},
        {"provider": "PAYMENT_PROVIDER_STRIPE", "connectionId": "co_2", "name": "Stripe",
          "mode": "CONNECTION_MODE_TEST", "purchasable": false,
          "ids": {"stripe": {"priceId": "price_1"}}}]}]}],
    "served": {"release": {"id": "re_1", "number": 12}}, "testers": false}
  """#

let cachedFor60 = ["Cache-Control": "private, max-age=60"]

@Suite struct PricingTests {
  @Test func pricingSendsTheMarketAndLocaleAndReadsTheSheet() async throws {
    let api = FakeAPI([Answer(body: #"{"pricing": \#(pricingSheetJSON)}"#)])
    let sheet = try await api.server().pricing(
      country: "AU", locale: Locale(identifier: "en_AU"))

    let request = try #require(api.requests.first)
    #expect(request.url?.path == "/v1/pricing")
    #expect(request.url?.query == "country=AU")
    #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en-AU")
    #expect(sheet.market?.tax.rawValue == "included")
    #expect(sheet.products.first?.defaultPlanID == "pl_0")
    #expect(sheet.served.source == .release(id: "re_1", number: 12))
    #expect(sheet.customer == nil)

    let plan = try #require(sheet.plans.first)
    #expect(plan.kind.rawValue == "plan")
    #expect(plan.status.rawValue == "active")
    #expect(plan.priceState.rawValue == "priced")
    #expect(plan.trial == Trial(days: 14, months: 0))
    #expect(plan.quantity == QuantityRule(min: 1, max: nil))
    #expect(plan.periods.first?.unit.rawValue == "months")
    #expect(plan.prices.first?.price == Amount(amount: 1200, currency: "aud", display: "A$12.00"))
    #expect(plan.prices.first?.bands.first?.upTo == 10)
    #expect(plan.fees.first?.direction.rawValue == "debit")
    #expect(plan.fees.first?.schedule == .everyMonths(months: 12, firstAfterMonths: 1))
    #expect(plan.items[0].value == .amount(5))
    #expect(plan.items[0].bank == .unlimited)
    #expect(plan.items[1].value == .amount(0))
    #expect(plan.items[1].markets == ["mk_au": .amount(5000)])
    #expect(plan.items[1].benefitThousandths == 500)

    let channels = try #require(plan.listings.first?.channels)
    #expect(channels[0].provider.rawValue == "apple")
    #expect(channels[0].ids == ["productId": "com.example.pro", "subscriptionGroupId": "21"])
    #expect(channels[0].price?.interval.rawValue == "month")
    #expect(channels[0].price?.tax.rawValue == "inclusive")
    #expect(channels[1].mode.rawValue == "test")
    #expect(channels[1].ids == ["priceId": "price_1"])
    #expect(channels[1].price == nil)
  }

  @Test func eachLocaleKeepsItsOwnSheet() async throws {
    let api = FakeAPI([
      Answer(headers: cachedFor60, body: #"{"pricing": \#(pricingSheetJSON)}"#),
      Answer(headers: cachedFor60, body: #"{"pricing": \#(pricingSheetJSON)}"#),
    ])
    let server = try api.server()
    _ = try await server.pricing(locale: Locale(identifier: "en_AU"))
    _ = try await server.pricing(locale: Locale(identifier: "fr_FR"))
    _ = try await server.pricing(locale: Locale(identifier: "en_AU"))

    #expect(
      api.requests.map { $0.value(forHTTPHeaderField: "Accept-Language") } == ["en-AU", "fr-FR"])
  }

  @Test func aLocaleThatIsNotALanguageTagIsRefusedBeforeAnyRequest() async throws {
    let api = FakeAPI([])
    let server = try api.server()
    await #expect(throws: ArgumentError.self) {
      try await server.pricing(locale: Locale(identifier: ""))
    }
    await #expect(throws: ArgumentError.self) {
      try await server.customer("ada").pricing(locale: Locale(identifier: "e"))
    }
    #expect(api.requests.isEmpty)
    #expect(throws: ArgumentError.self) { try languageTag(Locale(identifier: "en_a")) }
    #expect(throws: ArgumentError.self) { try languageTag(Locale(identifier: "en-US-x")) }
    #expect(try languageTag(Locale(identifier: "sr_Latn_RS")) == "sr-Latn-RS")
    #expect(try languageTag(Locale(identifier: "en_AU@calendar=gregorian")) == "en-AU")
  }

  @Test func aCustomersPricingCarriesWhatTheyPay() async throws {
    let api = FakeAPI([
      Answer(
        body: #"""
          {"pricing": \#(pricingSheetJSON.replacingOccurrences(of: #""testers": false"#, with: #""testers": false, "customer": "ada""#)),
            "prices": {"market": null, "subscriptions": [{"subscriptionId": "su_1", "productId": "pr_1",
              "renewsAt": 1790086400,
              "now": [{"planId": "pl_1", "version": 3, "periodId": "pe_1", "quantity": 2,
                "state": "PLAN_PRICE_STATE_PRICED",
                "price": {"amount": 2000, "currency": "aud", "display": "A$20.00"},
                "listPrice": {"amount": 2400, "currency": "aud", "display": "A$24.00"},
                "discounts": [{"offerId": "of_1", "offerKey": "launch", "offerName": "Launch",
                  "amount": {"amount": 400, "currency": "aud", "display": "A$4.00"}}]}],
              "nextCharges": [{"feeKey": "setup", "direction": "FEE_DIRECTION_CREDIT", "at": 1790086400}]}]}}
          """#)
    ])
    let pricing = try await api.server().customer("ada").pricing()

    #expect(api.requests.first?.url?.path == "/v1/customers/ada/pricing")
    #expect(api.requests.first?.value(forHTTPHeaderField: "Accept-Language") == nil)
    #expect(pricing.customer == "ada")
    #expect(pricing.plans.count == 1)
    let subscription = try #require(pricing.prices?.subscriptions.first)
    #expect(subscription.renewsAt == Date(timeIntervalSince1970: 1_790_086_400))
    #expect(subscription.atRenewal == nil)
    #expect(subscription.now.first?.quantity == 2)
    #expect(subscription.now.first?.discounts.first?.offerKey == "launch")
    #expect(subscription.now.first?.unitPrice == nil)
    #expect(subscription.nextCharges.first?.direction.rawValue == "credit")
  }

  @Test func theVisitorSignsWithItsPublishableKeyAndNeverShowsIt() async throws {
    let api = FakeAPI([Answer(body: #"{"pricing": \#(pricingSheetJSON)}"#)])
    let visitor = try EntitlerVisitor(
      key: "pk_test_secret", cache: nil, options: EntitlerOptions(maxRetries: 0),
      exchange: api.exchange, hooks: instantHooks)
    _ = try await visitor.pricing(market: "au")

    let request = try #require(api.requests.first)
    #expect(request.url?.query == "market=au")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer pk_test_secret")
    #expect(!"\(visitor)".contains("pk_test_secret"))
    #expect(!String(reflecting: visitor).contains("pk_test_secret"))
    #expect(throws: ArgumentError.self) { try EntitlerVisitor(key: " ") }
  }
}
