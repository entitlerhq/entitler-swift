# Company decisions

`ServerCustomer` makes the changes your company decides for a deal, a support ticket or a verified
store purchase, under no self-serve rules, sales-led plans included. Each takes `reason` (at most
200 characters) and `actor` (1 to 200 characters naming the person or system that decided, such as
a support agent's id or `hubspot`), which the customer's activity shows beside the key's name.

Take each idempotency key from the event (this deal update, this webhook delivery, this ticket),
never from the deal or the customer: keys are kept for ever, so a deal won a second time after
churning needs a new key, or its write replays the first one and moves nobody.

## Plans

```swift
try await customer.setPlan(
  to: "enterprise", period: "yearly", billing: .end, reason: "Contract signed",
  actor: "hubspot", idempotencyKey: "deal-\(jobID)-won")
```

- `billing: .provider` (the default) charges the change through the provider that bills the
  product. `.keep` moves the customer in Entitler while the provider keeps billing the plan it
  bills, as a deliberate exception such as a goodwill upgrade, until a later `setPlan`. `.end` ends
  the provider's subscription when the change takes effect, and the customer then holds the plan
  outside any provider, as with an invoiced contract. Moving a Stripe payer onto invoiced
  Enterprise is that one write.
- `when: .now` or `.end` (at renewal); the project's policy when left out.
- `until:` returns the customer to the product's default plan at that instant, unless a later
  `setPlan` moves them or sets a later `until`.
- The plan the customer already holds, with the same period, billing and `until`, answers
  `changed` false, so a redelivered webhook is harmless even with a fresh key.
- Charging through the provider can fail with `402 payment_required`, whose `payment` says whether
  the card was declined or needs the customer to act.

## Add-ons

```swift
try await customer.setAddOn("extra_seats", quantity: 150, actor: "salesforce")
try await customer.setAddOn("extra_seats", quantity: 0)
```

`setAddOn` adds the add-on when the customer holds none, sets its quantity when they do, and
removes it at 0 (quantity 0 to 10,000). The change always takes effect now: an add-on change
cannot be booked for renewal.

## Grants

```swift
let change = try await customer.grant(
  Features.sso, days: 30, reason: "Ticket 4821", actor: "agent-ada")
print("Keep this id to revoke it:", change.grant.id)
try await customer.grant(Features.teamSeats, value: .amount(10))
try await customer.revokeGrant(id: change.grant.id, reason: "Trial over")
```

A grant gives a feature beyond the plan: an amount from 0 to 999,999,999 or `.unlimited`, left out
for an on/off feature, for 0 to 3,650 days (none for no end). Both calls answer a `GrantChange`
holding the grant, so a support tool keeps its id.

## Meters

```swift
try await customer.adjustMeter(
  Features.aiCredits, by: -500, idempotencyKey: "refund-\(jobID)", reason: "Failed export")
try await customer.adjustMeter(Features.aiCredits, to: 0, idempotencyKey: "reset-\(jobID)")
try await customer.cancelUsage(id: "u_123", reason: "Duplicate report")
```

`adjustMeter(_:by:)` moves the meter by a whole number other than 0 without racing new usage;
`adjustMeter(_:to:)` sets it. The meter never goes below 0, and the key is required, so a support
tool's double submit applies once. `cancelUsage(id:)` takes one report off the meter.

## Customers

`register`, `details`, `update`, `token`, `setTrack` and `billing()` are on the same customer;
`erase()` deletes the customer for good, as app stores require: it ends any Stripe subscription in
the same call, then erases their details, usage and events. Store subscriptions are invisible to
Entitler, so cancel them through Apple or Google first. Erasing twice is safe.
