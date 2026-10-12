import Entitler
import Foundation

enum Features {
  static let exportPDF = Feature<OnOff>("export_pdf")
}

let customerID = "test_1001"
let server = try EntitlerServer(key: ProcessInfo.processInfo.environment["ENTITLER_KEY"] ?? "")
let customer = try server.customer(customerID)

let keys = try await server.snapshotKeys()
let environmentID = try await customer.check(Features.exportPDF).environment.id
let stored = try await customer.snapshot(ttlSeconds: 3_600).token

func canExportPDF() async -> Bool {
  do {
    return try await customer.check(Features.exportPDF).entitled
  } catch let error as EntitlerError where error.isUnreachable {
    let expected = SnapshotExpectation(
      keys: keys, customer: customerID, environment: environmentID)
    guard let snapshot = try? verifySnapshot(stored, expecting: expected) else { return false }
    print("Entitler is unreachable; answering from the snapshot valid until \(snapshot.expiresAt)")
    return snapshot.entitlements.has(Features.exportPDF)
  } catch {
    return false
  }
}

let snapshot = try verifySnapshot(
  stored,
  expecting: SnapshotExpectation(keys: keys, customer: customerID, environment: environmentID))
print("Export to PDF offline: \(snapshot.entitlements.has(Features.exportPDF) ? "yes" : "no")")
print("Valid until \(snapshot.expiresAt)")
print("Export to PDF now: \(await canExportPDF() ? "yes" : "no")")
