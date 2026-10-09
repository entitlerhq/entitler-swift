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

Checks, entitlement lists, plan space and customer pricing, and on the server `pricing()` and
`features()`, go through a cache of 1,000 answers in memory by default.

- An answer younger than its `max-age` answers without a request, unless this client has written
  to that customer since.
- Otherwise the SDK sends the kept `ETag` in `If-None-Match`; a `304` answers the kept body.
- `no-store` answers are never kept.

Keys are SHA-256 hashes of the request and the credential's principal, and never hold a
credential. Share answers between processes, or keep them across launches, with your own store:

```swift
actor DiskStore: CacheStore {
  func entry(forKey key: String) async -> CacheEntry? {
    guard let data = FileManager.default.contents(atPath: "/tmp/entitler/\(key)") else { return nil }
    return try? JSONDecoder().decode(CacheEntry.self, from: data)
  }

  func setEntry(_ entry: CacheEntry, forKey key: String) async {
    let data = try? JSONEncoder().encode(entry)
    FileManager.default.createFile(atPath: "/tmp/entitler/\(key)", contents: data)
  }
}
```

```swift
let cachedServer = try EntitlerServer(key: key, options: EntitlerOptions(cache: DiskStore()))
```

Pass `cache: nil` to turn caching off.

## Stale answers

When a read through the cache fails because Entitler is unreachable (a connection failure, a
timeout, `429` or a `5xx`, after retries) and the cache holds an answer younger than `staleFor`
(24 hours), the read answers it with `stale` set to `true` and passes the error to `onError`:

```swift
let options = EntitlerOptions(onError: { error in
  print("Entitler fallback:", error)
})
```

Every other failure throws as usual. `isEntitled` goes further and never fails; see
[checking access](checking-access.md).
