# ``Entitler``

Check feature access, record usage, show pricing and manage subscriptions with Entitler.

## Overview

Entitler lets SaaS teams manage plans, feature access, usage limits and customer grants. This
package has two clients: ``EntitlerServer`` for your servers, built from a secret key, and
``EntitlerClient`` for your apps, built from a customer token, or a publishable key with or
without an identity token. Both return a ``Customer``, so code that gates features, records usage
and offers the customer's own billing choices is written once. The `EntitlerTesting` library fakes
a customer for your own tests.

```swift
import Entitler

let server = try EntitlerServer(key: key)
let customer = try server.customer("user_123")
try await customer.register(name: "Ada Lovelace", email: "ada@example.com")

if await customer.isEntitled(to: Features.exportPDF, default: false) {
  try await customer.recordUsage(of: Features.aiCredits, amount: 1, idempotencyKey: job.id)
}
```

## Topics

### Clients

- ``EntitlerServer``
- ``EntitlerClient``
- ``EntitlerOptions``
- ``TokenCredential``
- ``IdentityCredential``
- ``PublishableCredential``
- ``ClientCredential``
- ``SignedInCredential``
- ``TokenProvider``

### Customers

- ``Customer``
- ``ServerCustomer``
- ``SignedInCustomer``
- ``Customers``
- ``CustomerHandle``

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
- ``Period``

### Usage

- ``UsageResult``
- ``Hold``
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

### Billing

- ``CustomerPlans``
- ``HeldPlan``
- ``PendingChange``
- ``MoveOption``
- ``OptionPlan``
- ``Move``
- ``MoveAction``
- ``SubscribeStep``
- ``PlanChange``
- ``ChangeEffect``
- ``ChangeTiming``
- ``BillingSync``
- ``ProviderPage``
- ``PlanChoice``
- ``SKU``
- ``BillingMode``
- ``GrantChange``
- ``Grant``

### Offline snapshots

- ``verifySnapshot(_:expecting:)``
- ``SnapshotExpectation``
- ``VerifiedSnapshot``
- ``IssuedSnapshot``
- ``SnapshotKeys``
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
- ``UsageSettlementError``
- ``ConnectionError``
- ``TimeoutError``
- ``TokenError``
- ``SnapshotError``
- ``ArgumentError``
- ``ClientClosedError``

### Scopes

- ``Scope``
- ``CredentialScopes``
