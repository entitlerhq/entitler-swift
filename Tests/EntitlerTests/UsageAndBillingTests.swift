import Foundation
import Testing

@testable import Entitler

@Suite struct UsageTests {
  @Test func recordUsageSendsOnlyGivenFields() async throws {
    let api = FakeAPI { _ in .json(Fixture.usage(), status: 201) }
    let customer = try api.server().customer("u")
    try await api.run {
      let result = try await customer.recordUsage(of: Feature<Metered>("ai_credits"), amount: 3)
      #expect(result.outcome == .recorded)
      #expect(result.reportedAs == .api)
      #expect(result.mode == .gate)
      #expect(api.last.method == "POST")
      #expect(api.last.path == "/customers/u/usage")
      #expect(api.last.header("Content-Type") == "application/json")
      #expect(api.last.header("Idempotency-Key")?.count == 36)
      #expect(api.last.json?.keys.sorted() == ["amount", "feature"])
      try await customer.recordUsage(
        of: "ai_credits", amount: 2, mode: .observe,
        occurredAt: Date(timeIntervalSince1970: 1_782_898_200),
        register: true)
      let json = try #require(api.last.json)
      #expect(json["mode"] as? String == "observe")
      #expect(json["occurredAt"] as? String == "2026-07-01T09:30:00.000Z")
      #expect(json["register"] as? Bool == true)
    }
  }

  @Test(arguments: [
    "recorded", "duplicate", "refused", "held", "settled", "released", "cancelled", "adjusted",
    "brand_new",
  ])
  func everyOutcomeDecodes(outcome: String) async throws {
    let api = FakeAPI { _ in
      .json(
        Fixture.usage(
          outcome: outcome, refusal: outcome == "refused" ? #""over_allowance""# : "null"))
    }
    let result = try await api.run {
      try await api.server().customer("u").recordUsage(of: "ai_credits", amount: 1)
    }
    #expect(result.outcome.rawValue == outcome)
    #expect(result.outcome == UsageOutcome(rawValue: outcome))
    if outcome == "refused" { #expect(result.refusal == .overAllowance) }
    if outcome == "brand_new" { #expect(result.outcome == .unknown("brand_new")) }
  }

  @Test func holdsSettleReleaseAndReadBack() async throws {
    let api = FakeAPI { request in
      request.method == "GET"
        ? .json(
          #"{"id":"h_1","customer":"u","feature":"ai_credits","amount":10,"state":"open","expiresAt":"2026-10-09T01:52:13Z","settledAmount":null,"usageId":null,"createdAt":"2026-10-09T01:47:13Z"}"#
        )
        : .json(Fixture.usage(outcome: "held", holdID: #""h_1""#))
    }
    let customer = try api.server().customer("u")
    try await api.run {
      let held = try await customer.holdUsage(
        of: Feature<Metered>("ai_credits"), amount: 10, ttlSeconds: 60)
      #expect(held.holdID == "h_1")
      #expect(api.last.path == "/customers/u/usage/holds")
      #expect(api.last.json?["ttlSeconds"] as? Int == 60)
      try await customer.settleUsage(hold: "h_1", amount: 4)
      #expect(api.last.path == "/customers/u/usage/holds/h_1/settle")
      #expect(api.last.json?["amount"] as? Int == 4)
      try await customer.releaseUsage(hold: "h_1")
      #expect(api.last.method == "DELETE")
      #expect(api.last.path == "/customers/u/usage/holds/h_1")
      let hold = try await customer.hold(id: "h_1")
      #expect(hold.state == .open)
      #expect(hold.usageID == nil)
      await #expect(throws: ArgumentError(message: "Provide the id of the hold.")) {
        try await customer.releaseUsage(hold: "")
      }
    }
  }

  @Test func withHoldSettlesWhatWorkUsed() async throws {
    let api = FakeAPI { _ in .json(Fixture.usage(outcome: "held", holdID: #""h_1""#, amount: 10)) }
    let customer = try api.server().customer("u")
    let used = try await api.run {
      try await customer.withHold(
        of: Feature<Metered>("ai_credits"), amount: 10, idempotencyKey: "job-1"
      ) { hold in
        #expect(hold.holdID == "h_1")
        return 7
      }
    }
    #expect(used == 7)
    #expect(
      api.requests.get.map(\.path) == [
        "/customers/u/usage/holds", "/customers/u/usage/holds/h_1/settle",
      ])
    #expect(api.last.json?["amount"] as? Int == 7)
    #expect(api.requests.get[0].header("Idempotency-Key") == "job-1")
  }

  @Test func withHoldRecordsTheExcessInObserveMode() async throws {
    let api = FakeAPI { _ in .json(Fixture.usage(outcome: "held", holdID: #""h_1""#, amount: 10)) }
    let customer = try api.server().customer("u")
    _ = try await api.run {
      try await customer.withHold(of: "ai_credits", amount: 10, idempotencyKey: "job-2") { _ in 15 }
    }
    let requests = api.requests.get
    #expect(requests.count == 3)
    #expect(requests[1].json?["amount"] as? Int == 10)
    #expect(requests[2].path == "/customers/u/usage")
    #expect(requests[2].json?["amount"] as? Int == 5)
    #expect(requests[2].json?["mode"] as? String == "observe")
    #expect(requests[2].header("Idempotency-Key") == "job-2:excess")
  }

  @Test func withHoldReleasesWhenWorkFails() async throws {
    struct WorkFailed: Error {}
    let api = FakeAPI { _ in .json(Fixture.usage(outcome: "held", holdID: #""h_1""#)) }
    let customer = try api.server().customer("u")
    await #expect(throws: WorkFailed.self) {
      try await api.run {
        try await customer.withHold(of: "ai_credits", amount: 10) { _ in throw WorkFailed() }
      }
    }
    #expect(api.last.method == "DELETE")
    #expect(api.last.path == "/customers/u/usage/holds/h_1")
  }

  @Test func failedReleaseGoesToOnError() async throws {
    struct WorkFailed: Error {}
    let errors = Box(0)
    let api = FakeAPI { request in
      request.method == "DELETE"
        ? .error(404, code: "not_found") : .json(Fixture.usage(outcome: "held", holdID: #""h_1""#))
    }
    let customer = try api.server { $0.onError = { _ in errors.with { $0 += 1 } } }.customer("u")
    await #expect(throws: WorkFailed.self) {
      try await api.run {
        try await customer.withHold(of: "ai_credits", amount: 10) { _ in throw WorkFailed() }
      }
    }
    #expect(errors.get == 1)
  }

  @Test func withHoldNeverRunsWorkWhenRefused() async throws {
    let api = FakeAPI { _ in .json(Fixture.usage(outcome: "refused", refusal: #""not_entitled""#)) }
    let ran = Box(false)
    do {
      _ = try await api.run {
        try await api.server().customer("u").withHold(of: "ai_credits", amount: 10) { _ in
          ran.with { $0 = true }
          return 1
        }
      }
      Issue.record("Expected a refusal")
    } catch EntitlerError.usageRefused(let answer) {
      #expect(answer.refusal == .notEntitled)
      #expect(EntitlerError.usageRefused(answer).description.contains("not_entitled"))
    }
    #expect(!ran.get)
  }

  @Test func failedSettlementCarriesTheHoldID() async throws {
    let api = FakeAPI { request in
      request.path.hasSuffix("/settle")
        ? .error(409, code: "hold_expired")
        : .json(Fixture.usage(outcome: "held", holdID: #""h_7""#))
    }
    do {
      _ = try await api.run {
        try await api.server().customer("u").withHold(of: "ai_credits", amount: 10) { _ in 3 }
      }
      Issue.record("Expected an error")
    } catch EntitlerError.api(let error) {
      #expect(error.code == .holdExpired)
      #expect(error.holdID == "h_7")
    }
  }

  @Test func holdIDsAttachToEveryRequestError() {
    let connection = EntitlerError.connection(
      ConnectionError(underlyingError: URLError(.timedOut), idempotencyKey: nil))
    if case .connection(let error) = connection.withHoldID("h") { #expect(error.holdID == "h") }
    let timeout = EntitlerError.timeout(TimeoutError(timeout: 1, idempotencyKey: nil))
    if case .timeout(let error) = timeout.withHoldID("h") { #expect(error.holdID == "h") }
    let token = EntitlerError.token(TokenError(message: "x", underlyingError: nil))
    if case .token(let error) = token.withHoldID("h") { #expect(error.holdID == "h") }
    let snapshot = EntitlerError.snapshot(SnapshotError(code: .invalid, message: "x"))
    if case .snapshot = snapshot.withHoldID("h") {} else { Issue.record("Changed kind") }
  }

  @Test func usageAndItsLogPage() async throws {
    let pages = [
      #"{"items":[{"id":"u_1","feature":"ai_credits","amount":3,"kind":"use","setTo":null,"source":"client","actor":null,"at":"2026-10-09T01:47:13Z","cancelledAt":null}],"next":"c2"}"#,
      #"{"items":[],"next":"c3"}"#,
      #"{"items":[{"id":"u_2","feature":"ai_credits","amount":5,"kind":"adjust","setTo":5,"source":"dashboard","actor":"Ada","at":"2026-10-08T01:47:13Z","cancelledAt":"2026-10-08T02:00:00Z"}],"next":null}"#,
    ]
    let api = FakeAPI { request in
      let index = request.query == nil ? 0 : request.query == "cursor=c2" ? 1 : 2
      return .json(
        #"{"customer":"u","asOf":"2026-10-09T01:47:13Z","metersStartAgainAt":null,"features":[{"feature":"ai_credits","type":"metered","entitled":true,"value":300,"sources":[],"used":3,"held":0,"remaining":297,"resetsAt":null}],"log":\#(pages[index]),\#(Fixture.context)}"#
      )
    }
    let customer = try api.server().customer("u")
    try await api.run {
      let usage = try await customer.usage()
      #expect(usage.features.first?.remaining == .amount(297))
      #expect(usage.log.next == "c2")
      var ids: [String] = []
      for try await event in customer.usageLog() { ids.append(event.id) }
      #expect(ids == ["u_1", "u_2"])
      #expect(api.count == 4)
      var pageCount = 0
      for try await _ in customer.usageLog().pages { pageCount += 1 }
      #expect(pageCount == 3)
    }
  }

  @Test func usageLogRequestsPagesOnlyWhenReached() async throws {
    let api = FakeAPI { _ in
      .json(
        #"{"customer":"u","asOf":"2026-10-09T01:47:13Z","metersStartAgainAt":null,"features":[],"log":{"items":[{"id":"u_1","feature":"f","amount":1,"kind":"use","setTo":null,"source":"api","actor":null,"at":"2026-10-09T01:47:13Z","cancelledAt":null}],"next":"more"},\#(Fixture.context)}"#
      )
    }
    let customer = try api.server().customer("u")
    try await api.run {
      var iterator = customer.usageLog().makeAsyncIterator()
      _ = try await iterator.next()
      #expect(api.count == 1)
    }
  }

  @Test func batchesSplitAtFiveHundredAndKeepInputOrder() async throws {
    let api = FakeAPI { request in
      let events = (request.json?["events"] as? [[String: Any]]) ?? []
      let results = events.indices.map {
        #"{"index":\#($0),"outcome":"recorded","id":"u_\#($0)","late":false,"error":null}"#
      }
      return .json(
        #"{"results":[\#(results.joined(separator: ","))],"recorded":\#(events.count),"duplicates":0,"errors":0}"#
      )
    }
    let events = (0..<1_001).map {
      UsageBatchEvent(
        customer: "c\($0)", feature: Feature<Metered>("ai_credits"), amount: 1,
        idempotencyKey: $0 == 0 ? "first" : nil)
    }
    let result = try await api.run {
      try await api.server().recordUsageBatch(events, register: true)
    }
    #expect(api.requests.get.map { ($0.json?["events"] as? [Any])?.count } == [500, 500, 1])
    #expect(result.results.count == 1_001)
    #expect(result.results.map(\.index) == Array(0..<1_001))
    #expect(result.recorded == 1_001)
    let first = try #require(api.requests.get.first?.json)
    #expect(first["register"] as? Bool == true)
    let event = try #require((first["events"] as? [[String: Any]])?.first)
    #expect(event["idempotencyKey"] as? String == "first")
    #expect(event["customer"] as? String == "c0")
    #expect(api.last.path == "/usage/events")
  }

  @Test func batchErrorsDecode() async throws {
    let api = FakeAPI { _ in
      .json(
        #"{"results":[{"index":0,"outcome":"error","id":null,"late":false,"error":{"code":"not_metered","message":"No."}},{"index":1,"outcome":"duplicate","id":"u_1","late":true,"error":null}],"recorded":0,"duplicates":1,"errors":1}"#
      )
    }
    let result = try await api.run {
      try await api.server().recordUsageBatch([
        UsageBatchEvent(customer: "a", feature: "sso"),
        UsageBatchEvent(customer: "b", feature: "ai_credits"),
      ])
    }
    #expect(result.results[0].error?.code == .notMetered)
    #expect(result.results[1].outcome == .duplicate)
    #expect(result.duplicates == 1)
    #expect(api.last.json?["register"] == nil)
    await #expect(throws: ArgumentError(message: "Provide the id your app uses for the customer."))
    {
      try await api.server().recordUsageBatch([UsageBatchEvent(customer: " ", feature: "f")])
    }
  }

  @Test func snapshotsAreMinted() async throws {
    let api = FakeAPI { _ in
      .json(#"{"token":"a.b.c","expiresAt":"2026-10-10T00:00:00Z","keyId":"k1"}"#, status: 201)
    }
    let customer = try api.server().customer("u")
    try await api.run {
      let snapshot = try await customer.snapshot()
      #expect(snapshot.keyID == "k1")
      #expect(api.last.body.map { String(decoding: $0, as: UTF8.self) } == "{}")
      _ = try await customer.snapshot(ttlSeconds: 600)
      #expect(api.last.json?["ttlSeconds"] as? Int == 600)
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

  @Test func detailsUpdateDeleteTokenAndTrack() async throws {
    let api = FakeAPI { request in
      switch (request.method, request.path) {
      case ("GET", _): .json(Fixture.detail)
      case ("POST", _):
        .json(
          #"{"token":"tok","customer":"u","scopes":["entitlements:read","future:scope"],"expiresAt":"2026-10-09T02:47:13Z"}"#
        )
      case ("PUT", _):
        .json(
          #"{"customer":"u","track":{"id":"t2","name":"Beta"},"source":"server","previousTrackId":"t1"}"#
        )
      default: .json(Fixture.summary)
      }
    }
    let customer = try api.server().customer("u")
    try await api.run {
      let detail = try await customer.details(cursor: "c1")
      #expect(api.last.query == "cursor=c1")
      #expect(detail.subscription?.pending?.type == .cancel)
      #expect(detail.subscription?.purchase.channel?.provider == .stripe)
      #expect(detail.banked["ai_credits"] == 5)
      #expect(detail.selfServe == true)
      #expect(detail.customer.metadata["team"] == "a")
      let updated = try await customer.update(
        email: "new@example.com", metadata: ["team": nil, "role": "admin"])
      #expect(updated.externalID == "user_1")
      #expect(api.last.method == "PATCH")
      let metadata = try #require(api.last.json?["metadata"] as? [String: Any])
      #expect(metadata["team"] is NSNull)
      #expect(metadata["role"] as? String == "admin")
      #expect(api.last.json?["name"] == nil)
      try await customer.delete(erase: true)
      #expect(api.last.method == "DELETE")
      #expect(api.last.query == "erase=true")
      try await customer.delete()
      #expect(api.last.query == nil)
      let token = try await customer.token(scopes: [.entitlementsRead], ttlSeconds: 600)
      #expect(token.scopes == [.entitlementsRead])
      #expect(api.last.json?["scopes"] as? [String] == ["entitlements:read"])
      _ = try await customer.token()
      #expect(api.last.body.map { String(decoding: $0, as: UTF8.self) } == "{}")
      let track = try await customer.setTrack("t2")
      #expect(track.previousTrackID == "t1")
      #expect(api.last.json?["trackId"] as? String == "t2")
      try await customer.setTrack(nil)
      #expect(api.last.body.map { String(decoding: $0, as: UTF8.self) } == #"{"trackId":null}"#)
    }
  }

  @Test func selfServeBillingSendsSelfServeTrue() async throws {
    let api = FakeAPI { request in
      request.path.hasSuffix("checkout") || request.path.hasSuffix("billing-portal")
        ? .json(#"{"provider":"stripe","url":"https://checkout.test/s"}"#) : .json(Fixture.detail)
    }
    let customer = try api.server().customer("u")
    try await api.run {
      try await customer.subscribe(to: "pro", period: "yearly")
      #expect(api.last.path == "/customers/u/subscription")
      #expect(api.last.json?["plan"] as? String == "pro")
      #expect(api.last.json?["selfServe"] as? Bool == true)
      #expect(api.last.json?["override"] == nil)
      try await customer.subscribe(
        to: .sku(SKU(connector: "apple", ids: ["productId": "pro"])), when: .end)
      #expect((api.last.json?["sku"] as? [String: Any])?["connector"] as? String == "apple")
      #expect(api.last.json?["when"] as? String == "end")
      let page = try await customer.checkout(
        "pro", successURL: URL(string: "https://app.test/ok")!,
        cancelURL: URL(string: "https://app.test/no")!)
      #expect(page.url.absoluteString == "https://checkout.test/s")
      #expect(api.last.json?["successUrl"] as? String == "https://app.test/ok")
      #expect(api.last.json?["selfServe"] as? Bool == true)
      try await customer.cancel(when: .now, product: "app")
      #expect(api.last.query == "product=app&when=now")
      try await customer.cancel()
      #expect(api.last.query == nil)
      try await customer.undoPendingChange(product: "app")
      #expect(api.last.path == "/customers/u/subscription/pending")
      try await customer.addAddOn("sso_addon", quantity: 2, replaces: "old")
      #expect(api.last.json?["quantity"] as? Int == 2)
      #expect(api.last.json?["replaces"] as? String == "old")
      #expect(api.last.json?["selfServe"] as? Bool == true)
      try await customer.setAddOnQuantity("sso_addon", to: 3)
      #expect(api.last.method == "PATCH")
      #expect(api.last.json?["selfServe"] as? Bool == true)
      try await customer.removeAddOn("sso_addon")
      #expect(api.last.path == "/customers/u/subscription/add-ons/sso_addon")
      try await customer.undoAddOnChange("sso_addon")
      #expect(api.last.path == "/customers/u/subscription/add-ons/sso_addon/pending")
      _ = try await customer.billingPortal(returnURL: URL(string: "https://app.test/account")!)
      #expect(api.last.json?["returnUrl"] as? String == "https://app.test/account")
      await #expect(throws: ArgumentError(message: "Name the plan by its id or its key.")) {
        try await customer.subscribe(to: " ")
      }
    }
  }

  @Test func vendorActionsSendSelfServeFalse() async throws {
    let api = FakeAPI { request in
      if request.path.contains("/meters/") || request.path.contains("/usage/") {
        return .json(Fixture.usage(outcome: "adjusted"))
      }
      if request.path.hasSuffix("checkout") {
        return .json(#"{"provider":"stripe","url":"https://checkout.test/s"}"#)
      }
      return .json(Fixture.detail)
    }
    let vendor = try api.server().customer("u").vendor
    try await api.run {
      try await vendor.subscribe(to: "team")
      #expect(api.last.json?["selfServe"] as? Bool == false)
      try await vendor.override(to: "team", period: "monthly")
      #expect(api.last.json?["override"] as? Bool == true)
      #expect(api.last.json?["selfServe"] as? Bool == false)
      try await vendor.undoOverride(product: "app")
      #expect(api.last.path == "/customers/u/subscription/override")
      #expect(api.last.query == "product=app")
      _ = try await vendor.checkout(
        "team", successURL: URL(string: "https://a.test")!,
        cancelURL: URL(string: "https://b.test")!, connection: "c1")
      #expect(api.last.json?["selfServe"] as? Bool == false)
      #expect(api.last.json?["connection"] as? String == "c1")
      try await vendor.addAddOn("sso_addon")
      #expect(api.last.json?["selfServe"] as? Bool == false)
      try await vendor.setAddOnQuantity("sso_addon", to: 2)
      #expect(api.last.json?["selfServe"] as? Bool == false)
      try await vendor.grant(Feature<OnOff>("sso"), days: 30, reason: "Trial")
      #expect(api.last.json?.keys.sorted() == ["days", "feature", "reason"])
      try await vendor.grant("seats", value: .amount(5))
      #expect(api.last.json?["value"] as? String == "5")
      try await vendor.grant("credits", value: .unlimited)
      #expect(api.last.json?["value"] as? String == "unlimited")
      try await vendor.revokeGrant("g_1")
      #expect(api.last.path == "/customers/u/grants/g_1")
      let set = try await vendor.setMeter(Feature<Metered>("ai_credits"), to: 40)
      #expect(set.outcome == .adjusted)
      #expect(api.last.method == "PUT")
      #expect(api.last.json?["used"] as? Int == 40)
      try await vendor.cancelUsage("u_1")
      #expect(api.last.path == "/customers/u/usage/u_1")
      await #expect(throws: ArgumentError(message: "Provide the id of the grant.")) {
        try await vendor.revokeGrant("")
      }
      await #expect(throws: ArgumentError(message: "Provide the id of the usage report.")) {
        try await vendor.cancelUsage("")
      }
    }
  }

  @Test func billingAndProvidersDecode() async throws {
    let api = FakeAPI { request in
      request.path.hasSuffix("billing")
        ? .json(
          #"{"provider":"stripe","status":"past_due","sku":{"period":"monthly","connector":"stripe","ids":{"price":"p"},"price":null},"items":1,"drift":{"billedPlan":"pro","heldPlan":null,"observedAt":"2026-10-09T01:47:13Z"},"products":[{"product":"app","status":"active","sku":null,"items":1,"drift":null}]}"#
        )
        : .json(
          #"{"connections":[{"connection":{"id":"c","name":"Stripe","provider":"stripe"},"readAt":"2026-10-09T01:47:13Z","state":{"subscriptions":[{"id":"s","status":"active","billing":true,"period":{"startsAt":"2026-10-01T00:00:00Z","endsAt":"2026-11-01T00:00:00Z"},"trialEndsAt":null,"cancelsAt":null,"items":[{"id":"i","ids":{},"quantity":1,"sale":{"plan":"pro","version":1,"period":"monthly","kind":"plan","product":"app"}}]}],"payments":[{"id":"p","ids":{},"quantity":1,"amount":{"value":100,"currency":"aud"},"status":"partially_refunded","paidAt":"2026-10-01T00:00:00Z","sale":null}]}}],"alerts":[{"id":"a","rule":"held_plan_differs","title":"T","message":"M","facts":{"customer":"u","connection":"c","provider":"google","refusal":"sandbox_builds_turned_off","planId":"p1"},"customer":{"externalId":"u","name":"Ada"},"connection":{"id":"c","name":"Stripe","provider":"stripe"},"openedAt":"2026-10-01T00:00:00Z","seenAt":"2026-10-01T00:00:00Z","resolvedAt":null,"resolvedBy":"person"}]}"#
        )
    }
    let customer = try api.server().customer("u")
    try await api.run {
      let billing = try await customer.billing()
      #expect(billing.status == .pastDue)
      #expect(billing.products?.first?.status == .active)
      let providers = try await customer.providers()
      #expect(providers.alerts.first?.rule == .heldPlanDiffers)
      #expect(providers.alerts.first?.facts.refusal == .sandboxBuildsTurnedOff)
      #expect(providers.alerts.first?.facts.planID == "p1")
      #expect(providers.connections.first?.state.payments.first?.status == .partiallyRefunded)
      #expect(providers.linked == nil)
    }
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
      let created = try await server.customers.create(
        id: "new_1", name: "Ada", plan: "pro", idempotencyKey: "create-1")
      #expect(created.customer.name == "Ada")
      #expect(api.last.json?["externalId"] as? String == "new_1")
      #expect(api.last.json?.keys.sorted() == ["externalId", "name", "plan"])
      #expect(api.last.header("Idempotency-Key") == "create-1")
    }
  }

  @Test func planSpaceDecodes() async throws {
    let api = FakeAPI { _ in
      .json(
        #"{"customer":"u","asOf":"2026-10-09T01:47:13Z","held":[{"plan":{"id":"p","key":"free","name":"Free","kind":"plan"},"product":{"key":"app","name":"App"},"version":1,"byDefault":true}],"options":[{"plan":{"id":"p2","key":"pro","name":"Pro","kind":"plan"},"product":{"key":"app","name":"App"},"move":"move","from":{"id":"p","key":"free","name":"Free"},"direction":"up","mode":"self-serve","selfServe":true,"disabledReason":null,"when":"now","impact":[{"kind":"Gains","text":"SSO"}],"skus":[]}],\#(Fixture.context)}"#
      )
    }
    let space = try await api.run { try await api.server().customer("u").planSpace() }
    #expect(space.held.first?.byDefault == true)
    let option = try #require(space.options.first)
    #expect(option.mode == .selfServe)
    #expect(option.direction == .up)
    #expect(option.impact.first?.kind == .gains)
    #expect(option.plan.kind == .plan)
  }

  @Test func entitlementsGetAndHas() async throws {
    let api = FakeAPI { _ in .json(Fixture.entitlements) }
    let entitlements = try await api.run { try await api.server().customer("u").entitlements() }
    #expect(entitlements.has(Feature<OnOff>("export_pdf")))
    #expect(!entitlements.has(Feature<FeatureGroup>("collaboration", includes: ["team_seats"])))
    #expect(!entitlements.has("missing"))
    #expect(entitlements[Feature<Metered>("ai_credits")]?.remaining == .unlimited)
    #expect(entitlements["collaboration"]?.sources.first?.features == ["team_seats"])
    #expect(entitlements["missing"] == nil)
    #expect(entitlements.items.count == 3)
  }
}
