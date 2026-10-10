# Reliability

## Timeouts and cancellation

Each attempt has a deadline, `timeout` (10 seconds by default), covering the whole attempt from
connecting to the last byte. `URLRequest.timeoutInterval` is only an idle timeout, so the SDK races
each attempt against a timer; losing throws `EntitlerError.timeout`. Every method takes `timeout:`
to override it for one call.

Cancelling the task cancels the request and any retry wait at once, and throws `CancellationError`.

## Retries

Connection failures, timeouts and answers `408`, `429`, `500`, `502`, `503` and `504` are retried,
for reads and writes alike, up to `maxRetries` times (2 by default). Every write carries an
idempotency key, the same on every attempt, so a retried write never acts twice.

The SDK waits as long as `Retry-After` asks (seconds or an HTTP date). When it asks for longer
than `maxRetryDelay` (10 seconds), the call fails at once and the error's `retryAfter` says when to
try again. Otherwise it waits a random time up to `min(8, 0.5 × 2^n)` seconds before retry `n`.

## The answer cache

Checks, entitlement lists, customer plans and customer pricing, and on the server `pricing()` and
`features()`, go through a cache of 1,000 answers in memory by default.

- An answer whose age (time since receipt plus its `Age` header) is below its `max-age`, and
  that has no `no-cache`, answers without a request.
- Every write to a customer, except minting tokens and snapshots and opening the billing portal,
  moves that customer's write generation. Answers kept before it, or read while it moved, are
  revalidated.
- `revalidate: true` skips a fresh answer and revalidates it, for a page that knows the customer
  just changed.
- Otherwise the SDK sends the kept `ETag` in `If-None-Match`; a `304` answers the kept body, and
  headers it sends replace the kept ones.
- `no-store` answers are never kept.

The SDK's cache is the only cache: the default `URLSession` has no `URLCache`, and every request,
an injected session's included, ignores the platform's cache.

Keys are the SHA-256 of the request, the kind of credential, a SHA-256 of the credential itself,
the as-of instant and the visitor; they never hold a credential, and a refreshed token keys its
own answers. Entries are plain values (`CacheEntry`, format 1), private to this SDK. A server shares
answers between processes with a store of its own, such as Redis. A store that throws counts as a
miss or skips the write, and the error goes to `onError`. `timeToLive` is `staleFor` plus the
answer's `max-age`: stores that expire entries should expire them after that. Custom stores are for
`EntitlerServer` only: an in-app client's principal changes with every token, so a store kept across
launches would never answer it again. In apps, only [snapshots](offline-snapshots.md) survive a
relaunch.

```swift
actor DiskStore: CacheStore {
  let directory = URL(fileURLWithPath: "/tmp/entitler", isDirectory: true)

  func entry(forKey key: String) async throws -> CacheEntry? {
    let file = directory.appendingPathComponent(key)
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    return try JSONDecoder().decode(CacheEntry.self, from: Data(contentsOf: file))
  }

  func setEntry(_ entry: CacheEntry, forKey key: String, timeToLive: TimeInterval) async throws {
    try JSONEncoder().encode(entry).write(to: directory.appendingPathComponent(key))
  }
}
```

```swift
let cachedServer = try EntitlerServer(key: key, cache: DiskStore())
print(cachedServer)
```

Pass `cache: nil` to turn caching off.

## Stale answers

When a read through the cache fails because Entitler is unreachable (a connection failure, a
timeout, `429`, a `5xx`, or a 2xx answer this SDK cannot read, such as a captive portal's page,
after retries) and the cache holds an answer younger than `staleFor` (24 hours), the read answers
it with `stale` set to `true` and passes the error to `onError`:

```swift
let options = EntitlerOptions(onError: { error in
  print("Entitler fallback:", error)
})
print(options.staleFor)
```

For the next 30 seconds (or the failed answer's `Retry-After`, if longer), reads with a kept answer
answer it at once, still `stale`, without a request; then one request tests the API again. So an
outage costs one slow read, not one per call.

Stale answers never cross credentials: an answer kept under another credential, a token the same
client held before included, is never answered. So when the in-app client's token provider fails
(offline, typically), the read fails with its `TokenError` and `isEntitled` answers its default.
Apps that must work offline, or after a relaunch, verify a [snapshot](offline-snapshots.md), and
fall back to it when `error.isUnreachable` is true.

`onError` never changes a call's answer or its error. Every other failure throws as usual.
`isEntitled` goes further and never fails; see [checking access](checking-access.md).
