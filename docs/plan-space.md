# Plan space and upgrades

The plan space is every plan and add-on a customer could move to from the plans they hold: the set
an in-app pricing page or a portal renders, and the only set a self-serve change may reach.

```swift
let space = try await customer.planSpace()
for held in space.held {
  print("Holds", held.plan.name)
}
for option in space.options {
  let label = option.selfServe ? "Choose" : "Contact sales"
  print(option.plan.name, option.direction.rawValue, option.when.rawValue, label)
  for impact in option.impact {
    print(" ", impact.kind.rawValue, impact.text)
  }
}
```

Each option says how it changes the customer's plans (`move`), whether it goes up, down or across,
whether the customer can take it alone (`selfServe`), when it applies, and what it changes.
Options behind a sales-led path are shown but not self-serve.

A check names the plans that would give a missing feature:

```swift
let check = try await customer.check(Features.sso)
if !check.entitled, let upgrade = check.upgrades.first {
  print("Available on", upgrade.name)
}
```

An in-app client reads its own plan space when the organisation's plan includes the customer
portal; otherwise it answers `409 limit_reached`.
