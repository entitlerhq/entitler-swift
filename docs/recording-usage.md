# Recording usage

Usage is recorded on metered features, in whole numbers of the feature's unit from 1 to 2^53 − 1.
Other features answer `400 not_metered`.

## Modes

```swift
let result = try await customer.recordUsage(of: Features.aiCredits, amount: 3)
switch result.outcome {
case .recorded, .duplicate:
  print("Recorded; \(result.remaining.map(String.init(describing:)) ?? "") left")
case .refused:
  print("Refused: \(result.refusal?.rawValue ?? "")")
default:
  break
}
```

- `.gate`, the default, records only if the amount fits the allowance; otherwise it records
  nothing and answers `refused`, with `refusal` `notEntitled` or `overAllowance`. Use it before
  work that must not start without allowance.
- `.observe` always records what happened; `overBy` says how far past the allowance the meter
  went. Use it for work that already happened, such as streamed tokens or minutes.

```swift
try await customer.recordUsage(
  of: Features.aiCredits, amount: 120, mode: .observe, occurredAt: Date().addingTimeInterval(-30))
```

`occurredAt` places the usage in the period it happened in. `register: true` registers a customer
not registered yet, when the credential may register customers. A refusal is an answer, not an
error.

## Idempotency keys from your own work

Every usage write carries an idempotency key. Pass one derived from your own unit of work, such as
a job id or a message id, so a retry from another process or after a restart is recognised:

```swift
try await customer.recordUsage(of: Features.aiCredits, amount: 5, idempotencyKey: "job-\(jobID)")
```

Without one, the SDK generates a key, which protects only its own retries. A replay of a key
records nothing and answers `duplicate`. Reusing a key for a different request answers
`422 idempotency_mismatch`. A refused report stores no key, so the same key works once there is
allowance.

## Holds

A hold reserves an amount against `remaining` until it is settled, released or expires
(`ttlSeconds` 1 to 3600, default 300):

```swift
let hold = try await customer.holdUsage(of: Features.aiCredits, amount: 50)
if let holdID = hold.holdID {
  try await customer.settleUsage(hold: holdID, amount: 32)
}
```

Settle with the real amount, from 0 to the amount held, or release it with `releaseUsage(hold:)`.
Read one back with `hold(id:)`.

## `withHold`

`withHold` holds an amount, runs your work, and settles what the work used:

```swift
let used = try await customer.withHold(of: Features.aiCredits, amount: 500) { hold in
  try await summarise(document).tokens
}
```

- A refused hold never runs the work and throws `EntitlerError.usageRefused(answer)`.
- When the work throws, the hold is released and the error propagates. A failed release goes to
  `onError`, since the hold expires on its own.
- An amount past the hold is recorded in observe mode, with the hold's key plus `:excess`.
- A failed settlement throws an error whose `holdID` names the hold, so you can settle it again.

## Batches from the server

```swift
let result = try await server.recordUsageBatch([
  UsageBatchEvent(customer: "user_1", feature: Features.aiCredits, amount: 3, idempotencyKey: "m-1"),
  UsageBatchEvent(customer: "user_2", feature: Features.aiCredits, amount: 1, idempotencyKey: "m-2"),
])
print(result.recorded, result.duplicates, result.errors)
```

Batches are recorded in observe mode, in requests of at most 500 events, and answer one result
per event in input order.

## Reading usage

```swift
let usage = try await customer.usage()
for meter in usage.features {
  print(meter.feature, meter.used, meter.remaining as Any)
}
for try await event in customer.usageLog() {
  print(event.at, event.feature, event.amount)
}
```

The log is requested a page at a time, only as iteration reaches each page.

Customer and identity tokens may report at most 100 times every 10 seconds per customer; the SDK
retries a `429` as described in [reliability](reliability.md).
