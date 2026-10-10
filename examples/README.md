# Examples

Small programs using the Entitler SDK for Swift. Each runs against your project with a secret key
in `ENTITLER_KEY`, from this directory:

- `quickstart`: a server registers a customer, checks a feature with `isEntitled` and records
  usage with an idempotency key. `ENTITLER_KEY=ent_test_… swift run quickstart`
- `pricing-page`: prints the pricing as a pricing page would, once through `EntitlerClient(key:)`
  with a publishable key and once through the server with a visitor id.
  `ENTITLER_KEY=ent_test_… ENTITLER_PUBLISHABLE_KEY=ent_pk_test_… swift run pricing-page`
- `in-app`: the server mints a customer token with `entitlements:read` and `usage:write`; an in-app
  client with a token provider checks and records usage for `me`, and is closed at sign-out.
  `ENTITLER_KEY=ent_test_… swift run in-app`
- `metered-work`: a `startHold` handle around streamed work that reports as it goes, `withHold`
  around work whose cost is known only afterwards, and an observe-mode report.
  `ENTITLER_KEY=ent_test_… swift run metered-work`
- `offline`: fetches a snapshot and the keys, then verifies the snapshot offline and checks a
  feature. `ENTITLER_KEY=ent_test_… swift run offline`
- `billing`: a billing page from `plans()`, `subscribe` handling every next step, the return page
  with `syncBilling()`, `cancel` and `undoPendingChange`, the billing portal handling `409 stale`,
  and the company's `setPlan` with `billing: .end` and a grant whose id it keeps.
  `ENTITLER_KEY=ent_test_… swift run billing`
- `generated-features`: a constants file from `entitler generate`, and code that uses it.
  `ENTITLER_KEY=ent_test_… swift run generated-features`
- `swiftui-view-model`: a SwiftUI view model gating a button. Build it on macOS or iOS with
  `swift build --target SwiftUIViewModel`.
- `testing`: unit tests of an app's gating and billing code with `FakeCustomer`, which need no key.
  `swift test`

The examples use the sample catalogue (`export_pdf`, `ai_credits`, `sso`, plans `free` and `pro`).
