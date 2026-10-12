import Entitler
import Foundation

func show(_ pricing: Pricing) {
  for plan in pricing.plans where plan.kind == .plan {
    print(plan.name, plan.isDefault ? "(free to start)" : "")
    for listing in plan.listings {
      let prices = listing.channels.filter(\.purchasable).compactMap(\.price).map { price in
        "\(Double(price.amount) / 100) \(price.currency.uppercased())"
      }
      let label = listing.period?.label ?? "Once"
      print("  \(label): \(prices.isEmpty ? "Coming soon" : prices.joined(separator: ", "))")
    }
  }
}

let environment = ProcessInfo.processInfo.environment
if let publishable = environment["ENTITLER_PUBLISHABLE_KEY"], !publishable.isEmpty {
  let paywall = try EntitlerClient(key: publishable)
  print("Signed out, in an app:")
  show(try await paywall.pricing())
  paywall.close()
}

let server = try EntitlerServer(key: environment["ENTITLER_KEY"] ?? "")
let visitor = server.newVisitorID()
print("Signed out, on a web page:")
show(try await server.pricing(visitor: visitor))
print("Keep the visitor id in a first-party cookie: \(visitor)")
