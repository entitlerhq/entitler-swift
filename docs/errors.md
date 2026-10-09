# Errors

Every failure is an `EntitlerError`, except cancellation (`CancellationError`) and invalid
arguments (`ArgumentError`, raised before any request).

| Case | When | Carries |
| --- | --- | --- |
| `.api(APIError)` | the API answered with a status other than 2xx | `status`, `code`, `message`, `requestID`, `retryAfter`, `idempotencyKey`, `payment`, `listingGaps`, `listingProblems` |
| `.connection(ConnectionError)` | no answer arrived | `underlyingError`, `idempotencyKey` |
| `.timeout(TimeoutError)` | an attempt took longer than its timeout | `timeout`, `idempotencyKey` |
| `.token(TokenError)` | a token provider failed or answered an unusable token | `message`, `underlyingError` |
| `.snapshot(SnapshotError)` | a snapshot failed verification | `code`, `message` |
| `.usageRefused(UsageResult)` | `withHold` was refused its hold | the usage answer |

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
the same key and it will not act twice. A failed settlement in `withHold` carries the hold's id in
`holdID`.

No error ever holds a key, a token or a request or answer body.
