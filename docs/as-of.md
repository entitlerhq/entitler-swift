# As-of reads

A server customer's reads take `asOf`, to read the customer as they stood, or will stand, at
another instant:

```swift
let lastMonth = Date().addingTimeInterval(-30 * 86_400)
let check = try await customer.check(Features.exportPDF, asOf: lastMonth)
print(check.asOf, check.entitled)
```

`check`, `isEntitled`, `entitlements`, `plans`, `usage` and `details` take it. The instant is sent
as `Entitler-As-Of` on that request only, in UTC with milliseconds, and the answer is kept in the
cache under a key of its own. An instant outside the years 0001 to 9999 fails before any request
with `Pass asOf as a valid date.`

- Reads at another instant need the organisation's `as_of` capability; without it they answer
  `409 capability_required`.
- Nothing else sends it: not the in-app client, not pricing, and never a write, so a preview can
  never break writes in a live environment. Pricing is always computed now.
- As-of shows the effects of time on the plans, grants and meters already in place (renewals,
  booked moves, grant expiries, meter resets), never a release nobody has rolled out yet, since
  nothing is derived on a schedule. To preview an unreleased change, put a test customer on a
  track for testers.
