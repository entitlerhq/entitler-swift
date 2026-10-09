# Configuration

Both clients take `EntitlerOptions`:

```swift
let options = EntitlerOptions(
  baseURL: URL(string: "https://api.entitler.dev")!,
  timeout: 5,
  maxRetries: 3,
  maxRetryDelay: 10,
  cache: MemoryCacheStore(capacity: 5_000),
  staleFor: 3_600,
  onError: { error in print("Entitler:", error) },
  session: .shared
)
let configured = try EntitlerServer(key: key, options: options)
```

| Option | Default | Meaning |
| --- | --- | --- |
| `baseURL` | `https://api.entitler.dev` | the API's address; trailing slashes are removed |
| `timeout` | 10 seconds | each attempt's deadline |
| `maxRetries` | 2 | retries after the first attempt |
| `maxRetryDelay` | 10 seconds | the longest `Retry-After` the SDK waits for |
| `cache` | `MemoryCacheStore(capacity: 1_000)` | the answer cache, or `nil` |
| `staleFor` | 24 hours | how long a kept answer may stand in while Entitler is unreachable |
| `onError` | none | called with each error a fallback absorbed |
| `asOf` | none | read at another instant ([as-of](as-of.md)) |
| `session` | `URLSession.shared` | the transport |

Pass your own `URLSession` to route requests through a proxy, add instrumentation, or answer them
in tests with a `URLProtocol`. The SDK enforces each attempt's deadline itself, whatever the
session's own timeouts.

`description` on a client shows only its base URL and kind, never the credential.
