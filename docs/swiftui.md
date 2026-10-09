# SwiftUI

Keep one in-app client for the signed-in session, and read entitlements in a view model:

```swift
@MainActor
final class ExportViewModel: ObservableObject {
  @Published private(set) var canExport = false
  @Published private(set) var creditsLeft: FeatureValue?

  private let customer: SignedInCustomer

  init(client: EntitlerClient<TokenCredential>) {
    customer = client.me
  }

  func refresh() async {
    canExport = await customer.isEntitled(to: Features.exportPDF, default: false)
    creditsLeft = try? await customer.check(Features.aiCredits).remaining
  }

  func export() async throws {
    guard canExport else { return }
    try await customer.recordUsage(of: Features.aiCredits, amount: 1)
    await refresh()
  }
}

struct ExportButton: View {
  @StateObject var model: ExportViewModel

  var body: some View {
    Button("Export to PDF") {
      Task { try? await model.export() }
    }
    .disabled(!model.canExport)
    .task { await model.refresh() }
  }
}
```

Every call is `async`, so nothing blocks the main actor. `isEntitled` never throws: a lost
connection shows the default, and a recent answer from the cache stands in while offline.

Create the client when the person signs in, with a token provider that asks your server:

```swift
let client = try EntitlerClient(tokenProvider: {
  try await api.entitlerToken()
})
```

For checks with no connection at all, ship snapshot keys with the app and keep a snapshot; see
[offline snapshots](offline-snapshots.md).
