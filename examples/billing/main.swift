import Entitler
import Foundation

enum Features {
  static let sso = Feature<OnOff>("sso")
}

let server = try EntitlerServer(key: ProcessInfo.processInfo.environment["ENTITLER_KEY"] ?? "")
let customer = try server.customer("billing-\(UUID().uuidString.prefix(8).lowercased())")
try await customer.register(name: "Mary Jackson")

do {
  let plans = try await customer.plans()
  for option in plans.options where option.selfServe {
    print("Could move to \(option.plan.name) (\(option.direction.rawValue))")
  }

  try await customer.subscribe(to: "pro", period: "Monthly")

  do {
    let page = try await customer.checkout(
      "pro", successURL: URL(string: "https://example.com/welcome")!,
      cancelURL: URL(string: "https://example.com/pricing")!)
    print("Send the customer to \(page.url)")
  } catch EntitlerError.api(let error) where error.code == .stale {
    print("No payment provider can take this checkout: \(error.message)")
  }

  try await customer.vendor.grant(Features.sso, days: 14, reason: "Sales trial")
  print("SSO: \(await customer.isEntitled(to: Features.sso, default: false))")
} catch {
  _ = try? await customer.delete(erase: true)
  throw error
}
try await customer.delete(erase: true)
