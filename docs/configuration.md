# Configuration

Both clients take `EntitlerOptions`:

```swift
let options = EntitlerOptions(
  baseURL: URL(string: "https://api.entitler.dev")!,
  timeout: 5,
  maxRetries: 3,
  maxRetryDelay: 10,
  staleFor: 3_600,
  onError: { error in print("Entitler:", error) }
)
let configured = try EntitlerServer(
  key: key, cache: MemoryCacheStore(capacity: 5_000), options: options)
```

| Option | Default | Meaning |
| --- | --- | --- |
| `baseURL` | `https://api.entitler.dev` | the API's address; trailing slashes are removed |
| `timeout` | 10 seconds | each attempt's deadline |
| `maxRetries` | 2 | retries after the first attempt |
| `maxRetryDelay` | 10 seconds | the longest `Retry-After` the SDK waits for |
| `staleFor` | 24 hours | how long a kept answer may stand in while Entitler is unreachable |
| `onError` | none | called with each error a fallback absorbed, a hold's failed release or disposal, or a custom store's failure |
| `session` | a session with no `URLCache` that refuses redirects | the transport |

The cache is an initialiser argument, typed per client: `EntitlerServer(key:cache:options:)` takes
any `CacheStore`, such as one backed by Redis, and the in-app initialisers only a
`MemoryCacheStore`. Each defaults to `MemoryCacheStore(capacity: 1_000)`, and `nil` turns caching
off. Neither client takes an as-of instant: a server customer's reads take `asOf` per call
([as-of](as-of.md)).

Pass your own `URLSession` to route requests through a proxy, add instrumentation, or answer them
in tests with a `URLProtocol`. The SDK enforces each attempt's deadline itself, whatever the
session's own timeouts, and still refuses redirects and bypasses `URLCache` on every request.
Closing a client leaves the session open.

`description` on a client shows only its base URL and kind, never the credential.

## Creating the server client on first use

Create one `EntitlerServer` and share it. Where code runs at build time without the key (a
preview, a test target, a build script that imports your module), create it on first use rather
than at start-up, so a missing key fails only the code that needs it:

```swift
enum Entitler {
  static let server = Result { try EntitlerServer(key: ProcessInfo.processInfo.environment["ENTITLER_KEY"] ?? "") }
}
```
