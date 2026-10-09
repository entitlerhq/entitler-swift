# Errors

Every failure is an `EntitlerError`, except cancellation (`CancellationError`) and invalid
arguments (`ArgumentError`, raised before any request).

| Case | When | Carries |
| --- | --- | --- |
| `.api(APIError)` | the API answered with a status other than 2xx, or a 2xx answer this SDK cannot read (`invalid_response`) | `status`, `code`, `message`, `requestID`, `retryAfter`, `idempotencyKey`, `payment`, `listingGaps`, `listingProblems` |
| `.connection(ConnectionError)` | no answer arrived | `underlyingError`, `idempotencyKey` |
| `.timeout(TimeoutError)` | an attempt took longer than its timeout | `timeout`, `idempotencyKey` |
| `.token(TokenError)` | a token provider failed or answered an unusable token | `message`, `underlyingError` |
| `.snapshot(SnapshotError)` | a snapshot failed verification | `code`, `message` |
| `.usageRefused(UsageResult)` | `withHold` was refused its hold, or replayed a finished one | the usage answer |
| `.usageSettlement(UsageSettlementError)` | `withHold`'s work ran, then settling or recording the excess failed | `holdID`, `amount`, `excess`, `underlyingError`, `result` |

Catch one code with a pattern:

```swift
do {
  try await customer.recordUsage(of: Features.aiCredits, amount: 1)
} catch EntitlerError.api(let error) where error.code == .customerNotFound {
  try await customer.register()
} catch EntitlerError.api(let error) {
  print(error.status, error.code, error.message, error.requestID ?? "")
}
```

`ErrorCode` has a static member for every code the API documents, such as `.customerNotFound`,
`.featureNotFound`, `.notSelfServe`, `.scopeRequired`, `.credentialNotAllowed`, `.rateLimited`,
`.stale`, `.idempotencyMismatch`, `.holdExpired`, plus the SDK's own `.httpError` for an answer
without a code. An unknown code is kept as it is, never an error.

A failed write's error carries the idempotency key it sent, so you can repeat the call later with
the same key and it will not act twice. A failed settlement in `withHold` carries the hold's id.

No error ever holds a key, a token, a request, its headers or an answer body. A token provider's own
error is kept as it is in `TokenError.underlyingError`; its contents are outside the SDK's
control. The SDK never follows a redirect: any `3xx` other than `304` is an `APIError` with code
`http_error`, so no credential reaches another origin.
