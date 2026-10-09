import Entitler
import Foundation

enum Features {
  static let exportPDF = Feature<OnOff>("export_pdf")
  static let aiCredits = Feature<Metered>("ai_credits")
}

let server = try EntitlerServer(key: ProcessInfo.processInfo.environment["ENTITLER_KEY"] ?? "")
let customer = try server.customer("in-app-\(UUID().uuidString.prefix(8).lowercased())")
try await customer.register(name: "Grace Hopper")

do {
  let client = try EntitlerClient(tokenProvider: {
    try await customer.token().token
  })

  let canExport = await client.me.isEntitled(to: Features.exportPDF, default: false)
  print("Export to PDF: \(canExport ? "yes" : "no")")
  let check = try await client.me.check(Features.aiCredits)
  print("AI credits left: \(check.remaining)")
  try await client.me.recordUsage(of: Features.aiCredits, amount: 1)
} catch {
  _ = try? await customer.delete(erase: true)
  throw error
}
try await customer.delete(erase: true)
