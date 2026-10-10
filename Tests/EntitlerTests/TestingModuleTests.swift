import EntitlerTesting
import Foundation
import Testing

@testable import Entitler

@Suite struct FakeCustomerTests {
  static let credits = Feature<Metered>("ai_credits")

  @Test func readsAnswerFromTheValues() async throws {
    let fake = FakeCustomer(
      ["export_pdf": true, "sso": false, "seats": 5, "ai_credits": .metered(value: 100, used: 97)],
      id: "user_9")
    let customer = fake.customer
    #expect(customer.id == "user_9")
    let export = try await customer.check("export_pdf")
    #expect(export.entitled)
    #expect(export.value == .on)
    #expect(export.customer == "user_9")
    #expect(!(try await customer.check("sso")).entitled)
    #expect(try await customer.check("seats").value == .amount(5))
    let credits = try await customer.check(Self.credits)
    #expect(credits.remaining == .amount(3))
    #expect(credits.used == 97)
    #expect(await customer.isEntitled(to: "missing", default: true))
    do {
      _ = try await customer.check("missing")
      Issue.record("Expected an error")
    } catch EntitlerError.api(let error) {
      #expect(error.status == 404)
      #expect(error.code == .featureNotFound)
    }
    let entitlements = try await customer.entitlements()
    #expect(entitlements.has("export_pdf"))
    #expect(!entitlements.has("sso"))
    #expect(entitlements["ai_credits"]?.remaining == .amount(3))
    #expect(fake.writes.isEmpty)
  }

  @Test func usageWritesMoveTheMetersByEntitlersRules() async throws {
    let fake = FakeCustomer(["ai_credits": .metered(value: 100, used: 90), "sso": true])
    let customer = fake.customer
    let refused = try await customer.recordUsage(of: Self.credits, amount: 20, idempotencyKey: "a")
    #expect(refused.outcome == .refused)
    #expect(refused.refusal == .overAllowance)
    let recorded = try await customer.recordUsage(of: Self.credits, amount: 5, idempotencyKey: "b")
    #expect(recorded.outcome == .recorded)
    #expect(recorded.used == 95)
    let replay = try await customer.recordUsage(of: Self.credits, amount: 5, idempotencyKey: "b")
    #expect(replay.replayed)
    #expect(replay.used == 95)
    let observed = try await customer.recordUsage(
      of: Self.credits, amount: 10, idempotencyKey: "c", mode: .observe)
    #expect(observed.overBy == 5)
    #expect(!(try await customer.check(Self.credits)).entitled)
    await #expect(throws: EntitlerError.self) {
      try await customer.recordUsage(
        of: Feature<Metered>("sso"), amount: 1, idempotencyKey: "d")
    }
    let adjusted = try await customer.adjustMeter(Self.credits, to: 10, idempotencyKey: "e")
    #expect(adjusted.outcome == .adjusted)
    #expect(adjusted.meterChange == -95)
    let cancelled = try await customer.cancelUsage(id: try #require(recorded.id))
    #expect(cancelled.outcome == .cancelled)
    #expect(cancelled.used == 5)
  }

  @Test func holdsSettleAndRelease() async throws {
    let fake = FakeCustomer(["ai_credits": .metered(value: 100, used: 0)])
    let customer = fake.customer
    let summary = try await customer.withHold(of: Self.credits, amount: 40, idempotencyKey: "job") {
      hold in
      #expect(try await customer.check(Self.credits).held == 40)
      try hold.use(25)
      return "summary"
    }
    #expect(summary == "summary")
    let after = try await customer.check(Self.credits)
    #expect(after.used == 25)
    #expect(after.held == 0)
    let hold = try await customer.startHold(of: Self.credits, amount: 10, idempotencyKey: "job-2")
    try await hold.release()
    #expect(try await customer.check(Self.credits).used == 25)
    await #expect(throws: EntitlerError.self) {
      try await customer.startHold(of: Self.credits, amount: 1_000, idempotencyKey: "job-3")
    }
    #expect(
      fake.writes.map(\.method) == [
        "holdUsage", "settleUsage", "holdUsage", "releaseUsage", "holdUsage",
      ])
    #expect(fake.writes.first?.arguments["amount"] == "40")
    #expect(fake.writes.first?.idempotencyKey == "job")
  }

  @Test func otherWritesAnswerAPlainSuccessUnlessReplaced() async throws {
    let fake = FakeCustomer([:])
    let customer = fake.customer
    guard case .done(let change) = try await customer.subscribe(to: "pro", period: "monthly") else {
      Issue.record("Expected a done step")
      return
    }
    #expect(change.plan?.key == "pro")
    #expect(change.effective == .now)
    #expect(try await customer.setPlan(to: "enterprise", billing: .end).plan?.key == "enterprise")
    #expect(try await customer.setAddOn("seats", quantity: 0).quantity == 0)
    #expect(try await customer.cancel().changed)
    #expect(try await customer.grant(Feature<OnOff>("sso"), actor: "agent").grant.actor == "agent")
    #expect(try await customer.syncBilling().changed == false)
    try await customer.erase()
    fake.answer(
      "subscribe",
      with: FakeAnswers.subscribeStep(.pay(URL(string: "https://checkout.test/1")!)))
    #expect(
      try await customer.subscribe(to: "pro") == .pay(URL(string: "https://checkout.test/1")!))
    fake.answer(
      "plans",
      with: FakeAnswers.plans(held: ["pro"], options: [.init(plan: "team", action: .contact)]))
    let plans = try await customer.plans()
    #expect(plans.held.first?.plan.key == "pro")
    #expect(plans.options.first?.action == .contact)
    #expect(
      fake.writes.map(\.method) == [
        "subscribe", "setPlan", "setAddOn", "cancel", "grant", "syncBilling", "erase", "subscribe",
      ])
    #expect(fake.writes[1].arguments["billing"] == "end")
  }

  @Test func everyBuilderDecodesWithTheRealDecoder() throws {
    let decoder = JSON.decoder()
    #expect(
      try decoder.decode(
        Check.self,
        from: FakeAnswers.check(
          feature: "sso", entitled: false, value: .amount(0),
          upgrades: [
            try decoder.decode(
              Upgrade.self,
              from: Data(
                #"{"plan":"pro","name":"Pro","move":"upgrade","action":"buy","reason":null}"#.utf8))
          ])
      ).upgrades.first?.plan == "pro")
    #expect(
      try decoder.decode(
        MeteredCheck.self,
        from: FakeAnswers.check(feature: "ai_credits", entitled: true, value: .amount(10), used: 4)
      ).remaining == .amount(6))
    #expect(
      try decoder.decode(
        Entitlements.self, from: FakeAnswers.entitlements(["a": true, "b": .unlimited])
      )
      .items.count == 2)
    #expect(
      try decoder.decode(
        CustomerPlans.self,
        from: FakeAnswers.plans(options: [.init(plan: "pro", periods: ["yearly"])])
      ).options.first?.periods.first?.key == "yearly")
    #expect(try decoder.decode(Pricing.self, from: FakeAnswers.pricing()).plans.count == 2)
    #expect(
      try decoder.decode(
        UsageResult.self,
        from: FakeAnswers.usageResult(
          feature: "ai_credits", outcome: .held, amount: 3, holdID: "h", expiresAt: Date())
      ).holdID == "h")
    for step in [
      SubscribeStep.pay(URL(string: "https://p.test")!), .confirming, .manage(billedBy: .google),
      .unknown("later"),
      .done(
        try decoder.decode(PlanChange.self, from: FakeAnswers.planChange(plan: nil, changed: false))
      ),
    ] {
      #expect(try decoder.decode(SubscribeStep.self, from: FakeAnswers.subscribeStep(step)) == step)
    }
    #expect(
      try decoder.decode(SubscribeStep.self, from: FakeAnswers.subscribeDone()) != .confirming)
    #expect(
      try decoder.decode(GrantChange.self, from: FakeAnswers.grantChange(feature: "sso")).grant
        .feature == "sso")
    #expect(
      try decoder.decode(BillingSync.self, from: FakeAnswers.billingSync(changed: true)).changed)
    #expect(
      try decoder.decode(
        ProviderPage.self, from: FakeAnswers.providerPage(url: URL(string: "https://b.test")!)
      ).provider == "stripe")
    #expect(
      try decoder.decode(RegisteredCustomer.self, from: FakeAnswers.registeredCustomer()).created)
    #expect(
      try decoder.decode(
        IssuedCustomerToken.self, from: FakeAnswers.customerToken(scopes: [.billingSelf])
      )
      .scopes == [.billingSelf])
    #expect(
      try decoder.decode(CustomerTrack.self, from: FakeAnswers.customerTrack(track: "Beta")).track
        .name
        == "Beta")
    let error =
      try JSONSerialization.jsonObject(
        with: FakeAnswers.error(code: .notSelfServe, message: "No.")) as? [String: [String: String]]
    #expect(error?["error"]?["code"] == "not_self_serve")
  }
}
