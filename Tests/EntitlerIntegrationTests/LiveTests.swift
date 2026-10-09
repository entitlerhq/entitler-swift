import Foundation
import Testing

@testable import Entitler

let liveKey = ProcessInfo.processInfo.environment["ENTITLER_TEST_KEY"] ?? ""

enum Live {
  static let aiCredits = Feature<Metered>("ai_credits")
  static let exportPDF = Feature<OnOff>("export_pdf")
  static let collaboration = Feature<FeatureGroup>(
    "collaboration", includes: ["team_seats", "shared_folders"])
  static let sso = Feature<OnOff>("sso")

  static func server(_ change: (inout EntitlerOptions) -> Void = { _ in }) throws -> EntitlerServer
  {
    var options = EntitlerOptions()
    change(&options)
    return try EntitlerServer(key: liveKey, options: options)
  }

  static func newID() -> String { "sdk-swift-\(UUID().uuidString.prefix(12).lowercased())" }

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
      _ = try? await customer.delete(erase: true)
      throw error
    }
    try await customer.delete(erase: true)
  }
}

/// The live API suite. The SDK test project has no sign-in provider, so the identity client is
/// covered by the unit tests only.
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
      _ = try? await customer.delete(erase: true)
      throw error
    }
    try await customer.delete(erase: true)
  }

  @Test func checksEntitlementsAndRevalidation() async throws {
    try await Live.withCustomer { server, customer in
      let check = try await customer.check(Live.aiCredits)
      #expect(check.entitled)
      #expect(check.value == .amount(20))
      #expect(check.remaining == .amount(20))
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
    }
  }

  @Test func usage() async throws {
    try await Live.withCustomer { server, customer in
      let key = "rec-\(UUID().uuidString)"
      let recorded = try await customer.recordUsage(
        of: Live.aiCredits, amount: 5, idempotencyKey: key)
      #expect(recorded.outcome == .recorded)
      #expect(recorded.used == 5)
      let replay = try await customer.recordUsage(
        of: Live.aiCredits, amount: 5, idempotencyKey: key)
      #expect(replay.outcome == .duplicate)
      let refused = try await customer.recordUsage(of: Live.aiCredits, amount: 100)
      #expect(refused.outcome == .refused)
      #expect(refused.refusal == .overAllowance)
      let observed = try await customer.recordUsage(of: Live.aiCredits, amount: 20, mode: .observe)
      #expect(observed.outcome == .recorded)
      #expect(observed.overBy == 5)
      try await customer.vendor.setMeter(Live.aiCredits, to: 0)
      let earlier = try await customer.recordUsage(
        of: Live.aiCredits, amount: 1, occurredAt: Date().addingTimeInterval(-60))
      #expect(earlier.outcome == .recorded)
      #expect(earlier.occurredAt != nil)

      let held = try await customer.holdUsage(of: Live.aiCredits, amount: 4, ttlSeconds: 120)
      #expect(held.outcome == .held)
      let holdID = try #require(held.holdID)
      let readBack = try await customer.hold(id: holdID)
      #expect(readBack.state == .open)
      #expect(readBack.amount == 4)
      let settled = try await customer.settleUsage(hold: holdID, amount: 3)
      #expect(settled.outcome == .settled)
      let released = try await customer.holdUsage(of: Live.aiCredits, amount: 2)
      let releasedID = try #require(released.holdID)
      let release = try await customer.releaseUsage(hold: releasedID)
      #expect(release.outcome == .released)
      let releasedHold = try await customer.hold(id: releasedID)
      #expect(releasedHold.state == .released)

      let output = try await customer.withHold(of: Live.aiCredits, amount: 3) { hold in
        try hold.use(2)
        return "done"
      }
      #expect(output == "done")
      struct WorkFailed: Error {}
      await #expect(throws: WorkFailed.self) {
        try await customer.withHold(of: Live.aiCredits, amount: 3) { _ in throw WorkFailed() }
      }

      let batchKey = "batch-\(UUID().uuidString)"
      let events = [
        UsageBatchEvent(
          customer: customer.id, feature: Live.aiCredits, amount: 1, idempotencyKey: batchKey),
        UsageBatchEvent(
          customer: customer.id, feature: Live.aiCredits, amount: 1, idempotencyKey: batchKey),
      ]
      let batch = try await server.recordUsageBatch(events)
      #expect(batch.results.map(\.outcome) == [.recorded, .duplicate])

      var log: [UsageEvent] = []
      for try await event in customer.usageLog() { log.append(event) }
      #expect(log.count >= 5)
      let cancelled = try await customer.vendor.cancelUsage(try #require(recorded.id))
      #expect(cancelled.outcome == .cancelled)
      let meter = try await customer.vendor.setMeter(Live.aiCredits, to: 7)
      #expect(meter.outcome == .adjusted)
      let usage = try await customer.usage()
      #expect(usage.features.first { $0.feature == "ai_credits" }?.used == 7)
    }
  }

  @Test func plansAndCustomerPricing() async throws {
    try await Live.withCustomer { _, customer in
      let plans = try await customer.plans()
      #expect(plans.held.contains { $0.plan.key == "free" })
      #expect(plans.options.contains { $0.plan.key == "pro" })
      let pricing = try await customer.pricing()
      #expect(pricing.customer == customer.id)
      #expect(pricing.plans.contains { $0.key == "pro" })
    }
  }

  @Test func customerTokensThroughAnInAppClient() async throws {
    try await Live.withCustomer { _, customer in
      let client = try EntitlerClient(tokenProvider: {
        try await customer.token(scopes: [.entitlementsRead, .usageRead, .usageWrite]).token
      })
      let scopes = try await client.scopes()
      #expect(scopes.scopes == [.entitlementsRead, .usageRead, .usageWrite])
      let check = try await client.me.check(Live.aiCredits)
      #expect(check.entitled)
      #expect(await client.me.id == customer.id)
      let entitlements = try await client.me.entitlements()
      #expect(entitlements.has(Live.aiCredits))
      let recorded = try await client.me.recordUsage(of: Live.aiCredits, amount: 1)
      #expect(recorded.reportedAs == .client)
      let narrow = try EntitlerClient(tokenProvider: {
        try await customer.token(scopes: [.entitlementsRead, .usageWrite]).token
      })
      do {
        _ = try await narrow.me.usage()
        Issue.record("A token without usage:read read usage.")
      } catch EntitlerError.api(let error) {
        #expect(error.status == 403)
        #expect(error.code == .scopeRequired)
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

  @Test func tracks() async throws {
    try await Live.withCustomer { server, customer in
      let beta = try await server.customer("test_1013").check(Live.sso).track
      #expect(beta.name == "Beta")
      let moved = try await customer.setTrack(beta.id)
      #expect(moved.track.id == beta.id)
      let back = try await customer.setTrack(nil)
      #expect(back.track.name == "All customers")
    }
  }

  @Test func asOfReads() async throws {
    let server = try Live.server { $0.asOf = Date().addingTimeInterval(-86_400) }
    do {
      let check = try await server.customer("test_1001").check(Live.sso)
      #expect(abs(check.asOf.timeIntervalSinceNow + 86_400) < 120)
    } catch EntitlerError.api(let error) {
      #expect(error.status == 409)
      #expect(error.code == .limitReached)
    }
  }

  @Test func billing() async throws {
    try await Live.withCustomer { server, customer in
      let pro = try await customer.subscribe(to: "pro", period: "Monthly")
      #expect(pro.customer.plan?.key == "pro")
      let added = try await customer.addAddOn("sso_addon")
      #expect(
        added.addOns.contains { $0.plan.key == "sso_addon" }
          || added.subscription?.addOns.contains { $0.plan.key == "sso_addon" } == true)
      let removed = try await customer.removeAddOn("sso_addon")
      #expect(removed.subscription?.addOns.contains { $0.plan.key == "sso_addon" } != true)
      let free = try await customer.cancel(when: .now)
      #expect(free.customer.plan?.key != "pro")
      let pricing = try await server.pricing()
      let period = try #require(
        pricing.plans.first { $0.key == "pro_basic" }?.periods.first?.label)
      let basic = try await customer.vendor.subscribe(to: "pro_basic", period: period)
      #expect(basic.customer.plan?.key == "pro_basic")
      let granted = try await customer.vendor.grant(Live.sso, days: 1, reason: "SDK test")
      let grant = try #require(granted.grants.first { $0.feature == "sso" && $0.revokedAt == nil })
      let revoked = try await customer.vendor.revokeGrant(grant.id)
      #expect(revoked.grants.first { $0.id == grant.id }?.revokedAt != nil)
      let meter = try await customer.vendor.setMeter(Live.aiCredits, to: 3)
      #expect(meter.outcome == .adjusted)
      let calls: [@Sendable () async throws -> Void] = [
        {
          _ = try await customer.checkout(
            "pro", period: "Monthly", successURL: URL(string: "https://example.com/ok")!,
            cancelURL: URL(string: "https://example.com/no")!)
        },
        {
          _ = try await customer.billingPortal(
            returnURL: URL(string: "https://example.com/account")!)
        },
      ]
      for call in calls {
        do {
          try await call()
          Issue.record("Expected 409 stale")
        } catch EntitlerError.api(let error) {
          #expect(error.status == 409)
          #expect(error.code == .stale)
        }
      }
    }
  }

  @Test func listSearchAndDelete() async throws {
    try await Live.withCustomer(name: "Searchable \(UUID().uuidString.prefix(6))") {
      server, customer in
      var found = false
      for try await summary in server.customers.list(query: customer.id)
      where summary.externalID == customer.id {
        found = true
      }
      #expect(found)
    }
  }

  @Test func errorsDecode() async throws {
    let server = try Live.server()
    do {
      try await server.customer(Live.newID()).recordUsage(of: Live.aiCredits, amount: 1)
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
