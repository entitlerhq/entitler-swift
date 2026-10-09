# Server-side Swift: Vapor and Hummingbird

Create one `EntitlerServer` when the application starts and share it: it is `Sendable`, and its
cache and connections are shared by every request.

```swift
struct EntitlerService: Sendable {
  let server: EntitlerServer

  init() throws {
    server = try EntitlerServer(key: ProcessInfo.processInfo.environment["ENTITLER_KEY"] ?? "")
  }

  func requireEntitlement(_ feature: Feature<OnOff>, for userID: String) async throws {
    let customer = try server.customer(userID)
    guard await customer.isEntitled(to: feature, default: false) else {
      throw EntitlementRequired(feature: feature.key)
    }
  }

  func token(for userID: String) async throws -> String {
    try await server.customer(userID).token().token
  }
}

struct EntitlementRequired: Error {
  let feature: String
}
```

In Vapor, store the service in `app.storage` or an `Application` extension and call
`requireEntitlement` from a route or an `AsyncMiddleware`, answering `403` for
`EntitlementRequired`. In Hummingbird, keep it in your request context or a `RouterMiddleware`.
Add a route that answers `token(for:)` for the signed-in user, so your apps' token providers can
fetch customer tokens.

Register customers at sign-up and sign-in so Entitler's copy stays current:

```swift
try await service.server.customer(userID).register(name: name, email: email, visitor: visitorCookie)
```
