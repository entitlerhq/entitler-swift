# Testing your app

Test your gating and billing code without the network, in one of two ways. Use your test
framework's assertions where these examples use `assert`; the [testing example](../examples/testing)
uses Swift Testing. Both live in the
`EntitlerTesting` library, which only your test targets depend on, so your app never ships it:

```swift Package.swift
.testTarget(
  name: "AppTests",
  dependencies: ["App", .product(name: "EntitlerTesting", package: "entitler-swift")]
)
```

## A fake customer

`FakeCustomer` holds a `ServerCustomer` that makes no request. Pass its `customer` to the code
under test, wherever that code takes `some Customer`:

```swift
import EntitlerTesting

func exportChargesOneCredit() async throws {
  let fake = FakeCustomer(["export_pdf": true, "ai_credits": .metered(value: 100, used: 97)])
  let customer = fake.customer
  if await customer.isEntitled(to: Features.exportPDF, default: false) {
    try await customer.recordUsage(of: Features.aiCredits, amount: 1, idempotencyKey: "export-1")
  }
  let remaining = try await customer.check(Features.aiCredits).remaining
  assert(fake.writes.map(\.method) == ["recordUsage"])
  assert(remaining == .amount(2))
}
```

- Reads answer complete checks and entitlement lists from the values: `true` is on, `false` is
  off, a whole number an amount, `.unlimited`, or `.metered(value:used:)` a meter. A key it does
  not hold answers `404 feature_not_found`, so `isEntitled` answers its default.
- Usage writes move the meters by Entitler's rules: a gated report past the allowance is refused,
  holds settle and release, and a reused key replays the first answer.
- `plans:` and `pricing:` set what `plans()` and `pricing()` answer, built with `FakeAnswers`.
- Every write is recorded in `writes`, in order, with its method, its arguments as text and its
  idempotency key. Writes it does not model answer a plain success: `subscribe` a `done` step made
  now, `setPlan` and the other billing writes a `PlanChange` made now.
- `answer(_:with:status:)` replaces one method's answer:

```swift
func paywallOpensCheckout() async throws {
  let fake = FakeCustomer([:])
  fake.answer(
    "subscribe", with: FakeAnswers.subscribeStep(.pay(URL(string: "https://checkout.test")!)))
  let step = try await fake.customer.subscribe(to: "pro", period: "monthly")
  assert(step == .pay(URL(string: "https://checkout.test")!))
}
```

## A fake transport

Code that builds its own client takes a `URLSession` whose `URLProtocol` answers requests. Build
each body with `FakeAnswers`, which writes complete JSON, so a fixture missing one field never
decodes as `invalid_response` and passes a test for the wrong reason:

```swift
let body = FakeAnswers.check(feature: "export_pdf", entitled: true, value: .on)
print(String(decoding: body, as: UTF8.self))
```

Give the client under test the settings tests need: `maxRetries: 0`, so a refused request fails at
once, and `cache: nil`, so one test's answer never serves another:

```swift
let testClient = try EntitlerServer(
  key: "ent_test_fake", cache: nil, options: EntitlerOptions(maxRetries: 0, session: .shared))
print(testClient)
```

Retry waits and timeouts use the real clock: keep `timeout` short in tests that exercise them.
