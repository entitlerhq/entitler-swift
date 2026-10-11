import Foundation
import Testing

@testable import Entitler

extension ConformanceTests {
  @Test(arguments: Conformance.names("values"))
  func values(_ name: String) async throws {
    let testCase = Conformance.testCase("values", name)
    let outcome = testCase["outcome"] as! JSONObject
    let answer = try JSONSerialization.data(withJSONObject: testCase["answer"]!)
    let replyHeaders = headers(testCase["headers"])
    let api = FakeAPI(host: "*") { _ in
      Reply(status: 200, headers: replyHeaders, body: answer)
    }
    let path = ((testCase["request"] as! JSONObject)["path"] as! String).split(separator: "/")
    let server = try EntitlerServer(
      key: "ent_test_conformance_server_key", cache: nil, options: api.options())
    defer { server.close() }
    let result: Result<Check, any Error>
    do {
      result = .success(
        try await api.run { try await server.customer(String(path[1])).check(String(path[3])) })
    } catch {
      result = .failure(error)
    }
    let failure =
      (outcome["answer"] as? JSONObject).flatMap { $0["kind"] as? String } != nil
      || outcome["kind"] != nil
    if failure || (testCase["kind"] as? String == "value" && outcome["value"] is NSNull) {
      guard case .failure(EntitlerError.api(let error)) = result else {
        Issue.record("Expected invalid_response, not \(result)")
        return
      }
      #expect(error.status == 200)
      #expect(error.code == .invalidResponse)
      #expect(error.message == "Entitler sent an answer this SDK cannot read.")
      return
    }
    let check = try result.get()
    switch testCase["kind"] as! String {
    case "value":
      expectValue(check.value, outcome["value"])
      #expect(check.entitled == (outcome["answer"] as! JSONObject)["entitled"] as? Bool)
    case "instant":
      expectInstant(
        testCase["field"] as? String == "asOf" ? check.asOf : check.resetsAt, outcome["instant"])
    default:
      #expect(check.customer == outcome["customer"] as? String)
      #expect(check.feature == outcome["feature"] as? String)
      Shape.expect(Shape.name(check.type), outcome["type"])
      #expect(check.entitled == outcome["entitled"] as? Bool)
      expectValue(check.value, outcome["value"])
      let absent = outcome["absent"] as? [String] ?? []
      if absent.contains("used") {
        #expect(check.used == nil)
      } else if let used = outcome["used"] as? NSNumber {
        #expect(check.used == used.int64Value)
      }
      if absent.contains("held") {
        #expect(check.held == nil)
      } else if let held = outcome["held"] as? NSNumber {
        #expect(check.held == held.int64Value)
      }
      if absent.contains("remaining") {
        #expect(check.remaining == nil)
      } else if outcome["remaining"] != nil {
        expectValue(check.remaining, outcome["remaining"])
      }
      if absent.contains("resetsAt") {
        #expect(check.resetsAt == nil)
      } else if outcome.keys.contains("resetsAt") {
        expectInstant(check.resetsAt, outcome["resetsAt"])
      }
      let environment = outcome["environment"] as! JSONObject
      #expect(check.environment.id == environment["id"] as? String)
      #expect(check.environment.name == environment["name"] as? String)
      Shape.expect(Shape.name(check.environment.kind), environment["kind"])
      let track = outcome["track"] as! JSONObject
      #expect(check.track.id == track["id"] as? String)
      #expect(check.track.name == track["name"] as? String)
      #expect(check.release == (outcome["release"] as? NSNumber)?.int64Value)
      #expect(check.change == outcome["change"] as? String)
      #expect(check.testers == outcome["testers"] as? Bool)
      if let experiment = outcome["experiment"] as? JSONObject {
        #expect(check.experiment?.id == experiment["id"] as? String)
        Shape.expect(Shape.name(check.experiment?.arm), experiment["arm"])
      } else {
        #expect(check.experiment == nil)
      }
      expectInstant(check.asOf, outcome["asOf"])
      #expect(check.stale == (outcome["stale"] as? Bool ?? false))
    }
  }

  @Test(arguments: Conformance.names("answers"))
  func answers(_ name: String) async throws {
    let testCase = Conformance.testCase("answers", name)
    let call = testCase["call"] as! JSONObject
    let reply = Reply(
      status: testCase["status"] as! Int, headers: headers(testCase["headers"]),
      body: Data((testCase["body"] as! String).utf8))
    let api = FakeAPI(host: "*") { _ in reply }
    let server = try EntitlerServer(
      key: "ent_test_conformance_server_key", cache: nil,
      options: api.options { $0.maxRetries = 0 })
    defer { server.close() }
    let customer = try server.customer(call["customer"] as! String)
    let key = call["idempotencyKey"] as? String
    let shape: Any
    do {
      shape = try await api.run { () async throws -> Any in
        switch call["method"] as! String {
        case "check":
          let check = try await customer.check(call["feature"] as! String)
          return ["entitled": check.entitled, "upgrades": Shape.upgrades(check.upgrades)]
        case "plans":
          return Self.plansShape(try await customer.plans())
        case "recordUsage":
          return Self.usageShape(
            try await customer.recordUsage(
              of: Feature<Metered>(call["feature"] as! String),
              amount: (call["amount"] as! NSNumber).int64Value, idempotencyKey: key!))
        case "subscribe":
          return Self.stepShape(
            try await customer.subscribe(
              to: call["plan"] as! String, period: call["period"] as? String,
              returnURL: (call["returnUrl"] as? String).flatMap(URL.init(string:)),
              idempotencyKey: key))
        case "cancel":
          return Self.changeShape(
            try await customer.cancel(addOn: call["addOn"] as? String, idempotencyKey: key))
        case "undoPendingChange":
          return Self.changeShape(try await customer.undoPendingChange(idempotencyKey: key))
        case "setPlan":
          return Self.changeShape(
            try await customer.setPlan(
              to: .plan(call["plan"] as! String), period: call["period"] as? String,
              until: instant(call["until"]), reason: call["reason"] as? String,
              actor: call["actor"] as? String, idempotencyKey: key))
        case "setAddOn":
          return Self.changeShape(
            try await customer.setAddOn(
              call["addOn"] as! String, quantity: (call["quantity"] as! NSNumber).intValue,
              idempotencyKey: key))
        case "grant":
          return Self.grantShape(
            try await customer.grant(
              call["feature"] as! String,
              value: (call["value"] as? NSNumber).map { .amount($0.int64Value) },
              days: call["days"] as? Int, reason: call["reason"] as? String,
              actor: call["actor"] as? String, idempotencyKey: key))
        case "revokeGrant":
          return Self.grantShape(
            try await customer.revokeGrant(id: call["grantId"] as! String, idempotencyKey: key))
        case "billingPortal":
          let page = try await customer.billingPortal(
            returnURL: URL(string: call["returnUrl"] as! String)!)
          return ["url": page.url.absoluteString]
        default:
          return ["changed": try await customer.syncBilling().changed]
        }
      }
    } catch EntitlerError.api(let error) {
      shape = Shape.apiError(error)
    }
    Shape.expect(shape, testCase["outcome"])
    #expect(api.count == 1)
  }

  static func plansShape(_ plans: CustomerPlans) -> JSONObject {
    [
      "held": plans.held.map { held in
        [
          "plan": Shape.plan(held.plan, kind: true), "product": Shape.product(held.product),
          "version": Shape.optional(held.version), "byDefault": held.byDefault,
          "period": Shape.period(held.period), "renewsAt": Shape.instant(held.renewsAt),
          "pending": pendingShape(held.pending), "billedBy": Shape.name(held.billedBy),
        ] as JSONObject
      },
      "options": plans.options.map { option in
        [
          "plan": [
            "id": option.plan.id, "key": option.plan.key, "name": option.plan.name,
            "kind": Shape.name(option.plan.kind), "description": option.plan.description,
            "default": option.plan.isDefault,
          ] as JSONObject,
          "product": Shape.product(option.product), "from": Shape.plan(option.from),
          "move": Shape.name(option.move), "action": Shape.name(option.action),
          "reason": Shape.optional(option.reason), "when": Shape.name(option.when),
          "periods": option.periods.map(Shape.period),
          "impact": option.impact.map { ["kind": Shape.name($0.kind), "text": $0.text] },
          "skus": option.skus.map { sku in
            [
              "period": Shape.period(sku.period), "connector": sku.connector, "ids": sku.ids,
              "price": Shape.optional(
                sku.price.map { price in
                  [
                    "amount": price.amount, "currency": price.currency,
                    "interval": Shape.name(price.interval), "intervalCount": price.intervalCount,
                    "tax": Shape.name(price.tax),
                  ] as JSONObject
                }),
            ] as JSONObject
          },
        ] as JSONObject
      },
    ]
  }

  static func pendingShape(_ pending: PendingChange?) -> Any {
    switch pending {
    case nil: NSNull()
    case .move(let plan): ["type": "move", "plan": Shape.plan(plan)]
    case .cancel(let plan): ["type": "cancel", "movingTo": Shape.plan(plan)]
    case .unknown(let type): ["type": ["unknown": type]]
    }
  }

  static func usageShape(_ result: UsageResult) -> JSONObject {
    [
      "outcome": Shape.name(result.outcome), "refusal": Shape.name(result.refusal),
      "id": Shape.optional(result.id), "holdId": Shape.optional(result.holdID),
      "mode": Shape.name(result.mode), "amount": result.amount, "meterChange": result.meterChange,
      "overBy": result.overBy, "late": result.late, "occurredAt": Shape.instant(result.occurredAt),
      "expiresAt": Shape.instant(result.expiresAt), "reportedAs": Shape.name(result.reportedAs),
      "entitled": result.entitled, "used": Shape.optional(result.used),
      "remaining": Shape.value(result.remaining), "held": Shape.optional(result.held),
      "upgrades": Shape.upgrades(result.upgrades), "replayed": result.replayed,
    ]
  }

  static func stepShape(_ step: SubscribeStep) -> JSONObject {
    switch step {
    case .done(let change):
      changeShape(change).merging(["next": "done"]) { $1 }
    case .pay(let url): ["next": "pay", "url": url.absoluteString]
    case .confirming: ["next": "confirming"]
    case .manage(let provider): ["next": "manage", "billedBy": Shape.name(provider)]
    case .unknown(let next): ["next": ["unknown": next]]
    }
  }

  static func changeShape(_ change: PlanChange) -> JSONObject {
    [
      "product": Shape.product(change.product), "plan": Shape.plan(change.plan),
      "quantity": Shape.optional(change.quantity), "effective": Shape.name(change.effective),
      "at": Shape.instant(change.at), "until": Shape.instant(change.until),
      "changed": change.changed, "replayed": change.replayed,
    ]
  }

  static func grantShape(_ change: GrantChange) -> JSONObject {
    [
      "grant": [
        "id": change.grant.id, "feature": change.grant.feature,
        "until": Shape.instant(change.grant.until),
        "revokedAt": Shape.instant(change.grant.revokedAt),
      ] as JSONObject,
      "replayed": change.replayed,
    ]
  }

  @Test(arguments: Conformance.names("errors"))
  func errors(_ name: String) async throws {
    let testCase = Conformance.testCase("errors", name)
    let call = testCase["call"] as! JSONObject
    let reply = Reply(
      status: testCase["status"] as! Int, headers: headers(testCase["headers"]),
      body: Data((testCase["body"] as? String ?? "").utf8))
    let api = FakeAPI(host: "*") { _ in reply }
    if let receivedAt = instant(testCase["receivedAt"]) { api.clock.with { $0 = receivedAt } }
    let options = api.options { $0.maxRetries = 0 }
    let key = call["idempotencyKey"] as? String
    let request: () async throws -> Void
    let close: () -> Void
    if let client = call["client"] as? JSONObject {
      let inApp = try EntitlerClient(
        key: client["key"] as! String, identityToken: client["identityToken"] as! String,
        cache: nil, options: options)
      close = inApp.close
      request = { try await inApp.register(idempotencyKey: key) }
    } else {
      let server = try EntitlerServer(
        key: "ent_test_conformance_server_key", cache: nil, options: options)
      close = server.close
      let customer = try server.customer(call["customer"] as! String)
      request = {
        switch call["method"] as! String {
        case "check" where call["asOf"] != nil:
          _ = try await customer.check(call["feature"] as! String, asOf: instant(call["asOf"]))
        case "check": _ = try await customer.check(call["feature"] as! String)
        case "recordUsage":
          _ = try await customer.recordUsage(
            of: Feature<Metered>(call["feature"] as! String),
            amount: (call["amount"] as! NSNumber).int64Value, idempotencyKey: key!)
        case "setPlan":
          let plan: PlanChoice
          if let sku = call["sku"] as? JSONObject {
            plan = .sku(
              SKU(connector: sku["connector"] as! String, ids: sku["ids"] as! [String: String]))
          } else {
            plan = .plan(call["plan"] as! String)
          }
          _ = try await customer.setPlan(
            to: plan, period: call["period"] as? String, until: instant(call["until"]),
            idempotencyKey: key)
        default:
          _ = try await customer.subscribe(
            to: call["plan"] as! String, period: call["period"] as? String, idempotencyKey: key)
        }
      }
    }
    defer { close() }
    do {
      try await api.run(request)
      Issue.record("Expected an APIError")
    } catch EntitlerError.api(let error) {
      Shape.expect(Shape.apiError(error), testCase["outcome"])
    }
    #expect(api.count == 1)
  }

  @Test(arguments: Conformance.names("snapshots"))
  func snapshots(_ name: String) throws {
    let testCase = Conformance.testCase("snapshots", name)
    let outcome = testCase["outcome"] as! JSONObject
    let expected = testCase["expected"] as! JSONObject
    let keyData = try JSONSerialization.data(withJSONObject: expected["keys"]!)
    let keys: [JSONWebKey] =
      expected["keys"] is [Any]
      ? try JSONDecoder().decode([JSONWebKey].self, from: keyData)
      : try JSONDecoder().decode(SnapshotKeys.self, from: keyData).keys
    var expectation = SnapshotExpectation(
      keys: keys, customer: expected["customer"] as! String,
      environment: expected["environment"] as! String,
      now: instant(expected["now"]),
      clockSkewSeconds: (expected["clockSkewSeconds"] as? NSNumber)?.intValue ?? 60)
    if let issuer = expected["issuer"] as? String { expectation.issuer = issuer }
    do {
      let snapshot = try verifySnapshot(testCase["token"] as! String, expecting: expectation)
      guard let wanted = outcome["snapshot"] as? JSONObject else {
        Issue.record("Expected \(outcome)")
        return
      }
      #expect(snapshot.customer == wanted["customer"] as? String)
      #expect(snapshot.environment.id == (wanted["environment"] as? JSONObject)?["id"] as? String)
      let track = wanted["track"] as! JSONObject
      #expect(snapshot.track.id == track["id"] as? String)
      #expect(snapshot.track.name == track["name"] as? String)
      #expect(snapshot.release == (wanted["release"] as? NSNumber)?.int64Value)
      #expect(snapshot.change == wanted["change"] as? String)
      #expect(snapshot.testers == wanted["testers"] as? Bool)
      expectInstant(snapshot.expiresAt, wanted["expiresAt"])
      let entitlements = wanted["entitlements"] as! JSONObject
      expectInstant(snapshot.entitlements.asOf, entitlements["asOf"])
      #expect(snapshot.entitlements.experiment == nil)
      let items = entitlements["items"] as! [JSONObject]
      #expect(snapshot.entitlements.items.count == items.count)
      for (item, wantedItem) in zip(snapshot.entitlements.items, items) {
        #expect(item.key == wantedItem["key"] as? String)
        Shape.expect(Shape.name(item.type), wantedItem["type"])
        #expect(item.entitled == wantedItem["entitled"] as? Bool)
        expectValue(item.value, wantedItem["value"])
        Shape.expect(Shape.upgrades(item.upgrades), wantedItem["upgrades"] ?? [Any]())
        let absent = wantedItem["absent"] as? [String] ?? []
        #expect((item.used == nil) == absent.contains("used"))
        #expect((item.held == nil) == absent.contains("held"))
        #expect((item.remaining == nil) == absent.contains("remaining"))
        if let used = wantedItem["used"] as? NSNumber { #expect(item.used == used.int64Value) }
        if let held = wantedItem["held"] as? NSNumber { #expect(item.held == held.int64Value) }
        if wantedItem["remaining"] != nil { expectValue(item.remaining, wantedItem["remaining"]) }
        if wantedItem.keys.contains("resetsAt") {
          expectInstant(item.resetsAt, wantedItem["resetsAt"])
        }
      }
      for (key, has) in entitlements["has"] as? [String: Bool] ?? [:] {
        #expect(snapshot.entitlements.has(key) == has, "has(\(key))")
      }
      for (key, entry) in entitlements["get"] as? JSONObject ?? [:] {
        if entry is NSNull {
          #expect(snapshot.entitlements[key] == nil, "get(\(key))")
        } else {
          #expect(
            snapshot.entitlements[key]?.key == (entry as? JSONObject)?["key"] as? String,
            "get(\(key))")
        }
      }
    } catch EntitlerError.snapshot(let error) {
      #expect(outcome["kind"] as? String == "SnapshotError", "\(error.message)")
      #expect(error.code.rawValue == outcome["code"] as? String)
      #expect(error.message == outcome["message"] as? String)
    } catch let error as ArgumentError {
      #expect(outcome["kind"] as? String == "ArgumentError")
      #expect(error.message == outcome["message"] as? String)
    }
  }
}
