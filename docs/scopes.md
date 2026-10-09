# Scopes

The server decides what a credential may do. The SDK never refuses a call itself: a missing scope
comes back as `403 scope_required`, and no request waits on a scope lookup.

Ask which scopes a client holds, to decide what to show:

```swift
let scopes = try await server.scopes()
if scopes.contains(.customersWrite) {
  print("This key can change plans")
}
```

Each call asks again, so a newly granted scope shows without a restart. For an identity client,
`registration` says whether the sign-in provider lets a new person register.

| Scope | Lets a credential |
| --- | --- |
| `plans:read` | read pricing and the feature list |
| `entitlements:read` | check features, list entitlements, read customer plans and pricing, mint snapshots |
| `usage:read` | read usage and holds |
| `usage:write` | record usage, hold, settle and release |
| `customers:register` | register customers |
| `customers:read` | list and read customers, billing and providers |
| `customers:write` | create, change and delete customers, billing, vendor actions |
| `customers:profile` | change customers' names, emails and metadata |
| `customers:sample` | replace the sample customers |
| `tokens:mint` | mint customer tokens |
| `plans:write` | change the catalogue |
| `plans:release` | release the catalogue |
| `tracks:manage` | manage tracks |
| `tracks:promote` | promote tracks |
| `tracks:assign` | put customers on tracks |
| `keys:manage` | manage keys |
| `members:manage` | manage members |
| `projects:manage` | manage projects |
| `org:manage` | manage the organisation |

Customer tokens hold at most `entitlements:read`, `usage:read` and `usage:write`. Identity tokens
hold at most those and `customers:register`.
