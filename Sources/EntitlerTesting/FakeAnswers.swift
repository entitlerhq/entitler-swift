import Entitler
import Foundation

/// Complete JSON answers, as Entitler sends them, for tests that fake the HTTP transport with a
/// `URLProtocol`, so a fixture missing one field never decodes as `invalid_response` and passes a
/// test for the wrong reason.
///
/// ```swift
/// let body = FakeAnswers.check(feature: "export_pdf", entitled: true, value: .on)
/// ```
///
/// Every answer names the environment `development`, the All customers track and release 1.
public enum FakeAnswers {
  /// A check of one feature, metered when `used` is given.
  public static func check(
    feature: String, entitled: Bool, value: FeatureValue, type: FeatureType? = nil,
    used: Int64? = nil, held: Int64 = 0, customer: String = "user_1", upgrades: [Upgrade] = []
  ) -> Data {
    var object = entitlement(
      key: feature, entitled: entitled, value: value, type: type, used: used, held: held,
      upgrades: upgrades)
    object["feature"] = object.removeValue(forKey: "key")
    object["customer"] = customer
    object["asOf"] = now
    return json(object.merging(context) { $1 })
  }

  /// The customer's entitlements, from feature keys and their values.
  public static func entitlements(_ values: [String: FakeValue], customer: String = "user_1")
    -> Data
  {
    let items = values.keys.sorted().map { key in values[key]!.entitlement(key: key) }
    return json(
      ["customer": customer, "asOf": now, "entitlements": items].merging(context) { $1 })
  }

  /// The customer's plans: the plans held, by key, and the plans they can move to.
  public static func plans(
    held: [String] = ["free"], options: [Option] = [], customer: String = "user_1"
  ) -> Data {
    let heldPlans: [[String: Any]] = held.map { key in
      [
        "plan": ["id": "plan_\(key)", "key": key, "name": key.capitalized, "kind": "plan"],
        "product": ["key": "app", "name": "App"], "version": 1, "byDefault": key == "free",
        "period": NSNull(), "renewsAt": NSNull(), "pending": NSNull(), "billedBy": NSNull(),
      ]
    }
    return json(
      [
        "customer": customer, "asOf": now, "held": heldPlans,
        "options": options.map(\.object),
      ].merging(context) { $1 })
  }

  /// A plan a customer can move to, in ``plans(held:options:customer:)``.
  public struct Option: Sendable {
    let plan: String
    let move: Move
    let action: MoveAction
    let periods: [String]

    /// Creates an option.
    ///
    /// - Parameters:
    ///   - plan: The plan's key.
    ///   - move: How it changes the customer's plans.
    ///   - action: Who can make the move.
    ///   - periods: The keys of its billing periods.
    public init(
      plan: String, move: Move = .upgrade, action: MoveAction = .buy,
      periods: [String] = ["monthly"]
    ) {
      self.plan = plan
      self.move = move
      self.action = action
      self.periods = periods
    }

    var object: [String: Any] {
      [
        "plan": [
          "id": "plan_\(plan)", "key": plan, "name": plan.capitalized, "kind": "plan",
          "description": "", "default": false,
        ],
        "product": ["key": "app", "name": "App"], "from": NSNull(), "move": move.rawValue,
        "action": action.rawValue, "reason": NSNull(), "when": "now",
        "periods": periods.map { ["key": $0, "label": $0.capitalized] }, "impact": [Any](),
        "skus": [Any](),
      ]
    }
  }

  /// Pricing with the plans given, by key, each on sale monthly with no provider.
  public static func pricing(plans: [String] = ["free", "pro"], customer: String? = nil) -> Data {
    let listed: [[String: Any]] = plans.map { key in
      [
        "id": "plan_\(key)", "key": key, "name": key.capitalized, "description": "",
        "kind": "plan", "product": "app", "salesLed": false, "status": "active", "version": 1,
        "default": key == "free",
        "periods": [["key": "monthly", "label": "Monthly", "count": 1, "unit": "months"]],
        "attachesTo": [Any](),
        "features": [String: Any](), "listings": [Any](),
      ]
    }
    var object = context
    object["customer"] = orNull(customer)
    object["defaultPlan"] = plans.contains("free") ? "free" : NSNull()
    object["products"] = [["key": "app", "name": "App", "defaultPlan": "free"]]
    object["plans"] = listed
    return json(object)
  }

  /// A usage write's answer.
  public static func usageResult(
    feature: String, outcome: UsageOutcome, amount: Int64, value: FeatureValue = .amount(100),
    used: Int64 = 0, held: Int64 = 0, holdID: String? = nil, refusal: UsageRefusal? = nil,
    mode: UsageMode = .gate, meterChange: Int64 = 0, overBy: Int64 = 0, id: String? = "usage_1",
    expiresAt: Date? = nil, customer: String = "user_1"
  ) -> Data {
    var object = entitlement(
      key: feature, entitled: refusal == nil, value: value, type: .metered, used: used,
      held: held, upgrades: [])
    object["feature"] = object.removeValue(forKey: "key")
    object["customer"] = customer
    object["asOf"] = now
    object["outcome"] = outcome.rawValue
    object["refusal"] = orNull(refusal?.rawValue)
    object["id"] = orNull(id)
    object["holdId"] = orNull(holdID)
    object["mode"] = mode.rawValue
    object["amount"] = amount
    object["meterChange"] = meterChange
    object["overBy"] = overBy
    object["late"] = false
    object["occurredAt"] = now
    object["expiresAt"] = orNull(expiresAt.map(instant))
    object["reportedAs"] = "api"
    return json(object.merging(context) { $1 })
  }

  /// The next step of `subscribe`.
  public static func subscribeStep(_ step: SubscribeStep) -> Data {
    switch step {
    case .done(let change): return json(planChangeObject(change).merging(["next": "done"]) { $1 })
    case .pay(let url): return json(["next": "pay", "url": url.absoluteString])
    case .confirming: return json(["next": "confirming"])
    case .manage(let provider): return json(["next": "manage", "billedBy": provider.rawValue])
    case .unknown(let next): return json(["next": next])
    }
  }

  /// A done step's change, made now: the plan given, or none.
  public static func subscribeDone(plan: String? = "pro", changed: Bool = true) -> Data {
    json(planChangeFields(plan: plan, changed: changed).merging(["next": "done"]) { $1 })
  }

  /// A plan change, made now: the plan given, or none.
  public static func planChange(
    plan: String? = "pro", quantity: Int64? = nil, changed: Bool = true
  ) -> Data {
    var object = planChangeFields(plan: plan, changed: changed)
    object["quantity"] = orNull(quantity)
    return json(object)
  }

  /// A grant made or revoked.
  public static func grantChange(
    id: String = "grant_1", feature: String, value: String = "true", revoked: Bool = false,
    reason: String = "", actor: String? = nil
  ) -> Data {
    json([
      "grant": [
        "id": id, "feature": feature, "value": value, "from": now, "until": NSNull(),
        "revokedAt": orNull(revoked ? now : nil), "reason": reason, "by": "Test key",
        "actor": orNull(actor),
      ]
    ])
  }

  /// The answer of `syncBilling`.
  public static func billingSync(changed: Bool = false) -> Data { json(["changed": changed]) }

  /// The provider's page, as `billingPortal` answers it.
  public static func providerPage(url: URL) -> Data {
    json(["provider": "stripe", "url": url.absoluteString])
  }

  /// A registered customer.
  public static func registeredCustomer(id: String = "user_1", created: Bool = true) -> Data {
    json([
      "id": "cus_\(id)", "externalId": id, "environmentId": "env_test", "createdAt": now,
      "created": created,
    ])
  }

  /// A customer token.
  public static func customerToken(
    customer: String = "user_1", scopes: [Scope] = [.entitlementsRead]
  ) -> Data {
    json([
      "token": "header.payload.signature", "customer": customer, "scopes": scopes.map(\.rawValue),
      "expiresAt": instant(Date().addingTimeInterval(3_600)),
    ])
  }

  /// A customer's place on a track.
  public static func customerTrack(customer: String = "user_1", track: String?) -> Data {
    json([
      "customer": customer,
      "track": ["id": "track_\(track ?? "all")", "name": track ?? "All customers"],
      "source": "server", "previousTrackId": NSNull(),
    ])
  }

  /// An error answer, as Entitler sends it with a non-2xx status.
  public static func error(code: ErrorCode, message: String) -> Data {
    json(["error": ["code": code.rawValue, "message": message]])
  }

  static let now = "2026-07-01T09:30:00.000Z"

  static var context: [String: Any] {
    [
      "environment": ["id": "env_test", "name": "development", "kind": "test"],
      "track": ["id": "track_all", "name": "All customers"], "release": 1, "change": NSNull(),
      "testers": true, "experiment": NSNull(),
    ]
  }

  static func entitlement(
    key: String, entitled: Bool, value: FeatureValue, type: FeatureType?, used: Int64?,
    held: Int64, upgrades: [Upgrade]
  ) -> [String: Any] {
    var object: [String: Any] = [
      "key": key, "entitled": entitled, "value": raw(value), "sources": [Any](),
      "upgrades": upgrades.map { upgrade in
        [
          "plan": upgrade.plan, "name": upgrade.name, "move": upgrade.move.rawValue,
          "action": upgrade.action.rawValue, "reason": orNull(upgrade.reason),
        ] as [String: Any]
      },
    ]
    let kind: FeatureType =
      type ?? (used != nil ? .metered : value == .on || value == .amount(0) ? .boolean : .config)
    object["type"] = kind.rawValue
    if let used {
      object["used"] = used
      object["held"] = held
      object["remaining"] =
        switch value {
        case .amount(let allowance): max(0, allowance - used - held)
        default: "unlimited"
        }
      object["resetsAt"] = NSNull()
    }
    return object
  }

  static func raw(_ value: FeatureValue) -> Any {
    switch value {
    case .on: true
    case .amount(let amount): amount
    case .unlimited: "unlimited"
    }
  }

  static func planChangeFields(plan: String?, changed: Bool) -> [String: Any] {
    [
      "product": ["key": "app", "name": "App"],
      "plan": orNull(plan.map { ["id": "plan_\($0)", "key": $0, "name": $0.capitalized] }),
      "quantity": NSNull(), "effective": "now", "at": now, "until": NSNull(), "changed": changed,
    ]
  }

  static func planChangeObject(_ change: PlanChange) -> [String: Any] {
    [
      "product": orNull(change.product.map { ["key": $0.key, "name": $0.name] }),
      "plan": orNull(change.plan.map { ["id": $0.id, "key": $0.key, "name": $0.name] }),
      "quantity": orNull(change.quantity), "effective": change.effective.rawValue,
      "at": instant(change.at), "until": orNull(change.until.map(instant)),
      "changed": change.changed,
    ]
  }

  static func instant(_ date: Date) -> String {
    Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
  }

  static func orNull(_ value: Any?) -> Any { value ?? NSNull() }

  static func json(_ object: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
  }
}
