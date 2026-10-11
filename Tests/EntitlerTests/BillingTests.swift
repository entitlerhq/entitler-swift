import Foundation
import Testing

@testable import Entitler

@Suite struct BillingTests {
  static let returnURL = URL(string: "https://app.test/billing/return")!

  @Test func subscribeSendsTheChoiceAndAnswersEachStep() async throws {
    let steps = [
      Fixture.planChange(next: "done"),
      #"{"next":"pay","url":"https://checkout.stripe.test/c/1"}"#,
      #"{"next":"confirming"}"#,
      #"{"next":"manage","billedBy":"apple"}"#,
      #"{"next":"later","anything":1}"#,
    ]
    let index = Box(0)
    let api = FakeAPI { _ in
      let step = index.with { value in
        defer { value += 1 }
        return steps[value]
      }
      return .json(step, headers: step.contains("done") ? ["Idempotent-Replayed": "true"] : [:])
    }
    let customer = try api.server().customer("u")
    try await api.run {
      let done = try await customer.subscribe(
        to: "pro", period: "monthly", returnURL: Self.returnURL, register: true,
        idempotencyKey: "choice-1")
      guard case .done(let change) = done else {
        Issue.record("Expected a done step")
        return
      }
      #expect(change.effective == .renewal)
      #expect(change.plan?.key == "pro")
      #expect(change.product?.key == "app")
      #expect(change.changed)
      #expect(change.replayed)
      #expect(done.replayed)
      #expect(api.last.path == "/customers/u/subscription")
      #expect(api.last.method == "POST")
      #expect(api.last.header("Idempotency-Key") == "choice-1")
      let json = try #require(api.last.json)
      #expect(json.keys.sorted() == ["period", "plan", "register", "returnUrl"])
      #expect(json["returnUrl"] as? String == "https://app.test/billing/return")
      #expect(
        try await customer.subscribe(to: "pro")
          == .pay(URL(string: "https://checkout.stripe.test/c/1")!))
      #expect(api.last.json?.keys.sorted() == ["plan"])
      #expect(try await customer.subscribe(to: "sso_addon", quantity: 2) == .confirming)
      #expect(api.last.json?["quantity"] as? Int == 2)
      #expect(try await customer.subscribe(to: "pro") == .manage(billedBy: .apple))
      let unknown = try await customer.subscribe(to: "pro")
      #expect(unknown == .unknown("later"))
      #expect(!unknown.replayed)
      await #expect(throws: ArgumentError(message: "Name the plan by its id or its key.")) {
        try await customer.subscribe(to: " ")
      }
    }
  }

  @Test func aDeclinedPaymentStaysAnError() async throws {
    let api = FakeAPI { _ in
      .json(
        #"{"error":{"code":"payment_required","message":"Declined.","payment":{"status":"declined","url":null}}}"#,
        status: 402)
    }
    do {
      _ = try await api.run { try await api.server().customer("u").subscribe(to: "pro") }
      Issue.record("Expected an error")
    } catch EntitlerError.api(let error) {
      #expect(error.code == .paymentRequired)
      #expect(error.payment?.status == .declined)
      #expect(error.payment?.url == nil)
    }
  }

  @Test func cancelAndUndoTakeAPlanOrAnAddOn() async throws {
    let api = FakeAPI { _ in .json(Fixture.planChange(changed: false)) }
    let customer = try api.server().customer("u")
    try await api.run {
      let change = try await customer.cancel()
      #expect(!change.changed)
      #expect(api.last.method == "DELETE")
      #expect(api.last.path == "/customers/u/subscription")
      #expect(api.last.query == nil)
      try await customer.cancel(product: "app")
      #expect(api.last.query == "product=app")
      try await customer.cancel(addOn: "sso_addon")
      #expect(api.last.path == "/customers/u/subscription/add-ons/sso_addon")
      try await customer.undoPendingChange()
      #expect(api.last.path == "/customers/u/subscription/pending")
      try await customer.undoPendingChange(product: "app")
      #expect(api.last.query == "product=app")
      try await customer.undoPendingChange(addOn: "sso_addon")
      #expect(api.last.path == "/customers/u/subscription/add-ons/sso_addon/pending")
    }
    let count = api.count
    for call in [
      { try await customer.cancel(addOn: "a", product: "p") },
      { try await customer.undoPendingChange(addOn: "a", product: "p") },
    ] as [@Sendable () async throws -> PlanChange] {
      await #expect(throws: ArgumentError(message: "Pass either addOn or product, not both.")) {
        try await call()
      }
    }
    await #expect(throws: ArgumentError(message: "Name the plan by its id or its key.")) {
      try await customer.cancel(addOn: " ")
    }
    await #expect(throws: ArgumentError(message: "Name the plan by its id or its key.")) {
      try await customer.undoPendingChange(addOn: "")
    }
    #expect(api.count == count)
  }

  @Test func billingPortalAndSync() async throws {
    let api = FakeAPI { request in
      request.path.hasSuffix("sync")
        ? .json(#"{"changed":true}"#)
        : .json(#"{"provider":"stripe","url":"https://billing.stripe.test/p/1"}"#)
    }
    let customer = try api.server().customer("u")
    try await api.run {
      let page = try await customer.billingPortal(returnURL: Self.returnURL)
      #expect(page.url.absoluteString == "https://billing.stripe.test/p/1")
      #expect(api.last.path == "/customers/u/billing-portal")
      #expect(api.last.json?["returnUrl"] as? String == "https://app.test/billing/return")
      #expect(api.last.header("Idempotency-Key")?.count == 36)
      let sync = try await customer.syncBilling()
      #expect(sync.changed)
      #expect(api.last.method == "POST")
      #expect(api.last.path == "/customers/u/billing/sync")
      #expect(api.last.body == nil || api.last.body?.isEmpty == true)
      #expect(api.last.header("Content-Type") == nil)
    }
  }

  @Test func theSignedInCustomerMakesItsOwnChoices() async throws {
    let api = FakeAPI { _ in .json(#"{"next":"pay","url":"https://checkout.stripe.test/c/2"}"#) }
    let client = try EntitlerClient(token: "tok", options: api.options())
    let step = try await api.run {
      try await client.me.subscribe(to: "pro", period: "yearly", returnURL: Self.returnURL)
    }
    #expect(step == .pay(URL(string: "https://checkout.stripe.test/c/2")!))
    #expect(api.last.path == "/customers/me/subscription")
    #expect(api.last.header("Authorization") == "Bearer tok")
  }
}

@Suite struct CompanyDecisionTests {
  @Test func setPlanSendsTheCompanysChoice() async throws {
    let api = FakeAPI { _ in .json(Fixture.planChange()) }
    let customer = try api.server().customer("u")
    try await api.run {
      let change = try await customer.setPlan(
        to: "enterprise", period: "yearly", when: .end, billing: .end,
        until: Date(timeIntervalSince1970: 1_782_898_200), register: true, reason: "Deal won",
        actor: "hubspot", idempotencyKey: "deal-7-won")
      #expect(change.effective == .renewal)
      #expect(api.last.method == "PUT")
      #expect(api.last.path == "/customers/u/plan")
      #expect(api.last.header("Idempotency-Key") == "deal-7-won")
      let json = try #require(api.last.json)
      #expect(
        json.keys.sorted() == [
          "actor", "billing", "period", "plan", "reason", "register", "until", "when",
        ])
      #expect(json["billing"] as? String == "end")
      #expect(json["until"] as? String == "2026-07-01T09:30:00.000Z")
      try await customer.setPlan(
        to: .sku(SKU(connector: "apple", ids: ["productId": "pro_yearly"])), billing: .keep)
      let sku = try #require(api.last.json?["sku"] as? [String: Any])
      #expect(sku["connector"] as? String == "apple")
      #expect(api.last.json?["plan"] == nil)
      #expect(api.last.json?["billing"] as? String == "keep")
      try await customer.setPlan(to: "pro", billing: .provider)
      #expect(api.last.json?.keys.sorted() == ["billing", "plan"])
      await #expect(throws: ArgumentError(message: "Name the plan by its id or its key.")) {
        try await customer.setPlan(to: "")
      }
    }
  }

  @Test func setAddOnSetsAQuantity() async throws {
    let api = FakeAPI { _ in .json(Fixture.planChange()) }
    let customer = try api.server().customer("u")
    try await api.run {
      try await customer.setAddOn("extra_seats", quantity: 150, actor: "agent-1")
      #expect(api.last.method == "PUT")
      #expect(api.last.path == "/customers/u/add-ons/extra_seats")
      #expect(api.last.json?.keys.sorted() == ["actor", "quantity"])
      try await customer.setAddOn("extra_seats", quantity: 0, when: .now)
      #expect(api.last.json?["quantity"] as? Int == 0)
      #expect(api.last.json?["when"] as? String == "now")
    }
  }

  @Test func grantsAnswerTheGrant() async throws {
    let api = FakeAPI { _ in
      .json(
        #"{"grant":{"id":"g_1","feature":"sso","value":"","from":"2026-10-01T00:00:00Z","until":null,"revokedAt":null,"reason":"Ticket 42","by":"Support key","actor":"agent-1"}}"#,
        status: 201)
    }
    let customer = try api.server().customer("u")
    try await api.run {
      let change = try await customer.grant(
        Feature<OnOff>("sso"), days: 30, reason: "Ticket 42", actor: "agent-1")
      #expect(change.grant.id == "g_1")
      #expect(change.grant.actor == "agent-1")
      #expect(change.grant.value == .on)
      #expect(!change.replayed)
      #expect(api.last.json?.keys.sorted() == ["actor", "days", "feature", "reason"])
      try await customer.grant("seats", value: .amount(5))
      #expect(api.last.json?["value"] as? String == "5")
      try await customer.grant("credits", value: .unlimited)
      #expect(api.last.json?["value"] as? String == "unlimited")
      try await customer.revokeGrant(id: "g_1")
      #expect(api.last.method == "DELETE")
      #expect(api.last.path == "/customers/u/grants/g_1")
      #expect(api.last.body == nil || api.last.body?.isEmpty == true)
      try await customer.revokeGrant(id: "g_1", reason: "Mistake")
      #expect(api.last.json?.keys.sorted() == ["reason"])
      await #expect(throws: ArgumentError(message: "Provide the id of the grant.")) {
        try await customer.revokeGrant(id: "")
      }
    }
  }

  @Test func adjustMeterTakesByOrTo() async throws {
    let api = FakeAPI { _ in .json(Fixture.usage(outcome: "adjusted")) }
    let customer = try api.server().customer("u")
    let credits = Feature<Metered>("ai_credits")
    try await api.run {
      let result = try await customer.adjustMeter(
        credits, by: -500, idempotencyKey: "ticket-9", reason: "Refund", actor: "agent-1")
      #expect(result.outcome == .adjusted)
      #expect(api.last.method == "POST")
      #expect(api.last.path == "/customers/u/meters/ai_credits/adjustments")
      #expect(api.last.header("Idempotency-Key") == "ticket-9")
      #expect(api.last.json?["by"] as? Int == -500)
      #expect(api.last.json?.keys.sorted() == ["actor", "by", "reason"])
      try await customer.adjustMeter(credits, to: 0, idempotencyKey: "ticket-10")
      #expect(api.last.json?.keys.sorted() == ["to"])
      #expect(api.last.json?["to"] as? Int == 0)
    }
    let count = api.count
    let message = ArgumentError(
      message: "Pass either by, a whole number other than 0, or to, a whole number of 0 or more.")
    await #expect(throws: message) {
      try await customer.adjustMeter(credits, by: 0, idempotencyKey: "k")
    }
    await #expect(throws: message) {
      try await customer.adjustMeter(credits, by: Int64.min, idempotencyKey: "k")
    }
    await #expect(throws: message) {
      try await customer.adjustMeter(credits, to: -1, idempotencyKey: "k")
    }
    #expect(api.count == count)
  }

  @Test func cancelUsageIsACorrection() async throws {
    let api = FakeAPI { _ in .json(Fixture.usage(outcome: "cancelled")) }
    let customer = try api.server().customer("u")
    try await api.run {
      let result = try await customer.cancelUsage(id: "u_1", actor: "agent-1")
      #expect(result.outcome == .cancelled)
      #expect(api.last.method == "DELETE")
      #expect(api.last.path == "/customers/u/usage/u_1")
      #expect(api.last.json?.keys.sorted() == ["actor"])
      await #expect(throws: ArgumentError(message: "Provide the id of the usage report.")) {
        try await customer.cancelUsage(id: "")
      }
    }
  }
}

@Suite struct ServerCustomerTests {
  @Test func registerSendsOnlyDetailsGivenAndTheVisitor() async throws {
    let api = FakeAPI { _ in
      .json(
        #"{"id":"c","externalId":"u","environmentId":"e","createdAt":"2026-10-09T01:47:13Z","created":false}"#
      )
    }
    let customer = try api.server().customer("u")
    try await api.run {
      try await customer.register()
      #expect(api.last.method == "PUT")
      #expect(api.last.body == nil || api.last.body?.isEmpty == true)
      #expect(api.last.header("Content-Type") == nil)
      #expect(api.last.header("Idempotency-Key") != nil)
      try await customer.register(
        name: "Ada", metadata: ["team": "a"], visitor: "abcdefghijklmnopq")
      #expect(api.last.json?.keys.sorted() == ["metadata", "name"])
      #expect(api.last.header("Entitler-Visitor") == "abcdefghijklmnopq")
    }
  }

  @Test func detailsUpdateEraseTokenAndTrack() async throws {
    let api = FakeAPI { request in
      switch (request.method, request.path) {
      case ("GET", _): .json(Fixture.detail)
      case ("POST", _):
        .json(
          #"{"token":"tok","customer":"u","scopes":["entitlements:read","billing:self","future:scope"],"expiresAt":"2026-10-09T02:47:13Z"}"#
        )
      case ("PUT", _):
        .json(
          #"{"customer":"u","track":{"id":"t2","name":"Beta"},"source":"server","previousTrackId":"t1"}"#
        )
      case ("DELETE", _): Reply(status: 204)
      default: .json(Fixture.summary)
      }
    }
    let customer = try api.server().customer("u")
    try await api.run {
      let detail = try await customer.details(cursor: "c1")
      #expect(api.last.query == "cursor=c1")
      if case .cancel(let plan)? = detail.subscription?.pending {
        #expect(plan?.key == "free")
      } else {
        Issue.record("Expected a booked cancel")
      }
      #expect(detail.subscription?.period?.key == "monthly")
      #expect(detail.subscription?.purchase.channel?.provider == .stripe)
      #expect(detail.banked["ai_credits"] == 5)
      #expect(detail.customer.metadata["team"] == "a")
      let updated = try await customer.update(
        email: "new@example.com", metadata: ["team": nil, "role": "admin"])
      #expect(updated.externalID == "user_1")
      #expect(api.last.method == "PATCH")
      let metadata = try #require(api.last.json?["metadata"] as? [String: Any])
      #expect(metadata["team"] is NSNull)
      #expect(metadata["role"] as? String == "admin")
      #expect(api.last.json?["name"] == nil)
      try await customer.erase(idempotencyKey: "delete-account-1")
      #expect(api.last.method == "DELETE")
      #expect(api.last.query == "erase=true")
      #expect(api.last.header("Idempotency-Key") == "delete-account-1")
      let token = try await customer.token(
        scopes: [.entitlementsRead, .billingSelf], ttlSeconds: 600)
      #expect(token.scopes == [.entitlementsRead, .billingSelf])
      #expect(api.last.json?["scopes"] as? [String] == ["entitlements:read", "billing:self"])
      _ = try await customer.token()
      #expect(api.last.body.map { String(decoding: $0, as: UTF8.self) } == "{}")
      let track = try await customer.setTrack("Beta")
      #expect(track.previousTrackID == "t1")
      #expect(api.last.json?["track"] as? String == "Beta")
      try await customer.setTrack(nil)
      #expect(api.last.body.map { String(decoding: $0, as: UTF8.self) } == #"{"track":null}"#)
      await #expect(throws: ArgumentError(message: "Name the track by its name.")) {
        try await customer.setTrack(" ")
      }
    }
  }

  @Test func billingDecodes() async throws {
    let api = FakeAPI { _ in
      .json(
        #"{"provider":"stripe","status":"past_due","sku":{"period":{"key":"monthly","label":"Monthly"},"connector":"stripe","ids":{"price":"p"},"price":null},"items":1,"drift":{"billedPlan":"pro","heldPlan":null,"observedAt":"2026-10-09T01:47:13Z"},"products":[{"product":"app","status":"active","sku":null,"items":1,"drift":null}]}"#
      )
    }
    let billing = try await api.run { try await api.server().customer("u").billing() }
    #expect(billing.status == .pastDue)
    #expect(billing.sku?.period?.label == "Monthly")
    #expect(billing.products?.first?.status == .active)
  }

  @Test func customersListAndCreate() async throws {
    let api = FakeAPI { request in
      if request.method == "POST" { return .json(Fixture.detail, status: 201) }
      return request.query?.contains("cursor=n2") == true
        ? .json(#"{"items":[\#(Fixture.summary)],"next":null,"used":2,"limit":"unlimited"}"#)
        : .json(#"{"items":[\#(Fixture.summary)],"next":"n2","used":2,"limit":100}"#)
    }
    let server = try api.server()
    try await api.run {
      var count = 0
      for try await customer in server.customers.list(query: "acme corp", includeTest: true) {
        #expect(customer.kind == .default)
        count += 1
      }
      #expect(count == 2)
      #expect(api.requests.get[0].query == "q=acme%20corp&includeTest=true")
      #expect(api.requests.get[1].query == "q=acme%20corp&includeTest=true&cursor=n2")
      for try await _ in server.customers.list(cohort: "pro:1", track: "t1") { break }
      #expect(api.last.query == "cohort=pro%3A1&track=t1")
      var pages = server.customers.list(cursor: "n2").pages.makeAsyncIterator()
      let page = try #require(try await pages.next())
      #expect(api.last.query == "cursor=n2")
      #expect(page.used == 2)
      #expect(page.limit == .unlimited)
      #expect(try await pages.next() == nil)
      let created = try await server.customers.create(
        id: "new_1", name: "Ada", plan: "pro", idempotencyKey: "create-1")
      #expect(created.customer.name == "Ada")
      #expect(api.last.json?["externalId"] as? String == "new_1")
      #expect(api.last.json?.keys.sorted() == ["externalId", "name", "plan"])
      #expect(api.last.header("Idempotency-Key") == "create-1")
    }
  }

  @Test func customerPlansDecode() async throws {
    let api = FakeAPI { _ in
      .json(
        #"{"customer":"u","asOf":"2026-10-09T01:47:13Z","held":[{"plan":{"id":"p2","key":"pro","name":"Pro","kind":"plan"},"product":{"key":"app","name":"App"},"version":3,"byDefault":false,"period":{"key":"monthly","label":"Monthly"},"renewsAt":"2026-11-01T00:00:00Z","pending":{"type":"move","plan":{"id":"p3","key":"pro_basic","name":"Pro basic"}},"billedBy":"stripe"},{"plan":{"id":"p","key":"free","name":"Free","kind":"plan"},"product":{"key":"other","name":"Other"},"version":1,"byDefault":true,"period":null,"renewsAt":null,"pending":{"type":"cancel","movingTo":null},"billedBy":null}],"options":[{"plan":{"id":"p4","key":"team","name":"Team","kind":"plan","description":"For teams","default":false},"product":{"key":"app","name":"App"},"from":{"id":"p2","key":"pro","name":"Pro"},"move":"upgrade","action":"contact","reason":null,"when":"now","periods":[{"key":"yearly","label":"Yearly"}],"impact":[{"kind":"gains","text":"SSO"}],"skus":[{"period":{"key":"yearly","label":"Yearly"},"connector":"apple","ids":{"productId":"team_yearly"}}]},{"plan":{"id":"p5","key":"x","name":"X","kind":"addon","description":"","default":false},"product":null,"from":null,"move":"teleport","action":"wish","reason":"Not yet.","when":"end","periods":[],"impact":[],"skus":[]}],\#(Fixture.context)}"#
      )
    }
    let plans = try await api.run { try await api.server().customer("u").plans() }
    let held = try #require(plans.held.first)
    #expect(held.period?.key == "monthly")
    #expect(held.billedBy == .stripe)
    #expect(
      held.pending
        == .move(
          to: PlanRef(
            id: "p3", key: "pro_basic", name: "Pro basic", kind: nil, version: nil, product: nil)))
    #expect(plans.held[1].pending == .cancel(movingTo: nil))
    #expect(plans.held[1].billedBy == nil)
    let option = try #require(plans.options.first)
    #expect(option.move == .upgrade)
    #expect(option.action == .contact)
    #expect(option.plan.description == "For teams")
    #expect(!option.plan.isDefault)
    #expect(option.periods.map(\.key) == ["yearly"])
    #expect(option.impact.first?.kind == .gains)
    #expect(option.skus.first?.period?.label == "Yearly")
    #expect(plans.options[1].move == .unknown("teleport"))
    #expect(plans.options[1].action == .unknown("wish"))
    #expect(plans.options[1].reason == "Not yet.")
  }

  @Test func entitlementsGetAndHas() async throws {
    let api = FakeAPI { _ in .json(Fixture.entitlements) }
    let entitlements = try await api.run { try await api.server().customer("u").entitlements() }
    #expect(entitlements.has(Feature<OnOff>("export_pdf")))
    #expect(!entitlements.has(Feature<FeatureGroup>("collaboration", includes: ["team_seats"])))
    #expect(!entitlements.has("missing"))
    #expect(entitlements[Feature<Metered>("ai_credits")]?.remaining == .unlimited)
    #expect(entitlements["collaboration"]?.sources.first?.features == ["team_seats"])
    #expect(entitlements["collaboration"]?.upgrades.first?.action == .contact)
    #expect(entitlements["collaboration"]?.upgrades.first?.move == .upgrade)
    #expect(entitlements["missing"] == nil)
    #expect(entitlements.items.count == 3)
  }
}

@Suite struct AsOfTests {
  @Test func onlyServerReadsGivenAsOfSendIt() async throws {
    let api = FakeAPI { request in
      switch request.path {
      case let path where path.hasSuffix("/usage"): .json(Fixture.usage())
      case let path where path.hasSuffix("/entitlements"): .json(Fixture.entitlements)
      default: .json(Fixture.check())
      }
    }
    let customer = try api.server().customer("u")
    let at = Date(timeIntervalSince1970: 1_782_898_200)
    try await api.run {
      _ = try await customer.check("sso", asOf: at)
      #expect(api.last.header("Entitler-As-Of") == "2026-07-01T09:30:00.000Z")
      _ = try await customer.check(Feature<OnOff>("sso"), asOf: at)
      #expect(api.last.header("Entitler-As-Of") == "2026-07-01T09:30:00.000Z")
      _ = await customer.isEntitled(to: Feature<OnOff>("sso"), default: false, asOf: at)
      _ = try await customer.entitlements(asOf: at)
      #expect(api.last.header("Entitler-As-Of") == "2026-07-01T09:30:00.000Z")
      _ = try await customer.check("sso")
      #expect(api.last.header("Entitler-As-Of") == nil)
      try await customer.recordUsage(
        of: Feature<Metered>("ai_credits"), amount: 1, idempotencyKey: "k")
      #expect(api.last.header("Entitler-As-Of") == nil)
    }
    #expect(api.count == 6)
  }

  @Test func anInvalidInstantIsRefusedBeforeAnyRequest() async throws {
    let api = FakeAPI()
    let customer = try api.server().customer("u")
    for at in [Date(timeIntervalSince1970: .nan), Date.distantFuture.addingTimeInterval(1e12)] {
      await #expect(throws: ArgumentError(message: "Pass asOf as a valid date.")) {
        try await customer.check("sso", asOf: at)
      }
      await #expect(throws: ArgumentError(message: "Pass asOf as a valid date.")) {
        try await customer.plans(asOf: at)
      }
      await #expect(throws: ArgumentError(message: "Pass asOf as a valid date.")) {
        try await customer.usage(asOf: at)
      }
      await #expect(throws: ArgumentError(message: "Pass asOf as a valid date.")) {
        try await customer.details(asOf: at)
      }
    }
    #expect(api.count == 0)
  }
}

@Suite struct ClosingTests {
  @Test func laterCallsFailBeforeAnyRequestAndClosingTwiceIsSafe() async throws {
    let api = FakeAPI { _ in .json(Fixture.check()) }
    let errors = Box<[any Error]>([])
    let server = try api.server { $0.onError = { error in errors.with { $0.append(error) } } }
    server.close()
    server.close()
    await #expect(throws: ClientClosedError()) {
      try await api.run { try await server.customer("u").check("sso") }
    }
    await #expect(throws: ClientClosedError()) {
      try await api.run { try await server.recordUsageBatch([]) }
    }
    #expect(await (try server.customer("u")).isEntitled(to: "sso", default: true))
    #expect(errors.get.first is ClientClosedError)
    #expect(ClientClosedError().description == "This Entitler client is closed. Create a new one.")
    #expect(ClientClosedError().errorDescription == ClientClosedError().message)
    #expect(api.count == 0)
  }

  @Test func closingCancelsCallsInFlight() async throws {
    let api = FakeAPI { _ in Reply.hanging }
    let client = try EntitlerClient(token: "tok", options: api.options())
    let hooks = api.hooks
    let call = Task {
      try await Hooks.$current.withValue(hooks) { try await client.me.check("sso") }
    }
    while api.count == 0 { try await Task.sleep(nanoseconds: 1_000_000) }
    client.close()
    await #expect(throws: ClientClosedError()) { try await call.value }
  }

  @Test func closingCancelsThePendingRefresh() async throws {
    let api = FakeAPI { _ in .json(Fixture.check()) }
    let asked = Box(false)
    let cancelled = Box(false)
    let client = try EntitlerClient(
      tokenProvider: {
        asked.with { $0 = true }
        do {
          try await Task.sleep(nanoseconds: 5_000_000_000)
        } catch {
          cancelled.with { $0 = true }
          throw error
        }
        return makeJWT(["sub": "u"])
      }, options: api.options())
    let hooks = api.hooks
    let call = Task {
      try await Hooks.$current.withValue(hooks) { try await client.me.check("sso") }
    }
    while !asked.get { try await Task.sleep(nanoseconds: 1_000_000) }
    client.close()
    await #expect(throws: ClientClosedError()) { try await call.value }
    for _ in 0..<500 where !cancelled.get { try await Task.sleep(nanoseconds: 1_000_000) }
    #expect(cancelled.get)
    #expect(api.count == 0)
  }

  @Test func closingDropsTheMemoryCacheAndLeavesTheSessionOpen() async throws {
    let api = FakeAPI { _ in .json(Fixture.check(), headers: ["Cache-Control": "max-age=60"]) }
    let store = MemoryCacheStore(capacity: 10)
    let first = try EntitlerClient(token: "tok", cache: store, options: api.options())
    _ = try await api.run { try await first.me.check("sso") }
    first.close()
    for _ in 0..<500 {
      let key = first.core.cacheKey(
        try Request("GET", ["customers", "me", "entitlements", "sso"]), token: "tok")
      if await store.entry(forKey: key) == nil { break }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    let next = try EntitlerClient(token: "tok", cache: store, options: api.options())
    _ = try await api.run { try await next.me.check("sso") }
    #expect(api.count == 2)
  }
}
