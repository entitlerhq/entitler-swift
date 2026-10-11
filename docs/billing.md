# Billing pages

A paywall and a billing page read one answer, `plans()`, and make the customer's own choices with
`subscribe`, `cancel`, `undoPendingChange`, `billingPortal` and `syncBilling`. These calls are on
`Customer`, so they work on the server and in apps alike, under self-serve rules: a change must be
in the plans the customer can move to, along a self-serve path, or the API refuses it with
`403 not_self_serve`. The project's policies decide when a change takes effect (a downgrade or a
cancel at renewal, an upgrade now).

On the server they need `customers:write`. In an app the token or identity provider must hold
`billing:self` (`403 scope_required` otherwise), and the organisation needs the customer portal
capability (`409 capability_required`). Mint `billing:self` only for people who may buy for the
customer, such as a workspace's owners, not every member.

## The one read

```swift
let plans = try await customer.plans()
for held in plans.held {
  print("Holds", held.plan.name, held.period?.label ?? "", held.billedBy?.rawValue ?? "")
}
for option in plans.options {
  switch option.action {
  case .buy: print("Button: choose", option.plan.name, option.periods.map(\.label))
  case .contact: print("Button: contact sales for", option.plan.name)
  default: print(option.plan.name, "is unavailable:", option.reason ?? "")
  }
}
```

- `action` decides the button: `buy` calls `subscribe`, `contact` is a sales-led move only the
  company can make, and `unavailable` comes with a `reason` for you, the developer.
- `move` says how the option changes the customer's plans (`subscribe`, `upgrade`, `downgrade`,
  `switch`, `add` or `replace`); `impact` lists what it changes for their features and limits.
- `periods` name each billing period by a stable `key` (`monthly`) that writes take, with a
  `label` to show.
- `skus` are the products to buy through StoreKit; see [store purchases](store-purchases.md).
- A held plan's `billedBy` decides where the customer manages it: Apple's or Google's own page for
  a store plan, `billingPortal(returnURL:)` for Stripe.

A check carries the same `move` and `action` on its `upgrades`, so the "Upgrade" button on a
refused export and the paywall share one rule.

## Subscribe, and the next step

```swift
let returnURL = URL(string: "https://example.com/billing/return")!
switch try await customer.subscribe(to: "pro", period: "monthly", returnURL: returnURL) {
case .done(let change):
  print("Now on", change.plan?.name ?? "", change.effective == .now ? "now" : "at renewal")
case .pay(let url):
  print("Send the customer to", url)
case .confirming:
  print("The bank is confirming the payment")
case .manage(let store):
  print("Change it in the store that bills it:", store.rawValue)
case .unknown(let next):
  print("A newer step:", next)
}
```

A plan or add-on is named by its key or public id. An add-on is added, has its quantity set when
held (`quantity:`), or replaces another, as `plans()` lists the move. A customer credential never
charges a saved payment method, so a paid change from an app always answers `pay`. A declined card
stays an error: `402 payment_required` with `payment.status` `declined`.

`subscribe` can fail with `return_url_required`, `payment_required`, `not_self_serve`,
`scope_required`, `customer_not_found` and `capability_required`, and is retried on `503`.

## Return URLs

`returnURL` matters only when the next step is a web page (Stripe Checkout, 3-D Secure); the
provider sends the customer back to it whether they paid or left. A change that needs a page and
has none is refused with `400 return_url_required` before anything changes, so pass one whenever
Stripe may bill the customer.

- A web app passes a page of its own.
- An iOS app billed through Stripe passes a universal link and opens the `pay` step's URL, and the
  billing portal's, in `ASWebAuthenticationSession`, which hands control back at that link. See
  the [SwiftUI guide](swiftui.md).
- An app whose plans Apple or Google bills never calls `subscribe`: see
  [store purchases](store-purchases.md).

## The return page

Back from the provider, call `syncBilling()`, then read the plans again with `revalidate`, so the
customer sees the plan they paid for without waiting for the provider's notification or a kept
answer's `max-age`:

```swift
_ = try await customer.syncBilling()
let fresh = try await customer.plans(revalidate: true)
print(fresh.held.map(\.plan.name))
```

## Cancel and undo

```swift
let cancelled = try await customer.cancel()
print(cancelled.changed ? "Cancelled, \(cancelled.effective.rawValue)" : "Nothing to cancel")
try await customer.cancel(addOn: "sso_addon")
try await customer.undoPendingChange()
try await customer.undoPendingChange(addOn: "sso_addon")
```

Each answers a `PlanChange`: the plan or add-on it leaves the customer on, `effective` (`now` or
`renewal`) and `at`, and `changed`, false when there was nothing to change. Pass `product:` when
the customer holds plans in several products, or `addOn:`, never both. A cancel the customer may
not make, such as of a sales-led plan, fails with `403 not_self_serve`.

## The billing portal

```swift
do {
  let portal = try await customer.billingPortal(returnURL: returnURL)
  print("Open", portal.url)
} catch EntitlerError.api(let error) where error.code == .notFound {
  print("No provider has billed this customer yet")
}
```

The portal shows payment details and invoices; it changes no plan. A customer the provider has
never billed answers `404 not_found`.

The company's own changes (deals, support, verified store purchases) are on the server's customer:
see [company decisions](company-decisions.md).
