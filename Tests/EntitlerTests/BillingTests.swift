import Foundation
import Testing

@testable import Entitler

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

let plansJSON = #"""
  {"asOf": 1790000000, "customerId": "cu_1",
    "options": [{"planId": "pl_2", "planKey": "team", "planName": "Team", "productId": "pr_1",
      "kind": "OPTION_KIND_MOVE", "direction": "PLAN_DIRECTION_UP", "selling": "SELLING_SELF_SERVE",
      "timing": "MOVE_TIMING_NOW_KEEP", "periodIds": ["pe_1"],
      "impact": [{"featureKey": "seats", "kind": "IMPACT_KIND_CHANGES",
        "from": {"configuration": {"count": 5}}, "to": {"configuration": {"unlimited": {}}}}]}],
    "holdings": {"grants": [{"id": "gr_1", "featureKey": "sso", "value": {"on": {}},
        "from": 1789000000, "reason": ""}],
      "lanes": [{"productId": "pr_1", "plan": {"planId": "pl_1", "planKey": "pro", "planName": "Pro",
          "versionNumber": 3, "byDefault": false, "money": "CUSTOMER_MONEY_REAL", "periodId": "pe_1"},
        "addOns": [{"planId": "pl_9", "planKey": "boost", "planName": "Boost", "versionNumber": 1,
          "money": "CUSTOMER_MONEY_REAL", "quantity": 2, "required": false, "addedAt": 1789500000}],
        "renewsAt": 1790500000, "collection": "SUBSCRIPTION_COLLECTION_PROVIDER",
        "pending": {"at": 1790500000, "move": {"planId": "pl_0", "periodId": "pe_1"}},
        "discounts": [{"offerId": "of_1", "offerKey": "launch", "offerName": "Launch",
          "percentThousandths": 10000, "applied": true, "fees": [], "givenAt": 1789000000,
          "givenBy": "DISCOUNT_GIVEN_BY_CUSTOMER", "periodIds": [], "planIds": []}],
        "paymentAmount": {"amount": 2000, "currency": "aud", "display": "A$20.00"},
        "periodsAhead": 0, "scheduledChanges": []}]}}
  """#

@Suite struct BillingTests {
  @Test func plansReadTheOptionsAndHoldings() async throws {
    let api = FakeAPI([
      Answer(headers: ["Cache-Control": "private, max-age=60"], body: plansJSON)
    ])
    let me = try client(api, Tokens([.success("ctk_1")])).me
    let plans = try await me.plans()
    _ = try await me.plans()

    #expect(api.requests.count == 1)
    #expect(api.requests.first?.url?.path == "/v1/customers/me/plans")
    #expect(plans.customerID == "cu_1")
    let option = try #require(plans.options.first)
    #expect(option.plan == NamedPlan(id: "pl_2", key: "team", name: "Team"))
    #expect(option.kind.rawValue == "move")
    #expect(option.direction.rawValue == "up")
    #expect(option.selling.rawValue == "self_serve")
    #expect(option.timing.rawValue == "now_keep")
    #expect(option.impact.first?.from == .amount(5))
    #expect(option.impact.first?.to == .unlimited)
    #expect(option.impact.first?.toMarkets == nil)

    let holdings = try #require(plans.holdings)
    #expect(holdings.grants.first?.value == .on)
    let lane = try #require(holdings.lanes.first)
    #expect(lane.plan?.key == "pro")
    #expect(lane.addOns.first?.quantity == 2)
    #expect(lane.collection.rawValue == "provider")
    #expect(
      lane.pending
        == PendingChange(
          at: Date(timeIntervalSince1970: 1_790_500_000), cancel: false, plan: "pl_0",
          period: "pe_1"))
    #expect(lane.discounts.first?.percentThousandths == 10_000)
    #expect(lane.payment.amount?.display == "A$20.00")
    #expect(lane.cancellation == nil)
  }

  @Test func billingAnswersTheProvidersStateOrUnlinked() async throws {
    let api = FakeAPI([
      Answer(
        body: #"""
          {"billing": {"linked": true, "connectionId": "co_1",
            "status": "PROVIDER_SUBSCRIPTION_STATUS_PAST_DUE", "items": 1, "renews": true,
            "sku": {"priceId": "price_1", "periodId": "pe_1"},
            "drift": {"billedPlanId": "pl_1", "heldPlanId": "pl_2", "observedAt": 1790000000},
            "products": [{"productId": "pr_1", "connectionId": "co_1",
              "status": "PROVIDER_SUBSCRIPTION_STATUS_ACTIVE", "items": 1, "renews": true}]}}
          """#),
      Answer(body: "{}"),
    ])
    let customer = try api.server().customer("ada")
    let linked = try await customer.billing()
    let unlinked = try await customer.billing()

    #expect(api.requests.first?.url?.path == "/v1/customers/ada/billing")
    #expect(linked.status.rawValue == "past_due")
    #expect(linked.sku?.priceID == "price_1")
    #expect(linked.drift?.heldPlan == "pl_2")
    #expect(linked.products.first?.status.rawValue == "active")
    #expect(!unlinked.linked)
    #expect(unlinked.status.rawValue == "unspecified")
    #expect(unlinked.products.isEmpty)
  }

  @Test func thePortalAndASyncWriteForTheCustomer() async throws {
    let api = FakeAPI([
      Answer(body: #"{"url": "https://billing.example.com/p/1"}"#),
      Answer(status: 503, body: refusal("Unavailable", nil)),
      Answer(body: #"{"changed": true}"#),
    ])
    let customer = try api.server(options: EntitlerOptions(maxRetries: 1)).customer("ada")
    let portal = try await customer.billingPortal(
      returnURL: try #require(URL(string: "https://example.com/account")))
    let changed = try await customer.syncBilling()

    #expect(portal == URL(string: "https://billing.example.com/p/1"))
    #expect(api.requests[0].url?.path == "/v1/customers/ada/billing/portal-sessions")
    #expect(body(api.requests[0])["returnUrl"] as? String == "https://example.com/account")
    #expect(api.requests[1].url?.path == "/v1/customers/ada/billing:sync")
    #expect(api.requests.count == 3)
    #expect(changed)
  }
}
