# The in-app client

`EntitlerClient` runs in your iOS, macOS, tvOS, watchOS or visionOS app and acts on the signed-in
customer only, `client.me`. It never takes a secret key: anything shipped in an app can be read
out of it, and a secret key acts on every customer.

It is built from one of two credentials, and the type says which, so `register()` exists only
where it works.

## Customer tokens from your server

Your server mints a token for the signed-in customer:

```swift
let issued = try await server.customer(userID).token(ttlSeconds: 3_600)
```

The app asks your server for one whenever it needs it:

```swift
let client = try EntitlerClient(tokenProvider: {
  try await api.entitlerToken()
})
let canExport = await client.me.isEntitled(to: Features.exportPDF, default: false)
try await client.me.recordUsage(of: Features.aiCredits, amount: 1)
```

The client asks the provider before the first request, again when the kept token expires within
60 seconds, and after a `401`, which it retries once with the new token. Concurrent requests share
one refresh. A provider that throws, or answers a blank or unreadable token, fails the call with
`EntitlerError.token`, which never holds the token.

A fixed token, `EntitlerClient(token:)`, cannot be refreshed: a `401` fails the call.

## Identity tokens from your sign-in provider

With a sign-in provider registered on your project (such as Sign in with Apple or Google), the app
sends its identity token beside a publishable key that holds only product scopes:

```swift
let identityClient = try EntitlerClient(key: "pk_live_…", identityTokenProvider: {
  try await signIn.currentIDToken()
})
try await identityClient.register()
let scopes = try await identityClient.scopes()
print(scopes.registration == true ? "New people may register" : "Registration is closed")
```

The customer's id is `<provider id>:<subject>`; your server acts on them with that id.

## The signed-in customer's id

```swift
if let id = await client.me.id {
  print("Signed in as", id)
}
```

It is `nil` until the first answer names the customer.

## What the in-app client cannot do

It has no signed-out pricing, no feature list and no batches, since neither credential may read
them: serve signed-out pricing from your server. A route that refuses the credential answers
`403 credential_not_allowed`, which is never retried or refreshed.
