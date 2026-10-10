import Entitler
import Foundation

enum Features {
  static let sso = Feature<OnOff>("sso")
}

let returnURL = URL(string: "https://example.com/billing/return")!
let server = try EntitlerServer(key: ProcessInfo.processInfo.environment["ENTITLER_KEY"] ?? "")
let customer = try server.customer("billing-\(UUID().uuidString.prefix(8).lowercased())")
try await customer.register(name: "Mary Jackson")

do {
  let plans = try await customer.plans()
  for held in plans.held {
    let billing = held.billedBy.map { "billed by \($0.rawValue)" } ?? "not billed"
    print("Holds \(held.plan.name), \(billing)")
  }
  for option in plans.options {
    switch option.action {
    case .buy:
      print("Choose \(option.plan.name): \(option.periods.map(\.label).joined(separator: ", "))")
    case .contact:
      print("Contact sales for \(option.plan.name)")
    default:
      print("\(option.plan.name) is unavailable: \(option.reason ?? "")")
    }
  }

  switch try await customer.subscribe(to: "pro", period: "monthly", returnURL: returnURL) {
  case .done(let change):
    print("Now on \(change.plan?.name ?? "no plan"), \(change.effective.rawValue)")
  case .pay(let url):
    print("Send the customer to \(url), then call syncBilling() on the return page")
  case .confirming:
    print("The provider is confirming the payment")
  case .manage(let store):
    print("Change it in the store: \(store.rawValue)")
  case .unknown(let next):
    print("A step this SDK does not know: \(next)")
  }

  let synced = try await customer.syncBilling()
  let fresh = try await customer.plans(revalidate: true)
  print("Synced (changed: \(synced.changed)); holds \(fresh.held.map(\.plan.name))")

  let cancelled = try await customer.cancel()
  print("Cancelled: \(cancelled.changed), \(cancelled.effective.rawValue)")
  let undone = try await customer.undoPendingChange()
  print("Undone: \(undone.changed)")

  do {
    let portal = try await customer.billingPortal(returnURL: returnURL)
    print("Billing portal: \(portal.url)")
  } catch EntitlerError.api(let error) where error.code == .stale {
    print("No provider has billed this customer yet: \(error.message)")
  }

  let deal = try await customer.setPlan(
    to: "pro_basic", period: "monthly", billing: .end, reason: "Invoiced contract",
    actor: "billing-example", idempotencyKey: "deal-\(UUID().uuidString)")
  print("The company moved them to \(deal.plan?.name ?? "no plan")")

  let grant = try await customer.grant(
    Features.sso, days: 14, reason: "Sales trial", actor: "billing-example")
  print("Granted SSO; keep \(grant.grant.id) to revoke it")
  print("SSO: \(await customer.isEntitled(to: Features.sso, default: false, revalidate: true))")
} catch {
  try? await customer.erase()
  throw error
}
try await customer.erase()
