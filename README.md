# Entitler SDK for Swift

The official Swift SDK for [Entitler](https://entitler.co), which lets SaaS teams manage plans,
feature access, usage limits and customer grants. Your servers and apps ask Entitler whether a
customer is entitled to a feature, record metered usage, show pricing and manage subscriptions.
The SDK retries, caches answers, keeps last known answers when Entitler is unreachable, and verifies
offline snapshots, with no dependency on Apple platforms. `EntitlerTesting` fakes a customer for
your own tests.

## Requirements and install

- Swift 6.0 or newer (Xcode 16 or newer).
- iOS 15, macOS 12, tvOS 15, watchOS 8, visionOS 1, or Linux.

Add the package with Swift Package Manager:

```swift Package.swift
dependencies: [
  .package(url: "https://github.com/entitlerhq/entitler-swift.git", from: "0.1.0")
],
targets: [
  .target(name: "App", dependencies: [.product(name: "Entitler", package: "entitler-swift")])
]
```

## Quick start on a server

```swift
import Entitler

let server = try EntitlerServer(key: ProcessInfo.processInfo.environment["ENTITLER_KEY"] ?? "")
let customer = try server.customer("user_123")

try await customer.register(name: "Ada Lovelace", email: "ada@example.com")

if await customer.isEntitled(to: Features.exportPDF, default: false) {
  try await customer.recordUsage(of: Features.aiCredits, amount: 1, idempotencyKey: jobID)
}
```

Every usage report carries a key from your own unit of work (a job, a message, a webhook
delivery), so a retry from anywhere records it once.

`isEntitled(to:default:)` never fails: when Entitler cannot answer, it answers the default you
pass. Use `false` for paid features.

## Two clients

| Client | Built from | Runs | Acts on |
| --- | --- | --- | --- |
| `EntitlerServer` | a secret key | your servers | any customer |
| `EntitlerClient` | a customer token, or a publishable key with or without an identity token | your apps | the signed-in customer, `me`, or signed-out pricing |

Never put a secret key in an app: anything shipped in an app can be read out of it, and a secret
key acts on every customer. Publishable keys start `ent_pk_`, and each client refuses the other
kind, so a server key pasted into an app fails on your machine, never in a shipped app. Your server
mints a short-lived customer token for one customer, and the app's client asks your server for a
new one when it expires:

```swift
let client = try EntitlerClient(tokenProvider: {
  try await api.entitlerToken()
})
let canExport = await client.me.isEntitled(to: Features.exportPDF, default: false)
```

Create one in-app client when a person signs in, keep it app-scoped, and `close()` it at sign-out.
Both clients return a `Customer`, so code that gates features, records usage and offers the
customer's own billing choices takes `some Customer` and is written once.

## Feature constants

Generate typed constants from your catalogue, so each answer is typed to match its feature:

```sh
ENTITLER_KEY=ent_live_… swift run entitler generate --out Sources/App/EntitlerFeatures.swift
swift run entitler snapshot-keys --out Sources/App/SnapshotKeys.json
```

```swift
let check = try await customer.check(Features.aiCredits)
print(check.remaining)
```

Declare one by hand with `Feature<OnOff>("export_pdf")`, `Feature<Config>`, `Feature<Metered>`
or `Feature<FeatureGroup>`. The generator also runs as a command plugin:
`swift package entitler-generate --out Sources/App/EntitlerFeatures.swift`. See
[the generator guide](docs/generator.md).

## Guides

- [Checking access](docs/checking-access.md)
- [Recording usage](docs/recording-usage.md)
- [Pricing pages and visitors](docs/pricing-and-visitors.md)
- [Billing pages](docs/billing.md)
- [Company decisions](docs/company-decisions.md)
- [Store purchases](docs/store-purchases.md)
- [The in-app client](docs/in-app-client.md)
- [Offline snapshots](docs/offline-snapshots.md)
- [Reliability](docs/reliability.md)
- [Errors](docs/errors.md)
- [As-of reads](docs/as-of.md)
- [Tracks](docs/tracks.md)
- [Scopes](docs/scopes.md)
- [Configuration](docs/configuration.md)
- [Testing your app](docs/testing.md)
- [Feature constants and the command-line tool](docs/generator.md)
- [SwiftUI](docs/swiftui.md)
- [Server-side Swift: Vapor and Hummingbird](docs/server-side-swift.md)
- [Versioning and support](docs/versioning.md)

The API reference is on the
[Swift Package Index](https://swiftpackageindex.com/entitlerhq/entitler-swift/documentation/entitler).

## Examples

[`examples/`](examples/README.md) holds runnable programs: [quickstart](examples/quickstart),
[pricing page](examples/pricing-page), [in-app](examples/in-app),
[metered work](examples/metered-work), [offline](examples/offline), [billing](examples/billing),
[generated features](examples/generated-features), a
[SwiftUI view model](examples/swiftui-view-model) and [testing](examples/testing).

## Licence

MIT. See [LICENSE](LICENSE).
