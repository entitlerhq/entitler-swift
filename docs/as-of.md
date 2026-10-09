# As-of reads

Read the API as it stood, or will stand, at another instant:

```swift
let lastMonth = try EntitlerServer(
  key: key, options: EntitlerOptions(asOf: Date().addingTimeInterval(-30 * 86_400)))
let check = try await lastMonth.customer("user_123").check(Features.exportPDF)
print(check.asOf, check.entitled)
```

The instant is sent as `Entitler-As-Of` on every request, in UTC with milliseconds. A date that
is not finite fails construction with `Pass asOf as a valid date.`

- Reads at another instant need the organisation's `as_of` capability; without it they answer
  `409 limit_reached`.
- Pricing is always computed now.
- Writes take an instant only in a test environment.
