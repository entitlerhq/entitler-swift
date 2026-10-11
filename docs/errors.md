# Errors

Every failure is an `EntitlerError`, except cancellation (`CancellationError`), invalid arguments
(`ArgumentError`, raised before any request) and a call on a closed client (`ClientClosedError`).

| Case | When | Carries |
| --- | --- | --- |
| `.api(APIError)` | the API answered with a status other than 2xx, or a 2xx answer this SDK cannot read (`invalid_response`) | `status`, `code`, `message`, `requestID`, `retryAfter`, `idempotencyKey`, `payment` |
| `.connection(ConnectionError)` | no answer arrived | `underlyingError`, `idempotencyKey` |
| `.timeout(TimeoutError)` | an attempt took longer than its timeout | `timeout`, `idempotencyKey` |
| `.token(TokenError)` | a token provider failed or answered an unusable token | `message`, `underlyingError` |
| `.snapshot(SnapshotError)` | a snapshot failed verification | `code`, `message` |
| `.usageRefused(UsageResult)` | `startHold` or `withHold` was refused: no allowance remains | the usage answer, with `refusal` and `upgrades` |
| `.usageReplayed(UsageResult)` | `startHold` or `withHold` was given the key of a hold already settled, released or expired | the usage answer |
| `.usageSettlement(UsageSettlementError)` | a hold's `finish()`, or `withHold` after its work, failed to settle or record the excess | `holdID`, `amount`, `excess`, `underlyingError`, `result` |

Catch one code with a pattern:

```swift
do {
  try await customer.recordUsage(of: Features.aiCredits, amount: 1, idempotencyKey: jobID)
} catch EntitlerError.api(let error) where error.code == .customerNotFound {
  try await customer.register()
} catch EntitlerError.api(let error) {
  print(error.status, error.code, error.message, error.requestID ?? "")
}
```

`ErrorCode` has a static member for every code the API documents, such as `.customerNotFound`,
`.featureNotFound`, `.notSelfServe`, `.scopeRequired`, `.credentialNotAllowed`, `.rateLimited`,
`.stale`, `.idempotencyMismatch`, `.holdExpired`, `.capabilityRequired`, plus the SDK's own
`.httpError` for an answer without a code and `.invalidResponse` for one it cannot read. An unknown
code is kept as it is, never an error, with `isKnown` false. API messages are written for you, the developer, not for
end users: show your own copy.

`isUnreachable` on an `EntitlerError` is true for a connection failure, a timeout, a failing token
provider, a `429`, a `5xx` or an unreadable answer: the moments an offline-capable app falls back
to its [snapshot](offline-snapshots.md).

## Billing codes

| Call | Codes it can answer |
| --- | --- |
| `subscribe` | `return_url_required`, `payment_required` (declined), `not_self_serve`, `scope_required`, `customer_not_found`, `capability_required`, `invalid_body` |
| `cancel`, `undoPendingChange` | `not_self_serve`, `scope_required`, `customer_not_found`, `capability_required` |
| `billingPortal` | `not_found` (never billed), `scope_required`, `capability_required` |
| `syncBilling` | `rate_limited`, `scope_required`, `capability_required`, and `503` while a change is followed |
| `setPlan` | `payment_required`, `billed_elsewhere`, `customer_not_found`, `invalid_body` |
| `setAddOn` | `payment_required`, `not_found`, `customer_not_found`, `invalid_body` |

A failed write's error carries the idempotency key it sent, so you can repeat the call later with
the same key and it will not act twice. A failed settlement carries the hold's id.

No error ever holds a key, a token, a request, its headers or an answer body. A token provider's own
error is kept as it is in `TokenError.underlyingError`; its contents are outside the SDK's
control. The SDK never follows a redirect: any `3xx` other than `304` is an `APIError` with code
`http_error`, so no credential reaches another origin.
