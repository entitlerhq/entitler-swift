# Recording usage

Usage is recorded on metered features, in whole numbers of the feature's unit from 1 to 2^53 − 1;
the SDK refuses other amounts before any request. Usage methods take only `Feature<Metered>`
constants: declare a plain key as `Feature<Metered>("ai_credits")`.

## Idempotency keys name the event

Every report and hold takes your own idempotency key, and the SDK never makes one up for them: a
generated key protects only its own retries, while a retry from the browser, another process or a
restart would charge twice. Take the key from your own unit of work:

```swift
try await customer.recordUsage(of: Features.aiCredits, amount: 5, idempotencyKey: "job-\(jobID)")
```

The API keeps each key for ever, per customer. So a key names an event (this message, this export
request, this webhook delivery), never an object whose state changes (a document, a deal): a key
reused after the object changes replays the first answer and records nothing. A replay answers
`duplicate` with `replayed` true. Reusing a key for a different request answers
`422 idempotency_mismatch`. A refused report stores no key, so the same key works once there is
allowance.

## Modes

```swift
let result = try await customer.recordUsage(
  of: Features.aiCredits, amount: 3, idempotencyKey: "message-\(jobID)")
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
  went. Use it for work that already happened, such as streamed tokens, bandwidth or minutes.

```swift
try await customer.recordUsage(
  of: Features.aiCredits, amount: 120, idempotencyKey: "stream-\(jobID)", mode: .observe,
  occurredAt: Date().addingTimeInterval(-30))
```

`occurredAt` places the usage in the period it happened in. `register: true` registers a customer
not registered yet, when the credential may register customers. A refusal is an answer, not an
error.

## Streamed work: `startHold`

`startHold` holds an amount against the allowance and answers a `Hold` before any work starts, so
a route can answer a refusal before it streams:

```swift
let hold: Hold
do {
  hold = try await customer.startHold(
    of: Features.aiCredits, amount: 2_000, idempotencyKey: "message-\(jobID)")
} catch EntitlerError.usageRefused(let answer) {
  print("Out of credits; upgrade to", answer.upgrades.first?.name ?? "a bigger plan")
  return
}
try await hold.run { hold in
  try hold.use(0)
  for try await chunk in stream {
    try hold.use(chunk.tokensSoFar)
  }
}
```

- `use(_:)` reports the total used so far, with no request; a later call replaces an earlier one.
  Work that reports as it goes calls `use(0)` before it starts, so a failure that used nothing
  frees the whole hold.
- `finish()` ends the work however it ended and charges for the work that happened: it settles the
  amount reported, or the held amount when none was. An amount past the hold is recorded in
  observe mode under the hold's key plus `:excess`, so the key is at most 193 characters. When the
  hold expired first, the whole amount is recorded that way, since the work happened.
- `release()` frees the hold, recording nothing, for work that never ran.
- `run(_:)` is the scope that disposes of the hold: it calls `finish()` when the closure returns;
  when it throws or the task is cancelled, it settles the amount reported, or releases the hold
  when none was, and rethrows. A disconnect after 3,000 tokens charges for 3,000 tokens.
- Only the first of `finish()`, `release()` and `run(_:)` acts; a later call answers its result.
  Each runs in a task of its own, so a cancelled request still settles or releases.
- Swift cannot await in `deinit` or `defer`: a hold never finished, released or run expires after
  its `ttlSeconds` (1 to 3600, default 300), recording nothing.
- `isDuplicate` is true when another caller holds the same key and may be doing the same work, so
  you can wait for that caller's result instead of paying for the work twice.

A refused hold throws `EntitlerError.usageRefused(answer)`. A key whose hold was already settled,
released or expired throws `EntitlerError.usageReplayed(answer)`: the work it stands for already
happened, so show that work's result, never an upgrade prompt to a paying customer.

When `finish()` cannot settle or record the excess after its retries, it throws
`EntitlerError.usageSettlement(error)`: keep the output, call `settleUsage(hold:amount:)` with its
`holdID` and `amount` before the hold expires, and record its `excess` under the same `:excess`
key. A failure while `run(_:)` disposes of a hold goes to `onError` instead.

## Work inside one call: `withHold`

`withHold` is `startHold` then `run`, and answers the work's own result:

```swift
let summary = try await customer.withHold(
  of: Features.aiCredits, amount: 500, idempotencyKey: "summary-\(jobID)"
) { hold in
  let answer = try await summarise(document)
  try hold.use(answer.tokens)
  return answer.summary
}
```

A `usageSettlement` error from it carries the work's result in `result`.

The accounting happens exactly once per key, but the work does not: two callers using the same key
at the same time may both run it, and the second sees `isDuplicate`. Coordinate the work yourself
when it must run once.

While a hold is open, `remaining` drops by the whole amount held, and rises when it settles: a
live meter shows `held` apart.

## Holds settled elsewhere

`holdUsage(of:amount:idempotencyKey:ttlSeconds:)` answers the hold's `UsageResult` for a hold
another process settles with `settleUsage(hold:amount:)` or frees with `releaseUsage(hold:)`.
Settling the same amount again answers `duplicate`; releasing twice is safe.

## Batches from the server

```swift
let result = try await server.recordUsageBatch([
  UsageBatchEvent(customer: "user_1", feature: Features.aiCredits, amount: 3, idempotencyKey: "m-1"),
  UsageBatchEvent(customer: "user_2", feature: Features.aiCredits, amount: 1, idempotencyKey: "m-2"),
])
print(result.recorded, result.duplicates, result.errors)
```

Batches are recorded in observe mode, in requests of at most 500 events, and answer one result per
event in input order, each with its idempotency key. The call never throws for an event or a
request: an event the SDK refuses itself (a blank customer, an amount out of range, an invalid key)
is answered `error` without being sent, and a request that fails after its retries answers its
events `error` (code `connection_failed` or `timed_out` when no answer arrived) while the next
request still goes. Each request's `Idempotency-Key` derives from its events, so resending the
same events replays the first answer, with `replayed` true. Resend the events answered `error`:
their keys make any resend safe.

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

## Reports from apps

Reports and holds sent with customer and identity tokens count towards 100 every 10 seconds per
customer, shared by all of that customer's devices; settlements and releases do not count. The SDK
retries a `429` as [reliability](reliability.md) describes. Counting on a device is advisory: a
modified app can skip it, so only work done on your server can be enforced.
