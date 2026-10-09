# Offline snapshots

A snapshot is the customer's entitlements, signed by Entitler, so an app can check them without a
connection until it expires.

```swift
let issued = try await client.me.snapshot()
let snapshot = try verifySnapshot(
  issued.token,
  expecting: SnapshotExpectation(keys: bundledKeys, customer: customerID, environment: environmentID))
if snapshot.entitlements.has(Features.exportPDF) {
  print("Export works offline until", snapshot.expiresAt)
}
```

Verification makes no request. It checks the token's form, finds the key by id, verifies the
ES256 signature with CryptoKit (swift-crypto on Linux), then checks the issuer, that it was not
signed in the future (60 seconds of clock skew by default, 0 to 300), that it has not expired, and
that it is for the customer and environment you expect. A failure throws `EntitlerError.snapshot`
with code `snapshot_invalid` or `snapshot_expired`.

Meters in a snapshot are frozen when it is signed: `used` and `remaining` do not move offline.

## Key pinning

The keys decide which snapshots an app trusts. Ship them with the app, fetched with
`snapshotKeys()` at build time:

```swift
let keys = try await server.snapshotKeys()
let json = try JSONEncoder().encode(keys)
```

Replace them only with keys fetched from Entitler over HTTPS. Never store them beside the token or
load them from the same record: anyone who can edit that record could replace both.
