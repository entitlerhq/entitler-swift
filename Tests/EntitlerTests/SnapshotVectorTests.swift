import Foundation
import Testing

@testable import Entitler

struct SnapshotVector: Sendable, CustomTestStringConvertible {
  let name: String
  let token: String
  let customer: String
  let environment: String
  let now: Date
  let clockSkewSeconds: Int?
  let outcome: String

  var testDescription: String { name }
}

let vectorFile: (keys: SnapshotKeySet, vectors: [SnapshotVector]) = {
  let url = Bundle.module.url(
    forResource: "snapshot-vectors", withExtension: "json", subdirectory: "Fixtures")!
  let data = try! Data(contentsOf: url)
  let file = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
  let keys = try! JSONDecoder().decode(
    SnapshotKeySet.self, from: JSONSerialization.data(withJSONObject: file["keys"]!))
  let vectors = (file["vectors"] as! [[String: Any]]).map { vector in
    let expected = vector["expected"] as! [String: Any]
    return SnapshotVector(
      name: vector["name"] as! String, token: vector["token"] as! String,
      customer: expected["customer"] as! String, environment: expected["environment"] as! String,
      now: isoFormatter().date(from: expected["now"] as! String)!,
      clockSkewSeconds: expected["clockSkewSeconds"] as? Int,
      outcome: canonical(vector["outcome"]!))
  }
  return (keys, vectors)
}()

func isoFormatter() -> ISO8601DateFormatter {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter
}

func iso(_ date: Date?) -> Any {
  date.map { isoFormatter().string(from: $0) } ?? NSNull()
}

func canonical(_ json: Any) -> String {
  String(
    decoding: try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
    as: UTF8.self)
}

@Suite struct SnapshotVectorTests {
  @Test(arguments: vectorFile.vectors)
  func theSharedVectorsVerifyAsEveryEntitlerSDKDoes(_ vector: SnapshotVector) {
    var outcome: Any
    do {
      let snapshot = try verifySnapshot(
        vector.token, keys: vectorFile.keys, customer: vector.customer,
        environment: vector.environment, now: vector.now,
        clockSkewSeconds: vector.clockSkewSeconds ?? 60)
      outcome = ["snapshot": json(snapshot)]
    } catch EntitlerError.snapshot(let error) {
      outcome = ["error": error.reason.rawValue]
    } catch {
      outcome = ["error": "\(error)"]
    }
    #expect(canonical(outcome) == vector.outcome)
  }
}

private func json(_ snapshot: VerifiedSnapshot) -> [String: Any] {
  [
    "customer": snapshot.customer, "environment": snapshot.environment,
    "issuedAt": iso(snapshot.issuedAt),
    "expiresAt": iso(snapshot.expiresAt),
    "served": json(snapshot.entitlements.served),
    "entitlements": snapshot.entitlements.map(json),
  ]
}

private func json(_ served: Served) -> [String: Any] {
  let source: Any =
    switch served.source {
    case .release(let id, let number): ["type": "release", "id": id, "number": number]
    case .change(let id): ["type": "change", "id": id]
    case .nothing: NSNull()
    }
  return [
    "track": served.track.map { ["id": $0.id, "name": $0.name] } ?? NSNull(), "source": source,
  ]
}

private func json(_ entitlement: Entitlement) -> [String: Any] {
  [
    "key": entitlement.key, "type": entitlement.type.rawValue, "entitled": entitlement.entitled,
    "value": json(entitlement.value), "markets": json(entitlement.markets),
    "decimals": entitlement.decimals, "currency": entitlement.currency ?? NSNull(),
    "sources": entitlement.sources.map(json),
    "upgrades": entitlement.upgrades.map {
      [
        "kind": $0.kind.rawValue, "planId": $0.planID, "plan": $0.plan, "name": $0.name,
        "product": $0.product ?? NSNull(), "move": $0.move.rawValue, "action": $0.action.rawValue,
      ] as [String: Any]
    },
    "meter": entitlement.meter.map {
      [
        "used": $0.used, "held": $0.held, "banked": $0.banked, "remaining": json($0.remaining),
        "resetsAt": iso($0.resetsAt),
      ] as [String: Any]
    } ?? NSNull(),
  ]
}

private func json(_ source: EntitlementSource) -> [String: Any] {
  switch source {
  case .plan(let plan):
    [
      "type": "plan", "planId": plan.planID, "plan": plan.plan, "name": plan.name,
      "version": plan.version, "product": plan.product ?? NSNull(), "byDefault": plan.byDefault,
      "value": plan.value.map(json) ?? NSNull(), "markets": json(plan.markets),
      "through": plan.through ?? NSNull(),
    ]
  case .addOn(let addOn):
    [
      "type": "addon", "planId": addOn.planID, "plan": addOn.plan, "name": addOn.name,
      "version": addOn.version, "quantity": addOn.quantity,
      "value": addOn.value.map(json) ?? NSNull(), "markets": json(addOn.markets),
      "through": addOn.through ?? NSNull(),
    ]
  case .grant(let grant):
    [
      "type": "grant", "grant": grant.grant, "until": iso(grant.until),
      "value": grant.value.map(json) ?? NSNull(), "markets": json(grant.markets),
      "through": grant.through ?? NSNull(),
    ]
  case .group(let features): ["type": "group", "features": features]
  }
}

private func json(_ value: FeatureValue) -> Any {
  switch value {
  case .on: true
  case .amount(let amount): amount
  case .unlimited: "unlimited"
  }
}

private func json(_ limit: Limit) -> Any {
  switch limit {
  case .amount(let amount): amount
  case .unlimited: "unlimited"
  }
}

private func json(_ markets: [String: Limit]?) -> Any {
  markets?.mapValues(json) ?? NSNull()
}
