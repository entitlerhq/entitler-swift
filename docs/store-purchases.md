# Store purchases

An app whose plans Apple or Google bills never calls `subscribe` and never uses a return URL: most
storefronts forbid card charges and web checkout for digital goods. Its paywall buys the store's
SKUs, and your server records each verified purchase with `setPlan`, or `setAddOn` for an add-on.
Clients never record purchases.

## The App Store

1. The paywall reads `plans()` and offers each option's `skus` whose `connector` is `apple`: the
   `productId` in `ids` is the StoreKit product to buy.
2. After a purchase, the app sends the transaction to your server, which verifies it with Apple
   (the App Store Server API, or a signed transaction checked against Apple's certificates).
3. Your server records it, with the transaction's expiry as `until`, so a missed notification ends
   the plan instead of keeping it for ever:

```swift
try await customer.setPlan(
  to: .sku(SKU(connector: "apple", ids: ["productId": "pro_yearly"])),
  until: Date().addingTimeInterval(365 * 86_400), actor: "app-store",
  idempotencyKey: "apple-\(jobID)")
```

4. At each renewal (App Store Server Notifications `DID_RENEW`), send the same `setPlan` with the
   new expiry and the notification's id as the key. On `EXPIRED` or `REFUND`, return the customer
   to the default plan with `setPlan(to: "free")`, or let `until` pass.

An add-on bought in the store is recorded the same way, with its quantity and SKU:

```swift
try await customer.setAddOn(
  "extra_seats", quantity: 5,
  sku: SKU(connector: "apple", ids: ["productId": "extra_seats_monthly"]), actor: "app-store",
  idempotencyKey: "apple-\(jobID)-seats")
```

A plan Apple bills shows `billedBy` `apple` in `plans()`, and `subscribe` answers `.manage` for it:
send the customer to the App Store's subscription management page.

## Google Play

The same recipe, with `connector` `google`, the Play product id in `ids`, verification through the
Google Play Developer API, and Real-time developer notifications for renewals, expiries and
refunds.

## Stripe already billing

A store SKU never touches Stripe, on `setPlan` and `setAddOn` alike: the store is recorded as the
biller. When Stripe already bills that product for the customer, the write answers `409 billed_elsewhere` and changes nothing: end the Stripe plan first, or keep the
customer on Stripe.

## Deleting an account

Entitler cannot see store subscriptions, so `erase()` cannot end them. The app sends the customer to
the store's subscription management page to cancel first, then your server calls `erase()`.
