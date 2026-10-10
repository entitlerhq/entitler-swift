import Entitler
import EntitlerTesting
import Foundation
import Testing

enum Features {
  static let exportPDF = Feature<OnOff>("export_pdf")
  static let aiCredits = Feature<Metered>("ai_credits")
}

func exportReport(for customer: some Customer, job: String) async throws -> Bool {
  guard await customer.isEntitled(to: Features.exportPDF, default: false) else { return false }
  let result = try await customer.recordUsage(
    of: Features.aiCredits, amount: 1, idempotencyKey: "export-\(job)")
  return result.outcome == .recorded
}

func upgrade(_ customer: some Customer, returnURL: URL) async throws -> URL? {
  guard
    case .pay(let url) = try await customer.subscribe(
      to: "pro", period: "monthly", returnURL: returnURL)
  else { return nil }
  return url
}

@Test func exportChargesOneCredit() async throws {
  let fake = FakeCustomer(["export_pdf": true, "ai_credits": .metered(value: 100, used: 97)])
  #expect(try await exportReport(for: fake.customer, job: "42"))
  #expect(fake.writes.map(\.method) == ["recordUsage"])
  #expect(fake.writes.first?.idempotencyKey == "export-42")
  #expect(try await fake.customer.check(Features.aiCredits).remaining == .amount(2))
}

@Test func exportIsRefusedWithoutTheFeature() async throws {
  let fake = FakeCustomer(["ai_credits": .metered(value: 100, used: 0)])
  #expect(try await exportReport(for: fake.customer, job: "43") == false)
  #expect(fake.writes.isEmpty)
}

@Test func upgradeOpensThePaymentPage() async throws {
  let fake = FakeCustomer([:])
  let checkout = URL(string: "https://checkout.example.com/1")!
  fake.answer("subscribe", with: FakeAnswers.subscribeStep(.pay(checkout)))
  #expect(
    try await upgrade(fake.customer, returnURL: URL(string: "https://example.com/back")!)
      == checkout)
  #expect(fake.writes.first?.arguments["plan"] == "pro")
}
