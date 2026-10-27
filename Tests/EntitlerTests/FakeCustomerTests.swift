import Entitler
import EntitlerTesting
import Foundation
import Testing

@Suite struct FakeCustomerTests {
  let aiCredits = Feature<Metered>("ai_credits")

  @Test func checksAnswerTheValues() async throws {
    let fake = FakeCustomer([
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
    let fake = FakeCustomer(["ai_credits": .metered(limit: 100, used: 97)])
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
    let fake = FakeCustomer(["ai_credits": .metered(limit: 1_000)])
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

  @Test func aHoldThatDoesNotFitIsRefused() async throws {
    let fake = FakeCustomer(["ai_credits": .metered(limit: 100, used: 90)])
    do {
      _ = try await fake.customer.startHold(of: aiCredits, amount: 20, idempotencyKey: "m-1")
      Issue.record("Expected a refusal.")
    } catch EntitlerError.usageRefused(let error) {
      #expect(error.result.refusal == .overAllowance)
    }
  }
}
