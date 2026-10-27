import Entitler
import Foundation
import Testing

@testable import EntitlerTesting

@Suite struct FakeCustomerTests {
  let aiCredits = Feature<Metered>("ai_credits")

  @Test func checksAnswerTheValues() async throws {
    let fake = try FakeCustomer([
      "export_pdf": true, "seats": 5, "sso": .unlimited,
      "ai_credits": .metered(limit: 100, used: 97),
    ])
    #expect(try await fake.customer.check("export_pdf").entitled)
    #expect(try await fake.customer.check("seats").value == .amount(5))
    #expect(try await fake.me.check("sso").value == .unlimited)
    #expect(try await fake.customer.check(aiCredits).meter.remaining == .amount(3))
    #expect(try await fake.customer.entitlements().map(\.key).count == 4)
    #expect(await fake.customer.isEntitled(to: "unknown", default: true))
  }

  @Test func usageMovesTheMeterAndRefusesWhatDoesNotFit() async throws {
    let fake = try FakeCustomer(["ai_credits": .metered(limit: 100, used: 97)])
    let refused = try await fake.customer.recordUsage(
      of: aiCredits, amount: 5, idempotencyKey: "m-1")
    let recorded = try await fake.customer.recordUsage(
      of: aiCredits, amount: 3, idempotencyKey: "m-2")
    let replayed = try await fake.customer.recordUsage(
      of: aiCredits, amount: 3, idempotencyKey: "m-2")

    #expect(refused.outcome == .refused)
    #expect(refused.refusal == .overAllowance)
    #expect(recorded.outcome == .recorded)
    #expect(replayed.replayed)
    #expect(fake.used("ai_credits") == 100)
    #expect(fake.writes.map(\.idempotencyKey) == ["m-1", "m-2"])
  }

  @Test func withHoldSettlesWhatTheWorkUsed() async throws {
    let fake = try FakeCustomer(["ai_credits": .metered(limit: 1_000)])
    let summary = try await fake.me.withHold(
      of: aiCredits, amount: 500, idempotencyKey: "summary-1"
    ) { hold in
      try hold.use(120)
      return "summary"
    }

    #expect(summary == "summary")
    #expect(fake.used("ai_credits") == 120)
    #expect(fake.writes.map(\.method) == ["holdUsage", "settleUsage"])
  }

  @Test func observedUsageIsRecordedPastTheAllowance() async throws {
    let fake = try FakeCustomer(["ai_credits": .metered(limit: 100, used: 97)])
    let result = try await fake.customer.recordUsage(
      of: aiCredits, amount: 5, idempotencyKey: "m-1", mode: .observe)

    #expect(result.mode == .observe)
    #expect(result.overBy == 2)
    #expect(throws: ArgumentError.self) { try FakeCustomer([:], id: "me") }
  }

  @Test func aHoldThatDoesNotFitIsRefused() async throws {
    let fake = try FakeCustomer(["ai_credits": .metered(limit: 100, used: 90)])
    do {
      _ = try await fake.customer.startHold(of: aiCredits, amount: 20, idempotencyKey: "m-1")
      Issue.record("Expected a refusal.")
    } catch EntitlerError.usageRefused(let error) {
      #expect(error.result.refusal == .overAllowance)
    }
  }

  @Test func aCustomerIDWithASlashRoutesToTheFake() async throws {
    let fake = try FakeCustomer(["export_pdf": true], id: "org/user")
    #expect(try await fake.customer.check("export_pdf").entitled)
  }

  @Test func aHoldExpiresAfterItsTTLAndFreesTheAllowance() async throws {
    let clock = Clock()
    let fake = try FakeCustomer(["ai_credits": .metered(limit: 10)], id: "user_1") { clock.now }
    let hold = try await fake.customer.holdUsage(
      of: aiCredits, amount: 10, idempotencyKey: "h-1", ttlSeconds: 60)
    clock.now += 60

    #expect(try await fake.customer.check(aiCredits).meter.held == 0)
    do {
      _ = try await fake.customer.settleUsage(hold: try #require(hold.holdID), amount: 10)
      Issue.record("Expected an expired hold.")
    } catch EntitlerError.api(let error) {
      #expect(error.reason == .holdExpired)
    }
    #expect(fake.used("ai_credits") == 0)
  }

  @Test func settlingMoreThanTheHoldIsRefusedAndKeepsIt() async throws {
    let fake = try FakeCustomer(["ai_credits": .metered(limit: 10)])
    let hold = try await fake.customer.holdUsage(of: aiCredits, amount: 1, idempotencyKey: "h-1")
    let id = try #require(hold.holdID)

    await #expect(throws: EntitlerError.self) {
      try await fake.customer.settleUsage(hold: id, amount: 2)
    }
    #expect(try await fake.customer.settleUsage(hold: id, amount: 1).outcome == .settled)
    #expect(fake.used("ai_credits") == 1)
  }

  @Test func aClosedHoldReplaysAsClosedAndHoldIDsStayUnique() async throws {
    let clock = Clock()
    let fake = try FakeCustomer(["ai_credits": .metered(limit: 10)], id: "user_1") { clock.now }
    let first = try await fake.customer.holdUsage(
      of: aiCredits, amount: 1, idempotencyKey: "h-1", ttlSeconds: 60)
    let second = try await fake.customer.holdUsage(
      of: aiCredits, amount: 1, idempotencyKey: "h-2", ttlSeconds: 60)
    clock.now += 60
    let third = try await fake.customer.holdUsage(
      of: aiCredits, amount: 1, idempotencyKey: "h-3", ttlSeconds: 60)

    #expect(Set([first.holdID, second.holdID, third.holdID]).count == 3)
    do {
      _ = try await fake.customer.startHold(of: aiCredits, amount: 1, idempotencyKey: "h-1")
      Issue.record("Expected a replayed hold.")
    } catch EntitlerError.usageReplayed {}
  }
}

final class Clock: @unchecked Sendable {
  private let lock = NSLock()
  private var instant = Date(timeIntervalSince1970: 1_790_000_000)

  var now: Date {
    get {
      lock.lock()
      defer { lock.unlock() }
      return instant
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      instant = newValue
    }
  }
}
