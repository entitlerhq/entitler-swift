# Pricing pages and visitors

## A signed-out pricing page

An app's signed-out paywall reads pricing with a publishable key alone, with no backend route:

```swift
let paywall = try EntitlerClient(key: "ent_pk_live_…")
let pricing = try await paywall.pricing()
for plan in pricing.plans where plan.kind == .plan {
  for listing in plan.listings {
    let purchasable = listing.channels.filter(\.purchasable)
    print(plan.name, listing.period?.label ?? "", purchasable.isEmpty ? "Coming soon" : "On sale")
  }
}
```

A web page's server reads it with the server client and the visitor's id:

```swift
let pricing = try await server.pricing(visitor: visitorID)
```

Each period lists every payment connection with `purchasable`, the ids to buy it with and, for
Stripe, the price. A plan without a listing still shows, so the page can say "Coming soon".

## Visitors keep their experiment arm

An experiment shows each visitor one arm. Keep a visitor id per person so they see the same arm on
every page and after signing up:

```swift
let visitorID = server.newVisitorID()
```

Keep it in a first-party cookie, and pass it to `pricing(visitor:)`, to `customer.pricing(visitor:)`
and to `register(visitor:)` when the person signs up. A visitor id is 16 to 64 letters, numbers,
hyphens or underscores (`visitorIDPattern`); `newVisitorID()` makes one from 24 random bytes.

The server never generates or keeps a visitor itself, because one server serves many visitors.

The in-app client keeps its own visitor id and sends it on every request: on Apple platforms in
`UserDefaults.standard` under `entitler.visitor`, and on Linux for the client's lifetime. Pass
`visitor:` to use one you keep yourself, for example in an app group:

```swift
let shared = UserDefaults(suiteName: "group.com.example.app")?.string(forKey: "visitor")
let client = try EntitlerClient(tokenProvider: { try await api.entitlerToken() }, visitor: shared)
```

## The visitor through sign-up

The visitor's path through sign-up keeps their arm: a signed-out screen reads the stored visitor,
with no client, and sends it with the app's own sign-up request; your server passes it to
`register(visitor:)`. Reset it at sign-out and at account deletion, so the next person on a shared
device is never linked to the last:

```swift
let signUpVisitor = storedVisitorID()
resetStoredVisitor()
```

Both functions exist on Apple platforms, where the SDK keeps the visitor itself.

## A signed-in customer's pricing

```swift
let pricing = try await customer.pricing()
```

It answers the plans on sale to the customer through their track, through the cache.
