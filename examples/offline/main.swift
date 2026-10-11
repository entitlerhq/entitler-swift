import Entitler
import Foundation

enum Features {
  static let exportPDF = Feature<OnOff>("export_pdf")
}

let server = try EntitlerServer(key: ProcessInfo.processInfo.environment["ENTITLER_KEY"] ?? "")
let customer = try server.customer("test_1001")

let keys = try await server.snapshotKeys()
let environment = try await customer.check(Features.exportPDF).environment.id
let issued = try await customer.snapshot(ttlSeconds: 3_600)

let snapshot = try verifySnapshot(
  issued.token,
  expecting: SnapshotExpectation(keys: keys, customer: "test_1001", environment: environment))
print("Export to PDF offline: \(snapshot.entitlements.has(Features.exportPDF) ? "yes" : "no")")
print("Valid until \(snapshot.expiresAt)")
