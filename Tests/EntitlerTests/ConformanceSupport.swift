import Foundation
import Testing

@testable import Entitler

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

typealias JSONObject = [String: Any]

enum Conformance {
  static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Conformance")

  static let fileNames = [
    "cache-keys", "path-encoding", "idempotency-keys", "retry-timing", "token-refresh",
    "construction", "values", "answers", "errors", "snapshots",
  ]

  static let conditionsSwiftMeets: Set<String> = [
    "the type of clockSkewSeconds can hold a negative number"
  ]

  static let conditionsSwiftRulesOut: Set<String> = [
    "strings can hold lone surrogates",
    "an in-app read can be given asOf",
    "a write that requires idempotencyKey can reach the SDK without one",
    "a batch event can reach the SDK without its idempotencyKey",
    "the in-app client can be built from no credential or from a combination section 4.2 does not list",
    "the in-app client can be given a custom cache store",
  ]

  nonisolated(unsafe) static let files: [String: [JSONObject]] = {
    var files: [String: [JSONObject]] = [:]
    for name in fileNames {
      let data = try! Data(contentsOf: directory.appendingPathComponent(name + ".json"))
      let object = try! JSONSerialization.jsonObject(with: data) as! JSONObject
      files[name] = object["cases"] as? [JSONObject] ?? []
    }
    return files
  }()

  static func names(_ file: String) -> [String] {
    (files[file] ?? []).filter(applies).compactMap { $0["name"] as? String }
  }

  static func skipped(_ file: String) -> [String] {
    (files[file] ?? []).filter { !applies($0) }.compactMap { $0["name"] as? String }
  }

  static func applies(_ testCase: JSONObject) -> Bool {
    guard let condition = testCase["appliesWhere"] as? String else { return true }
    return !conditionsSwiftRulesOut.contains(condition)
  }

  static func testCase(_ file: String, _ name: String) -> JSONObject {
    files[file]!.first { $0["name"] as? String == name }!
  }
}

let conformanceCheckBody =
  #"{"customer":"user_42","asOf":"2026-07-01T09:30:00.000Z","feature":"export_pdf","type":"boolean","entitled":true,"value":true,"sources":[],"upgrades":[],"environment":{"id":"e","name":"Development","kind":"test"},"track":{"id":"t","name":"All customers"},"release":2,"change":null,"testers":true,"experiment":null}"#

private let context =
  #""environment":{"id":"e","name":"Development","kind":"test"},"track":{"id":"t","name":"All customers"},"release":2,"change":null,"testers":true,"experiment":null"#

func conformanceBody(forPath path: String) -> String {
  if path.hasSuffix("/pricing/features") {
    return #"{\#(context),"features":[]}"#
  }
  if path.hasSuffix("/pricing") {
    return #"{\#(context),"customer":null,"defaultPlan":null,"products":[],"plans":[]}"#
  }
  if path.hasSuffix("/plans") {
    return #"{"customer":"u","asOf":"2026-07-01T09:30:00.000Z","held":[],"options":[],\#(context)}"#
  }
  if path.hasSuffix("/entitlements") {
    return #"{"customer":"u","asOf":"2026-07-01T09:30:00.000Z","entitlements":[],\#(context)}"#
  }
  return conformanceCheckBody
}

final class KeyLog: CacheStore {
  let asked = Box<[String]>([])
  func entry(forKey key: String) async throws -> CacheEntry? {
    asked.with { $0.append(key) }
    return nil
  }
  func setEntry(_ entry: CacheEntry, forKey key: String, timeToLive: TimeInterval) async throws {}
}

func instant(_ value: Any?) -> Date? {
  (value as? String).flatMap(parseInstant)
}

func expectInstant(
  _ actual: Date?, _ expected: Any?, sourceLocation: SourceLocation = #_sourceLocation
) {
  guard let expected = expected as? JSONObject, let millis = expected["epochMillis"] as? Double
  else {
    #expect(actual == nil, sourceLocation: sourceLocation)
    return
  }
  #expect(
    actual.map { ($0.timeIntervalSince1970 * 1000).rounded() } == millis,
    sourceLocation: sourceLocation)
}

func expectValue(
  _ actual: FeatureValue?, _ expected: Any?, sourceLocation: SourceLocation = #_sourceLocation
) {
  guard let expected = expected as? JSONObject else {
    #expect(actual == nil, sourceLocation: sourceLocation)
    return
  }
  let wanted: FeatureValue? =
    switch expected["kind"] as? String {
    case "on": .on
    case "unlimited": .unlimited
    case "amount": (expected["amount"] as? NSNumber).map { .amount($0.int64Value) }
    default: nil
    }
  #expect(actual == wanted, sourceLocation: sourceLocation)
}

func raw(_ expected: Any?) -> String? {
  if let text = expected as? String { return text }
  return (expected as? JSONObject)?["unknown"] as? String
}

func expectArgumentError(
  _ outcome: JSONObject, _ body: () async throws -> Void,
  sourceLocation: SourceLocation = #_sourceLocation
) async {
  do {
    try await body()
    Issue.record("Expected \(outcome["message"] ?? "")", sourceLocation: sourceLocation)
  } catch let error as ArgumentError {
    #expect(error.message == outcome["message"] as? String, sourceLocation: sourceLocation)
  } catch {
    Issue.record("Unexpected \(error)", sourceLocation: sourceLocation)
  }
}

func headers(_ object: Any?) -> [String: String] {
  (object as? [String: String]) ?? [:]
}

func isUUIDv4(_ text: String?) -> Bool {
  guard let text else { return false }
  return text.lowercased().wholeMatch(
    of: /[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/) != nil
}

enum Shape {
  static func canonical(_ value: Any) -> String {
    let data = try? JSONSerialization.data(
      withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
    return data.map { String(decoding: $0, as: UTF8.self) } ?? "\(value)"
  }

  static func expect(
    _ actual: Any, _ expected: Any?, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(
      canonical(actual) == canonical(expected ?? NSNull()), sourceLocation: sourceLocation)
  }

  static func optional(_ value: Any?) -> Any { value ?? NSNull() }

  static func name<Value: RawRepresentable>(_ value: Value?) -> Any where Value.RawValue == String {
    guard let value else { return NSNull() }
    return Mirror(reflecting: value).children.first?.label == "unknown"
      ? ["unknown": value.rawValue] : value.rawValue
  }

  static func code(_ code: ErrorCode) -> Any {
    code.isKnown ? code.rawValue : ["unknown": code.rawValue]
  }

  static func instant(_ date: Date?) -> Any {
    guard let date else { return NSNull() }
    return [
      "instant": formatInstant(date),
      "epochMillis": Int64((date.timeIntervalSince1970 * 1000).rounded()),
    ] as JSONObject
  }

  static func value(_ value: FeatureValue?) -> Any {
    switch value {
    case nil: NSNull()
    case .on: ["kind": "on"]
    case .unlimited: ["kind": "unlimited"]
    case .amount(let amount): ["kind": "amount", "amount": amount] as JSONObject
    }
  }

  static func product(_ product: Product?) -> Any {
    product.map { ["key": $0.key, "name": $0.name] } ?? NSNull()
  }

  static func plan(_ plan: PlanRef?, kind: Bool = false) -> Any {
    guard let plan else { return NSNull() }
    var object: JSONObject = ["id": plan.id, "key": plan.key, "name": plan.name]
    if kind { object["kind"] = name(plan.kind) }
    return object
  }

  static func period(_ period: Period?) -> Any {
    period.map { ["key": $0.key, "label": $0.label] } ?? NSNull()
  }

  static func upgrades(_ upgrades: [Upgrade]) -> Any {
    upgrades.map {
      [
        "plan": $0.plan, "name": $0.name, "move": name($0.move), "action": name($0.action),
        "reason": optional($0.reason),
      ] as JSONObject
    }
  }

  static func apiError(_ error: APIError) -> JSONObject {
    [
      "kind": "ApiError", "status": error.status, "code": code(error.code),
      "message": error.message, "requestId": optional(error.requestID),
      "retryAfterSeconds": optional(error.retryAfter.map { Int64($0) }),
      "idempotencyKey": optional(error.idempotencyKey),
      "payment": optional(
        error.payment.map { ["status": name($0.status), "url": optional($0.url)] as JSONObject }),
    ]
  }
}

struct Attempts {
  struct Wait: Equatable {
    let min: Double
    let max: Double
  }

  var attempts = 0
  var waits: [Wait] = []
  var providerCalls = 0
  var keys: [String?] = []
  var error: EntitlerError?

  static func run(
    answers: [JSONObject], now: String?, maxRetries: Int, maxRetryDelay: Double,
    credential: JSONObject = ["kind": "key", "key": "ent_test_conformance_server_key"],
    write: Bool = false,
    provider: [String]? = nil
  ) async throws -> Attempts {
    let queue = Box(answers)
    let waits = Box<[Wait]>([])
    let slept = Box<Wait?>(nil)
    let arrived = Box(0)
    let api = FakeAPI(host: "*") { _ in
      if arrived.with({ count in
        defer { count += 1 }
        return count > 0
      }) {
        waits.with {
          $0.append(
            slept.with { value in
              defer { value = nil }
              return value ?? Wait(min: 0, max: 0)
            })
        }
      }
      let answer = queue.with { $0.isEmpty ? ["status": 599] : $0.removeFirst() }
      switch answer["failure"] as? String {
      case "connection": return .failure(.cannotConnectToHost)
      case "timeout": return .failure(.timedOut)
      case "cut-off": return .cutOffJSON
      default:
        let body =
          answer["body"].flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
        return Reply(
          status: answer["status"] as! Int, headers: headers(answer["headers"]), body: body)
      }
    }
    if let now = instant(now) { api.clock.with { $0 = now } }
    let pending = Box<ClosedRange<Double>?>(nil)
    var hooks = api.hooks
    let clock = api.clock
    hooks.random = { range in
      pending.with { $0 = range }
      return range.upperBound
    }
    hooks.sleep = { seconds in
      let range = pending.with { value in
        defer { value = nil }
        return value
      }
      slept.with {
        $0 =
          range.map { Wait(min: $0.lowerBound, max: $0.upperBound) }
          ?? Wait(min: seconds, max: seconds)
      }
      clock.with { $0 += seconds }
    }
    let calls = Box(0)
    let options = api.options {
      $0.maxRetries = maxRetries
      $0.maxRetryDelay = maxRetryDelay
    }
    let tokens = provider ?? (credential["tokens"] as? [String]) ?? []
    let customer: any Customer
    let close: () -> Void
    switch credential["kind"] as? String ?? (provider == nil ? nil : "customerTokenProvider") {
    case "customerToken":
      let client = try EntitlerClient(
        token: credential["token"] as! String, cache: nil, options: options)
      customer = client.me
      close = client.close
    case "customerTokenProvider":
      let client = try EntitlerClient(
        tokenProvider: {
          let index = calls.with {
            $0 += 1
            return $0 - 1
          }
          return tokens[min(index, tokens.count - 1)]
        }, cache: nil, options: options)
      customer = client.me
      close = client.close
    default:
      let server = try EntitlerServer(
        key: credential["key"] as? String ?? "k", cache: nil, options: options)
      customer = try server.customer("user_42")
      close = server.close
    }
    defer { close() }
    var result = Attempts()
    do {
      try await Hooks.$current.withValue(hooks) {
        if write {
          _ = try await customer.recordUsage(
            of: Feature<Metered>("ai_credits"), amount: 1, idempotencyKey: "conformance-write")
        } else {
          _ = try await customer.check("export_pdf")
        }
      }
    } catch let error as EntitlerError {
      if case .api(let apiError) = error, apiError.code == .invalidResponse {
      } else {
        result.error = error
      }
    }
    result.attempts = api.count
    result.waits = waits.get
    result.providerCalls = calls.get
    result.keys = api.requests.get.map { $0.header("Idempotency-Key") }
    return result
  }
}
