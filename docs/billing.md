# Billing

Billing calls run on the server, on a `ServerCustomer`. Entitler keeps the plan; the payment
provider (Stripe) takes the money.

## Self-serve by default

The customer's own billing calls act as the customer choosing in your interface. Each sends
`selfServe: true`, so the change must be on a self-serve path from their plans, or the API
refuses it with `403 not_self_serve`.

```swift
try await customer.subscribe(to: "pro", period: "Yearly")
try await customer.subscribe(to: "pro", when: .end)
try await customer.addAddOn("sso_addon", quantity: 2)
try await customer.setAddOnQuantity("sso_addon", to: 3)
try await customer.removeAddOn("sso_addon")
try await customer.cancel()
try await customer.undoPendingChange()
```

Name a plan by its key or public id, or by the SKU the customer bought in an app store, which
names its own period:

```swift
try await customer.subscribe(to: .sku(SKU(connector: "apple", ids: ["productId": "pro_yearly"])))
```

## Checkout and the billing portal

```swift
do {
  let checkout = try await customer.checkout(
    "pro", period: "Monthly",
    successURL: URL(string: "https://example.com/welcome")!,
    cancelURL: URL(string: "https://example.com/pricing")!)
  print("Redirect to", checkout.url)
} catch EntitlerError.api(let error) where error.code == .stale {
  print("No payment provider can take it: \(error.message)")
}

let portal = try await customer.billingPortal(returnURL: URL(string: "https://example.com/account")!)
print("Redirect to", portal.url)
```

An environment with no Stripe connection answers both with `409 stale`. A change that waits on a
payment answers `402 payment_required`, with `APIError.payment` naming the page where the customer
pays or confirms it.

`billing()` says whether a provider bills the customer and how, and `providers()` shows what each
provider last reported.

## Vendor actions

Changes you make on the customer's behalf live under `vendor`, so they are never made by accident
and are easy to find in review. They send `selfServe: false`: the vendor may move a customer
anywhere, sales-led plans included.

```swift
try await customer.vendor.subscribe(to: "team")
try await customer.vendor.override(to: "team")
try await customer.vendor.undoOverride()
try await customer.vendor.grant(Features.sso, days: 30, reason: "Pilot")
try await customer.vendor.grant(Features.teamSeats, value: .amount(10))
try await customer.vendor.setMeter(Features.aiCredits, to: 0)
try await customer.vendor.cancelUsage("u_123")
```

An override moves the customer in Entitler only, while the provider keeps billing the plan they
held. `revokeGrant(_:)` ends a grant from now.
