import Entitler
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A feature's value in a ``FakeCustomer``: on, an amount, unlimited, or a meter.
///
/// `true` is on, `false` the amount 0, and a whole number an amount.
public enum FakeValue: Sendable, Hashable, ExpressibleByBooleanLiteral,
  ExpressibleByIntegerLiteral
{
  /// An on/off feature that is on.
  case on
  /// An on/off feature that is off, or a setting's amount.
  case amount(Int64)
  /// A setting with no limit.
  case unlimited
  /// A metered feature with an allowance and the amount used so far.
  case metered(value: Int64, used: Int64)
  /// A metered feature with no limit and the amount used so far.
  case unlimitedMeter(used: Int64)

  /// `true` is ``on``, `false` the amount 0.
  public init(booleanLiteral value: Bool) { self = value ? .on : .amount(0) }

  /// An amount.
  public init(integerLiteral value: Int64) { self = .amount(value) }

  func entitlement(key: String) -> [String: Any] {
    switch self {
    case .on:
      FakeAnswers.entitlement(
        key: key, entitled: true, value: .on, type: .boolean, used: nil, held: 0, upgrades: [])
    case .amount(let amount):
      FakeAnswers.entitlement(
        key: key, entitled: amount > 0, value: .amount(amount), type: nil, used: nil, held: 0,
        upgrades: [])
    case .unlimited:
      FakeAnswers.entitlement(
        key: key, entitled: true, value: .unlimited, type: .config, used: nil, held: 0,
        upgrades: [])
    case .metered(let value, let used):
      FakeAnswers.entitlement(
        key: key, entitled: used < value, value: .amount(value), type: .metered, used: used,
        held: 0, upgrades: [])
    case .unlimitedMeter(let used):
      FakeAnswers.entitlement(
        key: key, entitled: true, value: .unlimited, type: .metered, used: used, held: 0,
        upgrades: [])
    }
  }
}

/// A write a ``FakeCustomer`` received, for assertions.
public struct FakeWrite: Sendable, Hashable {
  /// The method that sent it, such as `recordUsage` or `subscribe`.
  public let method: String
  /// The arguments it sent, each written as text: `["feature": "ai_credits", "amount": "3"]`.
  public let arguments: [String: String]
  /// The idempotency key it sent.
  public let idempotencyKey: String?
}

/// A customer for an app's own tests, which makes no request: its ``customer`` reads and writes
/// answers it keeps in memory, through the SDK's real decoder.
///
/// ```swift
/// let fake = FakeCustomer(["export_pdf": true, "ai_credits": .metered(value: 100, used: 97)])
/// try await exportReport(for: fake.customer)
/// #expect(fake.writes.map(\.method) == ["recordUsage"])
/// ```
///
/// - Reads answer complete checks and entitlement lists from the values. A key it does not hold
///   answers `404 feature_not_found`, so `isEntitled` answers its default.
/// - Usage writes move the meters by Entitler's rules: a gated report past the allowance is
///   refused, holds settle and release, and a reused key replays the first answer.
/// - Writes it does not model answer a plain success, made now; ``answer(_:with:status:)``
///   replaces any method's answer.
public final class FakeCustomer: Sendable {
  /// The customer to pass to the code under test.
  public let customer: ServerCustomer
  private let state: Locked<State>

  /// Creates a fake customer.
  ///
  /// - Parameters:
  ///   - values: Feature keys and their values.
  ///   - id: The customer's external id.
  ///   - plans: The answer `plans()` reads, from ``FakeAnswers/plans(held:options:customer:)``.
  ///   - pricing: The answer `pricing()` reads, from ``FakeAnswers/pricing(plans:customer:)``.
  public init(
    _ values: [String: FakeValue], id: String = "user_1", plans: Data? = nil,
    pricing: Data? = nil
  ) {
    let state = Locked(
      State(
        id: id, values: values, plans: plans ?? FakeAnswers.plans(customer: id),
        pricing: pricing ?? FakeAnswers.pricing(customer: id)))
    self.state = state
    let server = EntitlerServer(
      key: "ent_test_fake", cache: nil,
      options: EntitlerOptions(
        baseURL: URL(string: "https://fake.entitler.invalid")!, maxRetries: 0),
      exchange: { request in
        let (status, body, replayed) = state.update { $0.answer(request) }
        let headers = replayed ? ["Idempotent-Replayed": "true"] : [:]
        return (
          body,
          HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: headers)!
        )
      })
    customer = try! server.customer(id)
  }

  /// Every write received, in order.
  public var writes: [FakeWrite] { state.update { $0.writes } }

  /// Replaces one method's answer, such as `"subscribe"` or `"setPlan"`, with a body from
  /// ``FakeAnswers`` and its status.
  public func answer(_ method: String, with body: Data, status: Int = 200) {
    state.update { $0.replaced[method] = (status, body) }
  }
}

final class Locked<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  init(_ value: Value) { self.value = value }

  func update<Result>(_ change: (inout Value) -> Result) -> Result {
    lock.lock()
    defer { lock.unlock() }
    return change(&value)
  }
}

struct State {
  struct Meter {
    var allowance: Int64?
    var used: Int64
    var held: Int64 = 0
  }

  struct HoldRecord {
    let feature: String
    let amount: Int64
    var settled: Int64?
    var released = false
  }

  let id: String
  var values: [String: FakeValue]
  let plans: Data
  let pricing: Data
  var meters: [String: Meter] = [:]
  var holds: [String: HoldRecord] = [:]
  var reports: [String: (feature: String, amount: Int64)] = [:]
  var keys: [String: Data] = [:]
  var writes: [FakeWrite] = []
  var replaced: [String: (status: Int, body: Data)] = [:]
  var counter = 0

  init(id: String, values: [String: FakeValue], plans: Data, pricing: Data) {
    self.id = id
    self.values = values
    self.plans = plans
    self.pricing = pricing
    for (key, value) in values {
      switch value {
      case .metered(let allowance, let used): meters[key] = Meter(allowance: allowance, used: used)
      case .unlimitedMeter(let used): meters[key] = Meter(allowance: nil, used: used)
      default: break
      }
    }
  }

  mutating func answer(_ request: URLRequest) -> (Int, Data, Bool) {
    let method = request.httpMethod ?? "GET"
    let path =
      request.url.map {
        URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? $0.path
      } ?? ""
    let segments = path.split(separator: "/").dropFirst(2).map {
      String($0).removingPercentEncoding ?? String($0)
    }
    let body =
      request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      ?? [:]
    let name = Self.method(method, segments)
    if method == "GET" {
      if let replaced = replaced[name] { return (replaced.status, replaced.body, false) }
      return read(segments)
    }
    let key = request.value(forHTTPHeaderField: "Idempotency-Key")
    var arguments = body.mapValues { "\($0)" }
    if let query = request.url?.query { arguments["query"] = query }
    if let last = segments.last, segments.count > 1,
      !["usage", "holds", "subscription"].contains(last)
    {
      arguments["id"] = last
    }
    writes.append(FakeWrite(method: name, arguments: arguments, idempotencyKey: key))
    if let key, let kept = keys["\(name) \(key)"] { return (200, kept, true) }
    let (status, answer, keep) =
      replaced[name].map { ($0.status, $0.body, true) } ?? write(name, segments, body)
    if keep, (200..<300).contains(status), let key { keys["\(name) \(key)"] = answer }
    return (status, answer, false)
  }

  static func method(_ method: String, _ segments: [String]) -> String {
    switch (method, segments.first, segments.count, segments.last) {
    case ("GET", "entitlements", 2, _): "check"
    case ("GET", "entitlements", _, _): "entitlements"
    case ("GET", "plans", _, _): "plans"
    case ("GET", "pricing", _, _): "pricing"
    case ("GET", "usage", _, _): "usage"
    case ("GET", nil, _, _): "details"
    case ("GET", _, _, _): "billing"
    case ("POST", "usage", 1, _): "recordUsage"
    case ("POST", "usage", 2, _): "holdUsage"
    case ("POST", "usage", _, _): "settleUsage"
    case ("DELETE", "usage", 3, _): "releaseUsage"
    case ("DELETE", "usage", _, _): "cancelUsage"
    case ("POST", "subscription", _, _): "subscribe"
    case ("DELETE", "subscription", _, "pending"): "undoPendingChange"
    case ("DELETE", "subscription", _, _): "cancel"
    case ("POST", "billing-portal", _, _): "billingPortal"
    case ("POST", "billing", _, _): "syncBilling"
    case ("PUT", "plan", _, _): "setPlan"
    case ("PUT", "add-ons", _, _): "setAddOn"
    case ("POST", "grants", _, _): "grant"
    case ("DELETE", "grants", _, _): "revokeGrant"
    case ("POST", "meters", _, _): "adjustMeter"
    case ("POST", "tokens", _, _): "token"
    case ("POST", "snapshots", _, _): "snapshot"
    case ("PUT", "track", _, _): "setTrack"
    case ("PUT", nil, _, _): "register"
    case ("PATCH", nil, _, _): "update"
    case ("DELETE", nil, _, _): "erase"
    default: "\(method) \(segments.joined(separator: "/"))"
    }
  }

  func read(_ segments: [String]) -> (Int, Data, Bool) {
    switch segments.first {
    case "entitlements" where segments.count == 2:
      let key = segments[1]
      guard let value = values[key] else {
        return (
          404,
          FakeAnswers.error(
            code: .featureNotFound, message: "No feature has the key \(key) in this catalogue."),
          false
        )
      }
      var object = value.entitlement(key: key)
      if let meter = meters[key] { object.merge(meterFields(meter)) { $1 } }
      object["feature"] = object.removeValue(forKey: "key")
      object["customer"] = id
      object["asOf"] = FakeAnswers.now
      return (200, FakeAnswers.json(object.merging(FakeAnswers.context) { $1 }), false)
    case "entitlements":
      let items = values.keys.sorted().map { key in
        var object = values[key]!.entitlement(key: key)
        if let meter = meters[key] { object.merge(meterFields(meter)) { $1 } }
        return object
      }
      return (
        200,
        FakeAnswers.json(
          ["customer": id, "asOf": FakeAnswers.now, "entitlements": items].merging(
            FakeAnswers.context
          ) { $1 }), false
      )
    case "plans": return (200, plans, false)
    case "pricing": return (200, pricing, false)
    default:
      return (
        404, FakeAnswers.error(code: .notFound, message: "This fake customer has no answer here."),
        false
      )
    }
  }

  func meterFields(_ meter: Meter) -> [String: Any] {
    [
      "used": meter.used, "held": meter.held,
      "remaining": meter.allowance.map { max(0, $0 - meter.used - meter.held) as Any }
        ?? "unlimited",
      "entitled": meter.allowance.map { meter.used + meter.held < $0 } ?? true,
    ]
  }

  mutating func write(_ name: String, _ segments: [String], _ body: [String: Any]) -> (
    Int, Data, Bool
  ) {
    switch name {
    case "recordUsage":
      return report(
        body["feature"] as? String ?? "", amount: (body["amount"] as? NSNumber)?.int64Value ?? 0,
        observe: body["mode"] as? String == "observe")
    case "holdUsage":
      return hold(
        body["feature"] as? String ?? "", amount: (body["amount"] as? NSNumber)?.int64Value ?? 0,
        ttl: (body["ttlSeconds"] as? NSNumber)?.doubleValue ?? 300)
    case "settleUsage":
      return settle(segments[2], amount: (body["amount"] as? NSNumber)?.int64Value ?? 0)
    case "releaseUsage": return release(segments[2])
    case "adjustMeter":
      return adjust(
        segments[1], by: (body["by"] as? NSNumber)?.int64Value,
        to: (body["to"] as? NSNumber)?.int64Value)
    case "cancelUsage": return cancelReport(segments[1])
    case "subscribe": return (200, FakeAnswers.subscribeDone(plan: body["plan"] as? String), true)
    case "setPlan": return (200, FakeAnswers.planChange(plan: body["plan"] as? String), true)
    case "setAddOn":
      let quantity = (body["quantity"] as? NSNumber)?.int64Value ?? 0
      return (
        200, FakeAnswers.planChange(plan: quantity > 0 ? segments[1] : nil, quantity: quantity),
        true
      )
    case "cancel", "undoPendingChange": return (200, FakeAnswers.planChange(plan: nil), true)
    case "grant":
      counter += 1
      return (
        201,
        FakeAnswers.grantChange(
          id: "grant_\(counter)", feature: body["feature"] as? String ?? "",
          value: body["value"] as? String ?? "true", reason: body["reason"] as? String ?? "",
          actor: body["actor"] as? String), true
      )
    case "revokeGrant":
      return (200, FakeAnswers.grantChange(id: segments[1], feature: "", revoked: true), true)
    case "billingPortal":
      return (
        200, FakeAnswers.providerPage(url: URL(string: "https://billing.fake.invalid")!), true
      )
    case "syncBilling": return (200, FakeAnswers.billingSync(), true)
    case "register": return (200, FakeAnswers.registeredCustomer(id: id, created: false), true)
    case "token": return (201, FakeAnswers.customerToken(customer: id), true)
    case "setTrack":
      return (200, FakeAnswers.customerTrack(customer: id, track: body["track"] as? String), true)
    case "erase": return (204, Data(), true)
    default:
      return (
        404, FakeAnswers.error(code: .notFound, message: "This fake customer has no answer here."),
        false
      )
    }
  }

  func usage(
    _ feature: String, outcome: UsageOutcome, amount: Int64, holdID: String? = nil,
    refusal: UsageRefusal? = nil, mode: UsageMode = .gate, change: Int64 = 0, id: String? = nil,
    expiresAt: Date? = nil
  ) -> Data {
    let meter = meters[feature] ?? Meter(allowance: 0, used: 0)
    return FakeAnswers.usageResult(
      feature: feature, outcome: outcome, amount: amount,
      value: meter.allowance.map(FeatureValue.amount) ?? .unlimited, used: meter.used,
      held: meter.held, holdID: holdID, refusal: refusal, mode: mode, meterChange: change,
      overBy: meter.allowance.map { max(0, meter.used - $0) } ?? 0, id: id, expiresAt: expiresAt,
      customer: self.id)
  }

  func notMetered(_ feature: String) -> (Int, Data, Bool)? {
    guard meters[feature] == nil else { return nil }
    return (
      400, FakeAnswers.error(code: .notMetered, message: "\(feature) is not a metered feature."),
      false
    )
  }

  func refusal(_ feature: String, _ amount: Int64) -> UsageRefusal? {
    guard let meter = meters[feature], let allowance = meter.allowance else { return nil }
    if allowance == 0 { return .notEntitled }
    return meter.used + meter.held + amount > allowance ? .overAllowance : nil
  }

  mutating func report(_ feature: String, amount: Int64, observe: Bool) -> (Int, Data, Bool) {
    if let failure = notMetered(feature) { return failure }
    if !observe, let refusal = refusal(feature, amount) {
      return (
        200, usage(feature, outcome: .refused, amount: amount, refusal: refusal), false
      )
    }
    meters[feature]!.used += amount
    counter += 1
    reports["usage_\(counter)"] = (feature, amount)
    return (
      201,
      usage(
        feature, outcome: .recorded, amount: amount, mode: observe ? .observe : .gate,
        change: amount, id: "usage_\(counter)"), true
    )
  }

  mutating func hold(_ feature: String, amount: Int64, ttl: TimeInterval) -> (Int, Data, Bool) {
    if let failure = notMetered(feature) { return failure }
    if let refusal = refusal(feature, amount) {
      return (200, usage(feature, outcome: .refused, amount: amount, refusal: refusal), false)
    }
    counter += 1
    let id = "hold_\(counter)"
    holds[id] = HoldRecord(feature: feature, amount: amount)
    meters[feature]!.held += amount
    return (
      201,
      usage(
        feature, outcome: .held, amount: amount, holdID: id,
        expiresAt: Date().addingTimeInterval(ttl)), true
    )
  }

  mutating func settle(_ id: String, amount: Int64) -> (Int, Data, Bool) {
    guard var hold = holds[id] else {
      return (404, FakeAnswers.error(code: .notFound, message: "No hold has the id \(id)."), false)
    }
    if hold.released {
      return (
        409, FakeAnswers.error(code: .holdReleased, message: "The hold was released."), false
      )
    }
    if let settled = hold.settled {
      guard settled == amount else {
        return (409, FakeAnswers.error(code: .holdSettled, message: "The hold was settled."), false)
      }
      return (200, usage(hold.feature, outcome: .duplicate, amount: amount, holdID: id), false)
    }
    guard amount <= hold.amount else {
      return (
        400,
        FakeAnswers.error(
          code: .invalidAmount, message: "Settle at most the held amount, \(hold.amount)."),
        false
      )
    }
    hold.settled = amount
    holds[id] = hold
    meters[hold.feature]!.held -= hold.amount
    meters[hold.feature]!.used += amount
    return (200, usage(hold.feature, outcome: .settled, amount: amount, holdID: id), true)
  }

  mutating func release(_ id: String) -> (Int, Data, Bool) {
    guard var hold = holds[id] else {
      return (404, FakeAnswers.error(code: .notFound, message: "No hold has the id \(id)."), false)
    }
    if hold.settled != nil {
      return (409, FakeAnswers.error(code: .holdSettled, message: "The hold was settled."), false)
    }
    if !hold.released {
      hold.released = true
      holds[id] = hold
      meters[hold.feature]!.held -= hold.amount
    }
    return (200, usage(hold.feature, outcome: .released, amount: hold.amount, holdID: id), true)
  }

  mutating func adjust(_ feature: String, by: Int64?, to: Int64?) -> (Int, Data, Bool) {
    if let failure = notMetered(feature) { return failure }
    let before = meters[feature]!.used
    meters[feature]!.used = max(0, to ?? before + (by ?? 0))
    let change = meters[feature]!.used - before
    counter += 1
    return (
      200,
      usage(
        feature, outcome: .adjusted, amount: abs(change), change: change,
        id: change == 0 ? nil : "usage_\(counter)"), true
    )
  }

  mutating func cancelReport(_ id: String) -> (Int, Data, Bool) {
    guard let report = reports.removeValue(forKey: id) else {
      return (
        404, FakeAnswers.error(code: .notFound, message: "No usage report has the id \(id)."),
        false
      )
    }
    if var meter = meters[report.feature] {
      meter.used = max(0, meter.used - report.amount)
      meters[report.feature] = meter
    }
    return (
      200,
      usage(
        report.feature, outcome: .cancelled, amount: report.amount, change: -report.amount, id: id),
      true
    )
  }
}
