# The in-app client

`EntitlerClient` runs in your iOS, macOS, tvOS, watchOS or visionOS app and acts on the signed-in
customer only, `client.me`, or, with a publishable key alone, reads signed-out pricing. It never
takes a secret key: anything shipped in an app can be read out of it, and a secret key acts on
every customer. Publishable keys start `ent_pk_` and hold product scopes only; the client refuses
any other key at construction, so a server key pasted into an app fails on your machine.

It is built from one of three credentials, and its type says which, so `me` exists only for a
signed-in person, `register()` only with an identity token, and `pricing()` only with a key alone.

## One client per signed-in person

Create the client when a person signs in, keep it where the app keeps state for the session
(app-scoped, not in one screen's view model, so screens share one cache, one token and one
visitor), and close it at sign-out:

```swift
@MainActor
final class Session {
  private(set) var client: EntitlerClient<TokenCredential>?

  func signedIn() throws {
    client = try EntitlerClient(tokenProvider: { try await api.entitlerToken() })
  }

  func signedOut() {
    client?.close()
    client = nil
  }
}
```

`close()` returns at once: calls in flight and the pending token refresh end with
`ClientClosedError`, the cache is dropped, and every later call fails the same way. The next
sign-in creates a new client, so nothing kept for one person is ever answered to another.

## Customer tokens from your server

Your server mints a token for the signed-in customer with the fewest scopes the app needs:

```swift
let issued = try await server.customer(userID).token(
  scopes: [.entitlementsRead, .usageWrite], ttlSeconds: 3_600)
```

Without `scopes` a token holds `entitlements:read` only. Ask for `usageWrite` only when the app
records usage itself, and for `billingSelf` only for people who may buy for the customer (a
workspace's owners, not every member): it lets the app call `subscribe`, `cancel`,
`undoPendingChange`, `billingPortal` and `syncBilling`.

The app asks your server for a token whenever it needs one:

```swift
let tokenClient = try EntitlerClient(tokenProvider: {
  try await api.entitlerToken()
})
let canExport = await tokenClient.me.isEntitled(to: Features.exportPDF, default: false)
try await tokenClient.me.recordUsage(of: Features.aiCredits, amount: 1, idempotencyKey: jobID)
```

The client asks the provider before the first request, again when the kept token expires within
the smaller of 60 seconds and half its lifetime, and after a `401`, which it retries once with the
new token. Concurrent requests share one refresh. A provider that throws, or answers a blank or
unreadable token, fails the call with `EntitlerError.token`, which never holds the token; a cached
answer kept under an earlier token is never answered instead.

A fixed token, `EntitlerClient(token:)`, cannot be refreshed: a `401` fails the call.

## Identity tokens from your sign-in provider

With a sign-in provider registered on your project, the app sends its identity token beside a
publishable key:

```swift
let identityClient = try EntitlerClient(key: "ent_pk_live_…", identityTokenProvider: {
  try await signIn.currentIDToken()
})
try await identityClient.register()
let scopes = try await identityClient.scopes()
print(scopes.registration == true ? "New people may register" : "Registration is closed")
```

Call `register()` after each sign-in: an existing customer is answered without being created again.
It fails with `403 registration_closed` when the provider does not let people register themselves.
The customer's id is `<provider id>:<subject>`; your server acts on them with that id.

Pick a provider whose tokens the device can refresh. Sign in with Apple's identity tokens last ten
minutes and cannot be refreshed on the device, so put a provider that refreshes its own, such as
Firebase Auth, in front of it.

## Signed-out pricing

A paywall shown before sign-in reads pricing with a publishable key alone:

```swift
let pricingClient = try EntitlerClient(key: "ent_pk_live_…")
let pricing = try await pricingClient.pricing()
print(pricing.plans.map(\.name))
```

See [pricing pages and visitors](pricing-and-visitors.md).

## The signed-in customer's id

```swift
if let id = await tokenClient.me.id {
  print("Signed in as", id)
}
```

It is `nil` until the first answer names the customer.

## What the in-app client cannot do

It has no feature list, no batches and no company decisions, since its credentials may not make
them. A route that refuses the credential answers `403 credential_not_allowed`, which is never
retried or refreshed. Its cache lives in memory only: a store kept across launches would never be
read again, since each token is a new principal. Only [snapshots](offline-snapshots.md) survive a
relaunch.
