# ``Entitler``

Check feature access, record usage, show pricing and manage subscriptions with Entitler.

## Overview

Entitler lets SaaS teams manage plans, feature access, usage limits and customer grants. This
package has two clients: ``EntitlerServer`` for your servers, built from a secret key, and
``EntitlerClient`` for your apps, built from a customer token or an identity token. Both return a
``Customer``, so code that gates features and records usage is written once.

```swift
import Entitler

let server = try EntitlerServer(key: key)
let customer = try server.customer("user_123")
try await customer.register(name: "Ada Lovelace", email: "ada@example.com")

if await customer.isEntitled(to: Features.exportPDF, default: false) {
  try await customer.recordUsage(of: Features.aiCredits, amount: 1)
}
```

## Topics

### Clients

- ``EntitlerServer``
- ``EntitlerClient``
- ``EntitlerOptions``
- ``TokenCredential``
- ``IdentityCredential``
- ``ClientCredential``
- ``TokenProvider``

### Customers

- ``Customer``
- ``ServerCustomer``
- ``SignedInCustomer``
- ``Vendor``
- ``Customers``
- ``CustomerHandle``
- ``PlanChoice``
- ``SKU``

### Features

- ``Feature``
- ``FeatureKind``
- ``OnOff``
- ``Config``
- ``Metered``
- ``FeatureGroup``
- ``FeatureValue``
- ``FeatureType``

### Checks and entitlements

- ``Check``
- ``MeteredCheck``
- ``Entitlements``
- ``Entitlement``
- ``EntitlementSource``
- ``Upgrade``

### Usage

- ``UsageResult``
- ``UsageHold``
- ``UsageMode``
- ``UsageOutcome``
- ``UsageRefusal``
- ``UsageBatchEvent``
- ``UsageBatchResult``
- ``UsageEventResult``
- ``CustomerUsage``
- ``UsageEvent``
- ``PagedList``
- ``Page``

### Offline snapshots

- ``verifySnapshot(_:expecting:)``
- ``SnapshotExpectation``
- ``VerifiedSnapshot``
- ``IssuedSnapshot``
- ``JSONWebKeySet``
- ``JSONWebKey``

### Visitors

- ``newVisitorID()``
- ``visitorIDPattern``

### Reliability

- ``CacheStore``
- ``CacheEntry``
- ``MemoryCacheStore``

### Errors

- ``EntitlerError``
- ``APIError``
- ``ErrorCode``
- ``ConnectionError``
- ``TimeoutError``
- ``TokenError``
- ``SnapshotError``
- ``ArgumentError``

### Scopes

- ``Scope``
- ``CredentialScopes``
