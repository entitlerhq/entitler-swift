# ``EntitlerTesting``

Test your app's gating and billing code without the network.

## Overview

Depend on this library from your test targets only, so your app never ships it.
``FakeCustomer`` holds a `ServerCustomer` that makes no request: its reads answer from the values
you give, its usage writes move the meters by Entitler's rules, and it records every write.
``FakeAnswers`` writes complete JSON answers for tests that fake the HTTP transport.

```swift
import EntitlerTesting

let fake = FakeCustomer(["export_pdf": true, "ai_credits": .metered(value: 100, used: 97)])
try await exportReport(for: fake.customer)
#expect(fake.writes.map(\.method) == ["recordUsage"])
```

## Topics

### Fakes

- ``FakeCustomer``
- ``FakeValue``
- ``FakeWrite``

### Answers

- ``FakeAnswers``
