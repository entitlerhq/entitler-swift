# SwiftUI

## One client per signed-in person

Keep the in-app client in an app-scoped session object, create it at sign-in, and close it at
sign-out. Views and view models take its `me`:

```swift
@MainActor
final class AppSession: ObservableObject {
  @Published private(set) var client: EntitlerClient<TokenCredential>?

  func signIn() throws {
    client = try EntitlerClient(tokenProvider: { try await api.entitlerToken() })
  }

  func signOut() {
    client?.close()
    client = nil
    resetStoredVisitor()
  }
}
```

## A view model

```swift
@MainActor
final class ExportViewModel: ObservableObject {
  @Published private(set) var canExport = false
  @Published private(set) var creditsLeft: FeatureValue?

  private let customer: SignedInCustomer

  init(customer: SignedInCustomer) {
    self.customer = customer
  }

  func refresh() async {
    canExport = await customer.isEntitled(to: Features.exportPDF, default: false)
    creditsLeft = try? await customer.check(Features.aiCredits).remaining
  }

  func export(job: UUID) async throws {
    guard canExport else { return }
    try await customer.recordUsage(
      of: Features.aiCredits, amount: 1, idempotencyKey: "export-\(job.uuidString)")
    await refresh()
  }
}

struct ExportButton: View {
  @StateObject var model: ExportViewModel

  var body: some View {
    Button("Export to PDF") {
      Task { try? await model.export(job: UUID()) }
    }
    .disabled(!model.canExport)
    .task { await model.refresh() }
  }
}
```

Every call is `async`, so nothing blocks the main actor. `isEntitled` never throws: a lost
connection shows the default, and a recent answer from the cache stands in while offline.

## Paying through Stripe

An app billed through Stripe passes a universal link as the return URL, opens the `pay` step's URL
(and the billing portal's) in `ASWebAuthenticationSession`, and on return syncs the customer's
billing and reads their plans again:

```swift
import AuthenticationServices

@available(iOS 17.4, macOS 14.4, *)
@MainActor
final class Checkout: NSObject, ASWebAuthenticationPresentationContextProviding {
  static let returnURL = URL(string: "https://example.com/billing/return")!

  func buy(_ plan: String, period: String, for customer: SignedInCustomer) async throws {
    let step = try await customer.subscribe(to: plan, period: period, returnURL: Self.returnURL)
    guard case .pay(let url) = step else { return }
    try await open(url)
    _ = try await customer.syncBilling()
    _ = try await customer.plans(revalidate: true)
  }

  private func open(_ url: URL) async throws {
    try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, any Error>) in
      let session = ASWebAuthenticationSession(
        url: url, callback: .https(host: "example.com", path: "/billing/return")
      ) { _, error in
        if let error { done.resume(throwing: error) } else { done.resume() }
      }
      session.presentationContextProvider = self
      session.start()
    }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    ASPresentationAnchor()
  }
}
```

The `.https(host:path:)` callback matches the universal link from iOS 17.4 and macOS 14.4. On
older systems, use `ASWebAuthenticationSession(url:callbackURLScheme:completionHandler:)` with a
custom scheme registered by the app, or open the page in Safari and handle the universal link in
`onOpenURL`; either way call `syncBilling()` and `plans(revalidate: true)` when the customer is
back. The SDK takes no AuthenticationServices dependency.

## Store-billed plans

An app whose plans Apple bills never calls `subscribe`: its paywall buys the `skus` from `plans()`
with StoreKit, and your server verifies each transaction and calls `setPlan(to: .sku(…), until:)`.
A plan Apple bills answers `.manage(billedBy: .apple)`, so send the customer to the App Store's
subscription management page. See [store purchases](store-purchases.md).

For checks with no connection at all, ship snapshot keys with the app and keep a snapshot; see
[offline snapshots](offline-snapshots.md).
