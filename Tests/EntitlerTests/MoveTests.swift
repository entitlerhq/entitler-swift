import Foundation
import Testing

@testable import Entitler

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

let doneMove = #"""
  {"done": {"customerId": "cu_1", "revision": 12, "money": "CUSTOMER_MONEY_REAL",
    "change": {"productId": "pr_1", "plan": {"planId": "pl_2", "planKey": "team",
      "planName": "Team", "versionNumber": 4, "byDefault": false, "money": "CUSTOMER_MONEY_REAL",
      "periodId": "pe_1"}, "effective": "EFFECTIVE_NOW", "at": 1790000000, "changed": true,
      "policy": "SUBSCRIPTION_MOVE_POLICY_UPGRADE"}}}
  """#

@Suite struct MoveTests {
  @Test func subscribeSendsThePlanAndNeverRetries() async throws {
    let api = FakeAPI([Answer(status: 503, body: refusal("Unavailable", nil))])
    let customer = try api.server(options: EntitlerOptions(maxRetries: 2)).customer("ada")
    await #expect(throws: EntitlerError.self) {
      try await customer.subscribe(
        to: "team", period: "pe_1", quantity: 3, offer: .code("LAUNCH"), country: "AU",
        returnURL: URL(string: "https://example.com/back"))
    }

    let request = try #require(api.requests.first)
    #expect(api.requests.count == 1)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/v1/customers/ada/subscription")
    let sent = body(request)
    #expect(sent["plan"] as? [String: String] == ["planKey": "team"])
    #expect(sent["periodId"] as? String == "pe_1")
    #expect(sent["quantity"] as? Int == 3)
    #expect(sent["offer"] as? [String: String] == ["code": "LAUNCH"])
    #expect(sent["country"] as? String == "AU")
    #expect(sent["returnUrl"] as? String == "https://example.com/back")
    #expect(sent["register"] == nil)
  }

  @Test func aMoveAnswersDonePayOrConfirming() async throws {
    let api = FakeAPI([
      Answer(body: doneMove),
      Answer(
        body:
          #"{"pay": {"url": "https://pay.example.com/c/1", "status": "PAYMENT_STEP_STATUS_CHECKOUT"}}"#
      ),
      Answer(body: #"{"confirming": {}}"#),
    ])
    let me = try client(api, Tokens([.success("ctk_1")])).me
    let done = try await me.subscribe(to: "team")
    let pay = try await me.subscribe(to: "team")
    let confirming = try await me.subscribe(to: "team")

    guard case .done(let result) = done else {
      Issue.record("Expected a done move.")
      return
    }
    #expect(result.customerID == "cu_1")
    #expect(result.revision == 12)
    #expect(result.money.rawValue == "real")
    #expect(result.change?.plan?.key == "team")
    #expect(result.change?.effective.rawValue == "now")
    #expect(result.change?.policy.rawValue == "upgrade")
    let checkout = try #require(URL(string: "https://pay.example.com/c/1"))
    #expect(pay == .pay(url: checkout, status: OpenName(rawValue: "checkout")))
    #expect(confirming == .confirming)
    #expect(api.requests.first?.url?.path == "/v1/customers/me/subscription")
  }

  @Test func cancelAndUndoRetryOnlyWithoutARevision() async throws {
    let unavailable = Answer(status: 503, body: refusal("Unavailable", nil))
    let api = FakeAPI([unavailable, Answer(body: doneMove), unavailable, Answer(body: doneMove)])
    let customer = try api.server(options: EntitlerOptions(maxRetries: 2)).customer("ada")
    _ = try await customer.cancel(
      product: "pr_1", endsAt: Date(timeIntervalSince1970: 1_792_000_000.7))
    await #expect(throws: EntitlerError.self) {
      try await customer.undoPendingChange(product: "pr_1", expectedRevision: 12)
    }
    _ = try await customer.undoPendingChange()

    #expect(api.requests.count == 4)
    #expect(api.requests[0].url?.path == "/v1/customers/ada/subscription:cancel")
    #expect(body(api.requests[0])["endsAt"] as? Int == 1_792_000_000)
    #expect(body(api.requests[0])["productId"] as? String == "pr_1")
    #expect(api.requests[2].url?.path == "/v1/customers/ada/subscription:cancelPendingChange")
    #expect(body(api.requests[2])["expectedRevision"] as? [String: Int] == ["value": 12])
  }

  @Test func setPlanSendsTheCompanysChoices() async throws {
    let api = FakeAPI([Answer(body: doneMove), Answer(body: doneMove)])
    let customer = try api.server().customer("ada")
    _ = try await customer.setPlan(
      "enterprise", period: "pe_2", when: .periodEnd,
      offers: [OfferChoice(key: "launch"), OfferChoice(key: "loyal", percentThousandths: 12_500)],
      market: "au", keepBilling: true, reason: "Order 118")
    _ = try await customer.endPlan(in: "pr_1", when: .now, waiveExitCharges: true)

    #expect(api.requests[0].httpMethod == "PUT")
    #expect(api.requests[0].url?.path == "/v1/customers/ada/plan")
    let sent = body(api.requests[0])
    #expect(sent["set"] as? [String: String] == ["planKey": "enterprise"])
    #expect(sent["when"] as? String == "SUBSCRIPTION_MOVE_WHEN_PERIOD_END")
    #expect(sent["market"] as? String == "au")
    #expect(sent["keepBilling"] as? Bool == true)
    #expect(sent["endBilling"] == nil)
    #expect(sent["reason"] as? String == "Order 118")
    let offers = try #require(sent["offers"] as? [[String: Any]])
    #expect(offers[0]["offerKey"] as? String == "launch")
    #expect(offers[0]["value"] == nil)
    #expect(offers[1]["value"] as? [String: Int] == ["percentThousandths": 12_500])
    let ended = body(api.requests[1])
    #expect(ended["end"] as? [String: String] == ["productId": "pr_1"])
    #expect(ended["when"] as? String == "SUBSCRIPTION_MOVE_WHEN_NOW")
    #expect(ended["waiveExitCharges"] as? Bool == true)
  }

  @Test func addOnMovesNameTheAddOnByKey() async throws {
    let api = FakeAPI([Answer(body: doneMove), Answer(body: doneMove), Answer(body: doneMove)])
    let customer = try api.server().customer("ada")
    _ = try await customer.setAddOn("extra_seats", quantity: 5, replaces: "seats_pack")
    _ = try await customer.removeAddOn("extra_seats", reason: "Downsized")
    _ = try await customer.undoAddOnChange("extra_seats")

    #expect(
      api.requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" } == [
        "PUT /v1/customers/ada/add-ons/extra_seats",
        "POST /v1/customers/ada/add-ons/extra_seats:remove",
        "POST /v1/customers/ada/add-ons/extra_seats:cancelPendingChange",
      ])
    #expect(body(api.requests[0])["quantity"] as? Int == 5)
    #expect(body(api.requests[0])["replaces"] as? [String: String] == ["planKey": "seats_pack"])
    #expect(body(api.requests[1])["reason"] as? String == "Downsized")
  }

  @Test func aMoveOutOfRangeIsRefusedBeforeAnyRequest() async throws {
    let api = FakeAPI([])
    let customer = try api.server().customer("ada")
    await #expect(throws: ArgumentError.self) {
      try await customer.subscribe(to: "team", market: "au", country: "AU")
    }
    await #expect(throws: ArgumentError.self) { try await customer.subscribe(to: " ") }
    await #expect(throws: ArgumentError.self) {
      try await customer.setAddOn("extra_seats", quantity: 0)
    }
    await #expect(throws: ArgumentError.self) {
      try await customer.setPlan(
        "team", offers: [OfferChoice(key: "x", percentThousandths: 100_001)])
    }
    #expect(api.requests.isEmpty)
  }
}
