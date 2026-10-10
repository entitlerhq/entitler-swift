#if canImport(SwiftUI)
  import Entitler
  import SwiftUI

  enum Features {
    static let exportPDF = Feature<OnOff>("export_pdf")
    static let aiCredits = Feature<Metered>("ai_credits")
  }

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
#endif
