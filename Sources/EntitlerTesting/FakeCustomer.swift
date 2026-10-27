import Entitler
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A feature's value in a ``FakeCustomer``: `true` is on, `false` off, a whole number an amount.
public enum FakeValue: Sendable, Hashable, ExpressibleByBooleanLiteral,
  ExpressibleByIntegerLiteral
{
  /// An on/off feature, on or off.
  case `switch`(Bool)
  /// A setting's amount.
  case amount(Int64)
  /// A setting with no limit.
  case unlimited
  /// A metered feature with an allowance, and how much is used so far.
  case metered(limit: Int64, used: Int64 = 0)
  /// A metered feature with no limit, and how much is used so far.
  case unlimitedMeter(used: Int64 = 0)

  /// `true` is on, `false` off.
  public init(booleanLiteral value: Bool) { self = .switch(value) }

  /// An amount.
  public init(integerLiteral value: Int64) { self = .amount(value) }
}

/// A write a ``FakeCustomer`` received, for assertions.
public struct FakeWrite: Sendable, Hashable {
  /// What it was: `recordUsage`, `holdUsage`, `settleUsage` or `releaseUsage`.
  public let method: String
  /// The feature's key, or the hold's id for `settleUsage` and `releaseUsage`.
  public let target: String
  /// The amount it sent, or `nil` for `releaseUsage`.
  public let amount: Int64?
  /// The idempotency key it sent, or `nil`.
  public let idempotencyKey: String?
}

/// A customer for your app's own tests that makes no request. Its customers read and write answers
/// it keeps in memory, through the SDK's real decoding.
///
/// ```swift
/// let fake = try FakeCustomer(["export_pdf": true, "ai_credits": .metered(limit: 100, used: 97)])
/// try await exportReport(for: fake.customer)
/// #expect(fake.writes.map(\.method) == ["recordUsage"])
/// ```
///
/// - Checks and entitlement lists answer from the values. A key it doesn't hold is refused with
///   ``Reason/featureNotFound``, so `isEntitled` answers its default.
/// - Usage moves the meters as Entitler does: a gated report or a hold that doesn't fit is
///   refused, holds settle and release, and a repeated idempotency key replays the first answer.
/// - Every other call is refused with `Unimplemented`.
public final class FakeCustomer: Sendable {
  /// The customer, as the server client names it.
  public let customer: ServerCustomer
  /// The same customer, as an app's client signs in as them.
  public let me: SignedInCustomer
  private let state: Locked

  /// Creates a fake customer.
  ///
  /// - Parameters:
  ///   - values: Feature keys and their values.
  ///   - id: The customer's external id.
  /// - Throws: ``ArgumentError`` for a blank id, or for `me`.
  public convenience init(_ values: [String: FakeValue], id: String = "user_1") throws {
    try self.init(values, id: id, clock: Date.init)
  }

  init(_ values: [String: FakeValue], id: String, clock: @escaping @Sendable () -> Date) throws {
    let state = Locked(FakeState(id: id, values: values, clock: clock))
    self.state = state
    let options = EntitlerOptions(
      baseURL: URL(string: "https://fake.entitler.invalid")!, maxRetries: 0)
    let exchange: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse) = { request in
      let (status, body) = state.update { $0.answer(request) }
      return (
        body,
        HTTPURLResponse(
          url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
      )
    }
    customer = try EntitlerServer(key: "fake", options: options, exchange: exchange).customer(id)
    me = try EntitlerClient(token: "fake", options: options, exchange: exchange).me
  }

  /// Every write received, in order.
  public var writes: [FakeWrite] { state.update { $0.writes } }

  /// How much of a metered feature is used now, settled holds included.
  public func used(_ feature: String) -> Int64 { state.update { $0.used[feature] ?? 0 } }
}

final class Locked: @unchecked Sendable {
  private let lock = NSLock()
  private var value: FakeState

  init(_ value: FakeState) { self.value = value }

  func update<Result>(_ change: (inout FakeState) -> Result) -> Result {
    lock.lock()
    defer { lock.unlock() }
    return change(&value)
  }
}

struct FakeState {
  struct Hold {
    let feature: String
    let amount: Int64
    let expiresAt: Date
  }

  let id: String
  let values: [String: FakeValue]
  let clock: @Sendable () -> Date
  var used: [String: Int64]
  var held: [String: Int64] = [:]
  var holds: [String: Hold] = [:]
  var replies: [String: [String: Any]] = [:]
  var writes: [FakeWrite] = []

  init(id: String, values: [String: FakeValue], clock: @escaping @Sendable () -> Date) {
    self.id = id
    self.values = values
    self.clock = clock
    used = values.compactMapValues {
      switch $0 {
      case .metered(_, let used), .unlimitedMeter(let used): used
      default: nil
      }
    }
  }

  mutating func answer(_ request: URLRequest) -> (Int, Data) {
    expireHolds()
    let path = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
    let parts = (path?.percentEncodedPath ?? "").split(separator: "/").map {
      $0.removingPercentEncoding ?? String($0)
    }
    guard parts.count >= 4, parts[0] == "v1", parts[1] == "customers",
      [id, "me"].contains(parts[2])
    else {
      return refused(501, "Unimplemented", "FAKE_UNSUPPORTED")
    }
    let rest = Array(parts.dropFirst(3))
    let body =
      (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
    switch (request.httpMethod ?? "GET", rest.count, rest.first) {
    case ("GET", 1, "entitlements"):
      return (200, json(context(["entitlements": values.keys.sorted().map(entitlement)])))
    case ("GET", 2, "entitlements"):
      guard values[rest[1]] != nil else { return refused(404, "NotFound", "FEATURE_NOT_FOUND") }
      return (200, json(context(["entitlement": entitlement(rest[1])])))
    case ("POST", 1, "usage"):
      return replay(body, "recordUsage") { state in state.report(body) }
    case ("POST", 2, "usage") where rest[1] == "holds":
      return replay(body, "holdUsage") { state in state.hold(body) }
    case ("POST", 3, "usage") where rest[1] == "holds" && rest[2].hasSuffix(":settle"):
      return close(String(rest[2].dropLast(":settle".count)), settling: int(body["amount"]))
    case ("DELETE", 3, "usage") where rest[1] == "holds":
      return close(rest[2], settling: nil)
    default:
      return refused(501, "Unimplemented", "FAKE_UNSUPPORTED")
    }
  }

  private mutating func replay(
    _ body: [String: Any], _ method: String, _ write: (inout FakeState) -> (Int, [String: Any])
  ) -> (Int, Data) {
    let key = method + "\n" + (body["idempotencyKey"] as? String ?? "")
    if var reply = replies[key] {
      var usage = reply["usage"] as? [String: Any] ?? [:]
      usage["replayed"] = true
      if let hold = usage["holdId"] as? String {
        usage["outcome"] = "USAGE_OUTCOME_DUPLICATE"
        if holds[hold] == nil { usage["expiresAtMs"] = int(reply["asOf"]) * 1000 }
      }
      reply["usage"] = usage
      return (200, json(["tracked": reply]))
    }
    let (status, reply) = write(&self)
    if status == 200 { replies[key] = reply }
    return (status, json(status == 200 ? ["tracked": reply] : reply))
  }

  private mutating func report(_ body: [String: Any]) -> (Int, [String: Any]) {
    let feature = body["featureKey"] as? String ?? ""
    let amount = int(body["amount"])
    let mode = body["mode"] as? String ?? "USAGE_MODE_GATE"
    let observe = mode == "USAGE_MODE_OBSERVE"
    writes.append(
      FakeWrite(
        method: "recordUsage", target: feature, amount: amount,
        idempotencyKey: body["idempotencyKey"] as? String))
    guard let limit = meterLimit(feature) else { return refusedObject(feature) }
    let fits =
      limit.map { used[feature, default: 0] + held[feature, default: 0] + amount <= $0 } ?? true
    guard fits || observe else {
      return (200, tracked(feature, outcome: "REFUSED", amount: amount, refusal: "OVER_ALLOWANCE"))
    }
    used[feature, default: 0] += amount
    return (200, tracked(feature, outcome: "RECORDED", amount: amount, change: amount, mode: mode))
  }

  private mutating func hold(_ body: [String: Any]) -> (Int, [String: Any]) {
    let feature = body["featureKey"] as? String ?? ""
    let amount = int(body["amount"])
    writes.append(
      FakeWrite(
        method: "holdUsage", target: feature, amount: amount,
        idempotencyKey: body["idempotencyKey"] as? String))
    guard let limit = meterLimit(feature) else { return refusedObject(feature) }
    guard
      limit.map({ used[feature, default: 0] + held[feature, default: 0] + amount <= $0 }) ?? true
    else {
      return (200, tracked(feature, outcome: "REFUSED", amount: amount, refusal: "OVER_ALLOWANCE"))
    }
    let id = "ho_\(writes.count)"
    let ttl = int(body["ttlSeconds"]) == 0 ? 300 : int(body["ttlSeconds"])
    let expiresAt = clock().addingTimeInterval(TimeInterval(ttl))
    holds[id] = Hold(feature: feature, amount: amount, expiresAt: expiresAt)
    held[feature, default: 0] += amount
    return (
      200,
      tracked(
        feature, outcome: "HELD", amount: amount, change: amount, hold: id,
        expiresAtMs: Int64(expiresAt.timeIntervalSince1970 * 1000))
    )
  }

  private mutating func expireHolds() {
    let now = clock()
    for (id, hold) in holds where hold.expiresAt <= now {
      holds[id] = nil
      held[hold.feature, default: 0] -= hold.amount
    }
  }

  private mutating func close(_ id: String, settling amount: Int64?) -> (Int, Data) {
    writes.append(
      FakeWrite(
        method: amount == nil ? "releaseUsage" : "settleUsage", target: id, amount: amount,
        idempotencyKey: nil))
    guard let hold = holds[id] else {
      return refused(409, "FailedPrecondition", "HOLD_EXPIRED")
    }
    guard (amount ?? 0) <= hold.amount else { return refused(400, "InvalidArgument", nil) }
    holds[id] = nil
    held[hold.feature, default: 0] -= hold.amount
    used[hold.feature, default: 0] += amount ?? 0
    return (
      200,
      json([
        "tracked": tracked(
          hold.feature, outcome: amount == nil ? "RELEASED" : "SETTLED",
          amount: amount ?? hold.amount,
          change: amount ?? 0, hold: id)
      ])
    )
  }

  private func meterLimit(_ feature: String) -> Int64?? {
    switch values[feature] {
    case .metered(let limit, _): .some(limit)
    case .unlimitedMeter: .some(nil)
    default: nil
    }
  }

  private func refusedObject(_ feature: String) -> (Int, [String: Any]) {
    guard values[feature] != nil else {
      return (404, errorObject("NotFound", "FEATURE_NOT_FOUND"))
    }
    return (200, tracked(feature, outcome: "REFUSED", amount: 0, refusal: "NOT_ENTITLED"))
  }

  private func tracked(
    _ feature: String, outcome: String, amount: Int64, change: Int64 = 0,
    refusal: String? = nil, hold: String? = nil, expiresAtMs: Int64? = nil,
    mode: String = "USAGE_MODE_GATE"
  ) -> [String: Any] {
    var usage: [String: Any] = [
      "outcome": "USAGE_OUTCOME_\(outcome)", "mode": mode, "amount": amount,
      "meterChange": change, "overBy": overBy(feature), "late": false, "replayed": false,
      "saturated": false,
    ]
    usage["refusal"] = refusal.map { "USAGE_REFUSAL_\($0)" }
    usage["holdId"] = hold
    usage["expiresAtMs"] = expiresAtMs
    return context(["entitlement": entitlement(feature), "usage": usage])
  }

  private func overBy(_ feature: String) -> Int64 {
    guard case .metered(let limit, _) = values[feature] else { return 0 }
    return max(0, used[feature, default: 0] - limit)
  }

  private func context(_ fields: [String: Any]) -> [String: Any] {
    fields.merging(
      ["asOf": Int64(clock().timeIntervalSince1970), "customer": ["externalId": id]]
    ) { first, _ in first }
  }

  private func entitlement(_ feature: String) -> [String: Any] {
    var answer: [String: Any] = [
      "featureKey": feature, "decimals": 0, "currency": "", "sources": [], "upgrades": [],
    ]
    let used = used[feature, default: 0]
    let held = held[feature, default: 0]
    switch values[feature] ?? .switch(false) {
    case .switch(let on):
      answer["kind"] = "ENTITLED_FEATURE_KIND_SWITCH"
      answer["entitled"] = on
      answer["value"] = ["switch": on]
    case .amount(let amount):
      answer["kind"] = "ENTITLED_FEATURE_KIND_CONFIGURATION"
      answer["entitled"] = amount > 0
      answer["value"] = ["configuration": ["count": amount]]
    case .unlimited:
      answer["kind"] = "ENTITLED_FEATURE_KIND_CONFIGURATION"
      answer["entitled"] = true
      answer["value"] = ["configuration": ["unlimited": [String: Any]()]]
    case .metered(let limit, _):
      answer["kind"] = "ENTITLED_FEATURE_KIND_METERED"
      answer["entitled"] = used + held < limit
      answer["value"] = ["metered": ["count": limit]]
      answer["meter"] = [
        "used": used, "held": held, "banked": 0,
        "remaining": ["count": max(0, limit - used - held)],
      ]
    case .unlimitedMeter:
      answer["kind"] = "ENTITLED_FEATURE_KIND_METERED"
      answer["entitled"] = true
      answer["value"] = ["metered": ["unlimited": [String: Any]()]]
      answer["meter"] = [
        "used": used, "held": held, "banked": 0,
        "remaining": ["unlimited": [String: Any]()],
      ]
    }
    return answer
  }
}

private func int(_ value: Any?) -> Int64 { (value as? NSNumber)?.int64Value ?? 0 }

private func json(_ object: [String: Any]) -> Data {
  (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
}

private func errorObject(_ code: String, _ reason: String?) -> [String: Any] {
  ["error": ["code": code, "reason": reason as Any? ?? NSNull(), "parameters": [String: String]()]]
}

private func refused(_ status: Int, _ code: String, _ reason: String?) -> (Int, Data) {
  (status, json(errorObject(code, reason)))
}
