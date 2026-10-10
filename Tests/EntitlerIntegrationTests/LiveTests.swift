import Foundation
import Testing

@testable import Entitler

let liveKey = ProcessInfo.processInfo.environment["ENTITLER_TEST_KEY"] ?? ""
let livePublishableKey = ProcessInfo.processInfo.environment["ENTITLER_TEST_PUBLISHABLE_KEY"] ?? ""

enum Live {
  static let aiCredits = Feature<Metered>("ai_credits")
  static let exportPDF = Feature<OnOff>("export_pdf")
  static let collaboration = Feature<FeatureGroup>(
    "collaboration", includes: ["team_seats", "shared_folders"])
  static let sso = Feature<OnOff>("sso")
  static let returnURL = URL(string: "https://example.com/billing/return")!

  static func server() throws -> EntitlerServer { try EntitlerServer(key: liveKey) }

  static func newID() -> String { "sdk-swift-\(UUID().uuidString.prefix(12).lowercased())" }

  static func key(_ name: String) -> String { "\(name)-\(UUID().uuidString.lowercased())" }

  /// Registers a unique customer, runs `body`, and erases the customer even when `body` fails.
  static func withCustomer(
    name: String = "SDK test", _ body: (EntitlerServer, ServerCustomer) async throws -> Void
  ) async throws {
    let server = try server()
    let customer = try server.customer(newID())
    try await customer.register(name: name, email: "sdk-swift@example.com")
    do {
      try await body(server, customer)
    } catch {
      try? await customer.erase()
      throw error
    }
    try await customer.erase()
  }

  static func expectAPIError(
    _ status: Int, _ code: ErrorCode, _ call: () async throws -> Void
  ) async {
    do {
      try await call()
      Issue.record("Expected \(status) \(code)")
    } catch EntitlerError.api(let error) {
      #expect(error.status == status)
      #expect(error.code == code)
    } catch {
      Issue.record("Expected \(status) \(code), not \(error)")
    }
  }
}

/// The live API suite. The SDK test project has no sign-in provider and no Stripe connection, so
/// the identity client, and the `pay`, `confirming` and `manage` steps, are covered by the unit
/// tests only.
@Suite(
  .enabled(if: !liveKey.isEmpty, "Live API tests skipped: set ENTITLER_TEST_KEY to run them."),
  .serialized)
struct LiveTests {
  @Test func scopesPricingAndFeatures() async throws {
    let server = try Live.server()
    let scopes = try await server.scopes()
    #expect(scopes.contains(.plansRead))
    #expect(scopes.contains(.tracksAssign))
    let pricing = try await server.pricing(visitor: newVisitorID())
    #expect(pricing.plans.contains { $0.key == "pro" })
    #expect(pricing.defaultPlan == "free")
    let features = try await server.features()
    #expect(features.track.name == "All customers")
    #expect(
      Set(features.features.map(\.key)).isSuperset(of: [
        "ai_credits", "collaboration", "export_pdf", "sso", "team_seats",
      ]))
    #expect(features.features.first { $0.key == "ai_credits" }?.type == .metered)
  }

  @Test(.enabled(if: !livePublishableKey.isEmpty, "Set ENTITLER_TEST_PUBLISHABLE_KEY to run it."))
  func signedOutPricingWithAPublishableKey() async throws {
    let client = try EntitlerClient(key: livePublishableKey)
    defer { client.close() }
    let pricing = try await client.pricing()
    #expect(pricing.plans.contains { $0.key == "pro" })
  }

  @Test func registerDetailsAndUpdate() async throws {
    let server = try Live.server()
    let customer = try server.customer(Live.newID())
    let created = try await customer.register(name: "First", visitor: newVisitorID())
    do {
      #expect(created.created)
      let again = try await customer.register(name: "Second", email: "second@example.com")
      #expect(!again.created)
      var details = try await customer.details()
      #expect(details.customer.name == "Second")
      #expect(details.customer.email == "second@example.com")
      let updated = try await customer.update(metadata: ["team": "core"])
      #expect(updated.metadata["team"] == "core")
      try await customer.update(metadata: ["team": nil])
      details = try await customer.details()
      #expect(details.customer.metadata["team"] == nil)
    } catch {
      try? await customer.erase()
      throw error
    }
    try await customer.erase()
  }

  @Test func checksEntitlementsAndRevalidation() async throws {
    try await Live.withCustomer { server, customer in
      let check = try await customer.check(Live.aiCredits)
      #expect(check.entitled)
      #expect(check.remaining == check.value)
      let group = try await customer.check(Live.collaboration)
      #expect(!group.entitled)
      let entitlements = try await customer.entitlements()
      #expect(!entitlements.has(Live.collaboration))
      #expect(entitlements[Live.collaboration] != nil)
      #expect(entitlements.has(Live.aiCredits))
      for segments in [["entitlements", "export_pdf"], ["entitlements"]] {
        let request = try customer.handle.request("GET", segments, timeout: nil)
        let first = try await server.core.send(request)
        let etag = try #require(first.etag)
        let second = try await server.core.send(request, ifNoneMatch: etag)
        #expect(second.status == 304)
      }
      #expect(await customer.isEntitled(to: Live.sso, default: true) == false)
      let other = try Live.server()
      let granted = try await other.customer(customer.id).grant(
        Live.sso, days: 1, reason: "Revalidate", actor: "sdk-swift-tests",
        idempotencyKey: Live.key("grant"))
      #expect(try await customer.check(Live.sso, revalidate: true).entitled)
      try await other.customer(customer.id).revokeGrant(id: granted.grant.id)
    }
  }

  @Test func usage() async throws {
    try await Live.withCustomer { server, customer in
      let key = Live.key("rec")
      let recorded = try await customer.recordUsage(
        of: Live.aiCredits, amount: 5, idempotencyKey: key)
      #expect(recorded.outcome == .recorded)
      #expect(recorded.used == 5)
      let replay = try await customer.recordUsage(
        of: Live.aiCredits, amount: 5, idempotencyKey: key)
      #expect(replay.outcome == .duplicate)
      #expect(replay.replayed)
      let allowance: Int64 =
        switch recorded.value {
        case .amount(let amount): amount
        default: 20
        }
      let refused = try await customer.recordUsage(
        of: Live.aiCredits, amount: allowance * 10, idempotencyKey: Live.key("over"))
      #expect(refused.outcome == .refused)
      #expect(refused.refusal == .overAllowance)
      let observed = try await customer.recordUsage(
        of: Live.aiCredits, amount: allowance, idempotencyKey: Live.key("observe"), mode: .observe)
      #expect(observed.outcome == .recorded)
      #expect(observed.overBy == 5)
      try await customer.adjustMeter(Live.aiCredits, to: 0, idempotencyKey: Live.key("reset"))
      let earlier = try await customer.recordUsage(
        of: Live.aiCredits, amount: 1, idempotencyKey: Live.key("earlier"),
        occurredAt: Date().addingTimeInterval(-60))
      #expect(earlier.occurredAt != nil)

      let finishedKey = Live.key("hold")
      let hold = try await customer.startHold(
        of: Live.aiCredits, amount: 4, idempotencyKey: finishedKey, ttlSeconds: 120)
      #expect(!hold.isDuplicate)
      try hold.use(3)
      let settled = try await hold.finish()
      #expect(settled.outcome == .settled)
      let released = try await customer.startHold(
        of: Live.aiCredits, amount: 2, idempotencyKey: Live.key("release"))
      #expect(try await released.release().outcome == .released)
      #expect(try await customer.hold(id: released.id).state == .released)
      do {
        _ = try await customer.startHold(of: Live.aiCredits, amount: 4, idempotencyKey: finishedKey)
        Issue.record("Expected the finished hold's key to replay")
      } catch EntitlerError.usageReplayed(let answer) {
        #expect(answer.outcome == .settled)
      }

      let output = try await customer.withHold(
        of: Live.aiCredits, amount: 3, idempotencyKey: Live.key("with")
      ) { hold in
        try hold.use(2)
        return "done"
      }
      #expect(output == "done")
      struct WorkFailed: Error {}
      let before = try await customer.check(Live.aiCredits, revalidate: true).used
      await #expect(throws: WorkFailed.self) {
        try await customer.withHold(of: Live.aiCredits, amount: 3, idempotencyKey: Live.key("fail"))
        { hold in
          try hold.use(1)
          throw WorkFailed()
        }
      }
      #expect(try await customer.check(Live.aiCredits, revalidate: true).used == before + 1)
      await #expect(throws: WorkFailed.self) {
        try await customer.withHold(of: Live.aiCredits, amount: 3, idempotencyKey: Live.key("none"))
        { _ in throw WorkFailed() }
      }
      #expect(try await customer.check(Live.aiCredits, revalidate: true).used == before + 1)

      let eventKey = Live.key("event")
      let events = [
        UsageBatchEvent(
          customer: customer.id, feature: Live.aiCredits, amount: 1, idempotencyKey: eventKey),
        UsageBatchEvent(
          customer: customer.id, feature: Live.aiCredits, amount: 1, idempotencyKey: eventKey),
      ]
      let batch = try await server.recordUsageBatch(events)
      #expect(batch.results.map(\.outcome) == [.recorded, .duplicate])
      let resent = try await server.recordUsageBatch(events)
      #expect(resent.results.allSatisfy { $0.replayed })

      var log: [UsageEvent] = []
      for try await event in customer.usageLog() { log.append(event) }
      #expect(log.count >= 5)
      let cancelled = try await customer.cancelUsage(
        id: try #require(recorded.id), reason: "SDK test", actor: "sdk-swift-tests")
      #expect(cancelled.outcome == .cancelled)
      let by = try await customer.adjustMeter(Live.aiCredits, by: 2, idempotencyKey: Live.key("by"))
      #expect(by.outcome == .adjusted)
      #expect(by.meterChange == 2)
      let to = try await customer.adjustMeter(Live.aiCredits, to: 7, idempotencyKey: Live.key("to"))
      #expect(to.outcome == .adjusted)
      let usage = try await customer.usage()
      #expect(usage.features.first { $0.feature == "ai_credits" }?.used == 7)
    }
  }

  @Test func plansAndCustomerPricing() async throws {
    try await Live.withCustomer { _, customer in
      let plans = try await customer.plans()
      let free = try #require(plans.held.first { $0.plan.key == "free" })
      #expect(free.billedBy == nil)
      #expect(free.period == nil)
      let pro = try #require(plans.options.first { $0.plan.key == "pro" })
      #expect(pro.action == .buy)
      #expect(Set(pro.periods.map(\.key)) == ["monthly", "yearly"])
      let pricing = try await customer.pricing()
      #expect(pricing.customer == customer.id)
      #expect(pricing.plans.contains { $0.key == "pro" })
    }
  }

  @Test func customerTokensThroughAnInAppClient() async throws {
    try await Live.withCustomer { _, customer in
      let plain = try await customer.token()
      #expect(plain.scopes == [.entitlementsRead])
      let client = try EntitlerClient(tokenProvider: {
        try await customer.token(scopes: [.entitlementsRead, .usageWrite, .billingSelf]).token
      })
      defer { client.close() }
      let scopes = try await client.scopes()
      #expect(scopes.scopes == [.entitlementsRead, .usageWrite, .billingSelf])
      let check = try await client.me.check(Live.aiCredits)
      #expect(check.entitled)
      #expect(await client.me.id == customer.id)
      let recorded = try await client.me.recordUsage(
        of: Live.aiCredits, amount: 1, idempotencyKey: Live.key("app"))
      #expect(recorded.reportedAs == .client)
      do {
        let step = try await client.me.subscribe(
          to: "pro", period: "monthly", returnURL: Live.returnURL)
        guard case .done = step else {
          Issue.record("Expected a done step without Stripe, not \(step)")
          return
        }
      } catch EntitlerError.api(let error) {
        #expect(error.status == 409)
        #expect(error.code == .capabilityRequired)
      }
      let narrow = try EntitlerClient(tokenProvider: {
        try await customer.token(scopes: [.entitlementsRead, .usageWrite]).token
      })
      defer { narrow.close() }
      await Live.expectAPIError(403, .scopeRequired) {
        _ = try await narrow.me.subscribe(to: "pro", period: "monthly")
      }
    }
  }

  @Test func snapshotsVerifyOffline() async throws {
    try await Live.withCustomer { server, customer in
      let issued = try await customer.snapshot(ttlSeconds: 600)
      let keys = try await server.snapshotKeys()
      let environment = try await customer.check(Live.sso).environment.id
      let snapshot = try verifySnapshot(
        issued.token,
        expecting: SnapshotExpectation(keys: keys, customer: customer.id, environment: environment))
      #expect(snapshot.customer == customer.id)
      #expect(snapshot.entitlements.has(Live.aiCredits))
      #expect(!snapshot.entitlements.has(Live.collaboration))
    }
  }

  @Test func tracksByName() async throws {
    try await Live.withCustomer { _, customer in
      let moved = try await customer.setTrack("Beta")
      #expect(moved.track.name == "Beta")
      let back = try await customer.setTrack(nil)
      #expect(back.track.name == "All customers")
    }
  }

  @Test func asOfReads() async throws {
    let customer = try Live.server().customer("test_1001")
    do {
      let check = try await customer.check(Live.sso, asOf: Date().addingTimeInterval(-86_400))
      #expect(abs(check.asOf.timeIntervalSinceNow + 86_400) < 120)
    } catch EntitlerError.api(let error) {
      #expect(error.status == 409)
      #expect(error.code == .capabilityRequired)
    }
  }

  @Test func billing() async throws {
    try await Live.withCustomer { _, customer in
      guard case .done(let pro) = try await customer.subscribe(to: "pro", period: "monthly") else {
        Issue.record("Expected a done step without Stripe")
        return
      }
      #expect(pro.plan?.key == "pro")
      guard case .done(let addOn) = try await customer.subscribe(to: "sso_addon") else {
        Issue.record("Expected a done step for the add-on")
        return
      }
      #expect(addOn.plan?.key == "sso_addon")
      #expect(try await customer.cancel(addOn: "sso_addon").changed)
      let cancelled = try await customer.cancel()
      #expect(cancelled.changed)
      _ = try await customer.undoPendingChange()
      let plans = try await customer.plans()
      let period = try #require(
        plans.options.first { $0.plan.key == "pro_basic" }?.periods.first?.key)
      let basic = try await customer.setPlan(
        to: "pro_basic", period: period, reason: "SDK test", actor: "sdk-swift-tests")
      #expect(basic.plan?.key == "pro_basic")
      let same = try await customer.setPlan(to: "pro_basic", period: period)
      #expect(!same.changed)
      let until = Date().addingTimeInterval(86_400)
      let limited = try await customer.setPlan(to: "pro_basic", period: period, until: until)
      #expect(limited.until != nil)
      #expect(try await customer.setAddOn("support_standard", quantity: 1).quantity == 1)
      #expect(try await customer.setAddOn("support_standard", quantity: 0).quantity == 0)
      _ = try await customer.cancel(product: basic.product?.key)
      let nothing = try await customer.cancel()
      #expect(!nothing.changed)
      let granted = try await customer.grant(
        Live.sso, days: 1, reason: "SDK test", actor: "sdk-swift-tests")
      #expect(granted.grant.feature == "sso")
      let revoked = try await customer.revokeGrant(id: granted.grant.id)
      #expect(revoked.grant.revokedAt != nil)
      #expect(try await customer.syncBilling().changed == false)
      await Live.expectAPIError(409, .stale) {
        _ = try await customer.billingPortal(returnURL: Live.returnURL)
      }
    }
  }

  @Test func listSearchAndErase() async throws {
    try await Live.withCustomer(name: "Searchable \(UUID().uuidString.prefix(6))") {
      server, customer in
      var found = false
      var pages = server.customers.list(query: customer.id).pages.makeAsyncIterator()
      while let page = try await pages.next() {
        found = found || page.items.contains { $0.externalID == customer.id }
      }
      #expect(found)
    }
  }

  @Test func errorsDecode() async throws {
    let server = try Live.server()
    do {
      try await server.customer(Live.newID()).recordUsage(
        of: Live.aiCredits, amount: 1, idempotencyKey: Live.key("missing"))
      Issue.record("Expected customer_not_found")
    } catch EntitlerError.api(let error) {
      #expect(error.code == .customerNotFound)
      #expect(error.status == 404)
      #expect(error.requestID != nil)
      #expect(error.idempotencyKey != nil)
    }
    do {
      _ = try await server.customer("test_1001").check("no_such_feature")
      Issue.record("Expected feature_not_found")
    } catch EntitlerError.api(let error) {
      #expect(error.code == .featureNotFound)
      #expect(error.requestID != nil)
    }
  }
}
