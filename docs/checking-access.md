# Checking access

Ask Entitler whether a customer is entitled to a feature. Entitler decides, from the customer's
plans, add-ons, grants and groups; the SDK never re-derives the answer from a value.

## `isEntitled`: a boolean that never fails

```swift
if await customer.isEntitled(to: Features.exportPDF, default: false) {
  try await exportPDF()
}
```

When Entitler cannot answer (no connection, a timeout, an outage, a missing feature), the call
answers `default` and passes the error to `onError`. A stale answer from the cache counts as an
answer (see [reliability](reliability.md)). Cancelling the task answers `default` without calling
`onError`.

Choose the default deliberately:

- **Fail closed** with `false` for paid features, so an outage never gives them away.
- **Fail open** with `true` only where losing a sale or blocking a customer costs more than giving
  the feature away for a while.

## `check`: the full answer

```swift
let check = try await customer.check(Features.aiCredits)
print(check.entitled, check.used, check.remaining, check.resetsAt as Any)

let sso = try await customer.check(Features.sso)
if !sso.entitled {
  print("Upgrade to", sso.upgrades.map(\.name))
}
```

A metered constant answers a `MeteredCheck`, whose `used`, `held` and `remaining` are never `nil`;
every other constant answers a `Check`. A plain key answers a `Check`:
`try await customer.check("export_pdf")`.

`value` is a `FeatureValue`: `.on`, `.amount(n)` or `.unlimited`.

## Every entitlement at once

```swift
let entitlements = try await customer.entitlements()
if entitlements.has(Features.teamEssentials) {
  print("Team plan features are on")
}
let seats = entitlements[Features.teamSeats]?.value
```

Groups are in the list with Entitler's decision, so `has` never expands a group itself. `has`
answers `false` for a feature the list does not hold.

Checks, entitlement lists, plan space and pricing go through the [answer cache](reliability.md).
