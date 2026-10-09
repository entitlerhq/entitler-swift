import Entitler
import Foundation

let server = try EntitlerServer(key: ProcessInfo.processInfo.environment["ENTITLER_KEY"] ?? "")
let visitor = server.newVisitorID()
let pricing = try await server.pricing(visitor: visitor)

for plan in pricing.plans where plan.kind == .plan {
  print(plan.name, plan.isDefault ? "(free to start)" : "")
  for period in plan.periods {
    let channels = plan.listings.first { $0.period == period.label }?.channels ?? []
    let prices = channels.filter(\.purchasable).compactMap(\.price).map { price in
      "\(Double(price.amount) / 100) \(price.currency.uppercased())"
    }
    print("  \(period.label): \(prices.isEmpty ? "Coming soon" : prices.joined(separator: ", "))")
  }
}
print("Keep the visitor id in a first-party cookie: \(visitor)")
