# Examples

Small programs using the Entitler SDK for Swift. Each runs against your project with a secret key
in `ENTITLER_KEY`, from this directory:

- `quickstart`: a server registers a customer, checks a feature and records usage.
  `ENTITLER_KEY=sk_… swift run quickstart`
- `pricing-page`: prints the pricing as a pricing page would, with a visitor id.
  `ENTITLER_KEY=sk_… swift run pricing-page`
- `in-app`: the server mints a customer token, and an in-app client with a token provider checks
  and records usage for `me`. `ENTITLER_KEY=sk_… swift run in-app`
- `metered-work`: `withHold` around work whose cost is known only afterwards, and an observe-mode
  report. `ENTITLER_KEY=sk_… swift run metered-work`
- `offline`: fetches a snapshot and the keys, then verifies the snapshot offline and checks a
  feature. `ENTITLER_KEY=sk_… swift run offline`
- `billing`: self-serve subscription, plan space, a checkout that handles `409 stale`, and a vendor
  grant. `ENTITLER_KEY=sk_… swift run billing`
- `generated-features`: a constants file from `entitler generate`, and code that uses it.
  `ENTITLER_KEY=sk_… swift run generated-features`
- `swiftui-view-model`: a SwiftUI view model gating a button. Build it on macOS or iOS with
  `swift build --target SwiftUIViewModel`.

The examples use the sample catalogue (`export_pdf`, `ai_credits`, `sso`, plans `free` and `pro`).
