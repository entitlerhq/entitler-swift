import Entitler
import Foundation

enum Features {
  static let exportPDF = Feature<OnOff>("export_pdf")
  static let aiCredits = Feature<Metered>("ai_credits")
}

let server = try EntitlerServer(key: ProcessInfo.processInfo.environment["ENTITLER_KEY"] ?? "")
let customer = try server.customer("quickstart-\(UUID().uuidString.prefix(8).lowercased())")

try await customer.register(name: "Ada Lovelace", email: "ada@example.com")

do {
  let canExport = await customer.isEntitled(to: Features.exportPDF, default: false)
  print("Export to PDF: \(canExport ? "yes" : "no")")

  let result = try await customer.recordUsage(
    of: Features.aiCredits, amount: 1, idempotencyKey: "quickstart-\(UUID().uuidString)")
  print(
    "AI credits: \(result.outcome), \(result.remaining.map(String.init(describing:)) ?? "no meter") left"
  )
} catch {
  try? await customer.erase()
  throw error
}
try await customer.erase()
