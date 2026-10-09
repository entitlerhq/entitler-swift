# Changing plans

`plans()` answers the plans and add-ons a customer holds, and every one they can move to from
there: the set an in-app pricing page or a portal renders, and the only set a self-serve change
may reach.

```swift
let plans = try await customer.plans()
for held in plans.held {
  print("Holds", held.plan.name)
}
for option in plans.options {
  let label = option.selfServe ? "Choose" : "Contact sales"
  print(option.plan.name, option.direction.rawValue, option.when.rawValue, label)
  for impact in option.impact {
    print(" ", impact.kind.rawValue, impact.text)
  }
}
```

Each option says how it changes the customer's plans (`move`), whether it is an upgrade, a
downgrade or a move across (`direction`), whether the customer can take it alone (`selfServe`,
from its `mode`), when it applies, what it changes for their features and limits (`impact`), and
the `skus` that buy it. Options behind a sales-led path are shown but not self-serve.

Take an option with the billing calls in [billing](billing.md): `subscribe(to:)` for a plan,
`addAddOn(_:)` for an add-on.

A check names the plans that would give a missing feature:

```swift
let check = try await customer.check(Features.sso)
if !check.entitled, let upgrade = check.upgrades.first {
  print("Available on", upgrade.name)
}
```

An in-app client reads its own plans when the organisation's plan includes the customer portal;
otherwise it answers `409 limit_reached`.
