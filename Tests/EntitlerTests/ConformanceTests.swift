import Foundation
import Testing

@testable import Entitler

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

typealias JSONObject = [String: Any]

/// The shared conformance suite in `Tests/Conformance`, copied unchanged from the specification.
enum Conformance {
  static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Conformance")

  static let fileNames = [
    "cache-keys", "path-encoding", "idempotency-keys", "retry-timing", "token-refresh", "values",
    "errors", "snapshots",
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
    (files[file] ?? []).filter { applies($0) && contradiction(file, $0) == nil }
      .compactMap { $0["name"] as? String }
  }

  static func contradicted() -> [String: String] {
    var reasons: [String: String] = [:]
    for file in fileNames {
      for testCase in files[file] ?? [] where applies(testCase) {
        if let reason = contradiction(file, testCase) {
          reasons["\(file)/\(testCase["name"] as! String)"] = reason
        }
      }
    }
    return reasons
  }

  static func contradiction(_ file: String, _ testCase: JSONObject) -> String? {
    switch file {
    case "cache-keys":
      if testCase["principalKind"] as? String == "identity" {
        return
          "Spec v9 3.5 and 4.3: publishable keys start ent_pk_, so EntitlerClient refuses the case's ent_pub_ key as secret."
      }
      if testCase["asOf"] is String, testCase["principalKind"] as? String != "key" {
        return "Spec v9 4.3 and 6.6: no in-app client takes asOf."
      }
      if testCase["asOf"] is String,
        (testCase["built"] as? JSONObject)?["route"] as? String == "/pricing"
      {
        return "Spec v9 6.6: pricing is always computed now and never sends Entitler-As-Of."
      }
    case "idempotency-keys":
      if testCase["method"] as? String == "recordUsageBatch" {
        return
          "Spec v9 5.2 and 7.2: recordUsageBatch takes no key; each request's key derives from its events."
      }
    default: break
    }
    return nil
  }

  static func skipped(_ file: String) -> [String] {
    (files[file] ?? []).filter { !applies($0) }.compactMap { $0["name"] as? String }
  }

  static func applies(_ testCase: JSONObject) -> Bool {
    testCase["appliesWhere"] as? String != "strings can hold lone surrogates"
  }

  static func testCase(_ file: String, _ name: String) -> JSONObject {
    files[file]!.first { $0["name"] as? String == name }!
  }
}

private let checkBody =
  #"{"customer":"user_42","asOf":"2026-07-01T09:30:00.000Z","feature":"export_pdf","type":"boolean","entitled":true,"value":true,"sources":[],"upgrades":[],"environment":{"id":"e","name":"Development","kind":"test"},"track":{"id":"t","name":"All customers"},"release":2,"change":null,"testers":true,"experiment":null}"#
private let context =
  #""environment":{"id":"e","name":"Development","kind":"test"},"track":{"id":"t","name":"All customers"},"release":2,"change":null,"testers":true,"experiment":null"#

private func body(forPath path: String) -> String {
  if path.hasSuffix("/pricing/features") || path == "/pricing/features" {
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
  return checkBody
}

final class KeyLog: CacheStore {
  let asked = Box<[String]>([])
  func entry(forKey key: String) async throws -> CacheEntry? {
    asked.with { $0.append(key) }
    return nil
  }
  func setEntry(_ entry: CacheEntry, forKey key: String, timeToLive: TimeInterval) async throws {}
}

private func instant(_ value: Any?) -> Date? {
  (value as? String).flatMap(parseInstant)
}

private func expectInstant(
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

private func expectValue(
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

private func raw(_ expected: Any?) -> String? {
  if let text = expected as? String { return text }
  return (expected as? JSONObject)?["unknown"] as? String
}

private func expectArgumentError(
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

private func headers(_ object: Any?) -> [String: String] {
  (object as? [String: String]) ?? [:]
}

@Suite(.serialized) struct ConformanceTests {
  @Test func manifestMatchesEveryFile() throws {
    let manifest =
      try JSONSerialization.jsonObject(
        with: Data(contentsOf: Conformance.directory.appendingPathComponent("manifest.json")))
      as! JSONObject
    let entries = manifest["files"] as! [JSONObject]
    #expect(entries.count == Conformance.fileNames.count)
    for entry in entries {
      let path = entry["path"] as! String
      let data = try Data(contentsOf: Conformance.directory.appendingPathComponent(path))
      #expect(sha256Hex(data) == entry["sha256"] as? String, "\(path) differs from the manifest")
      let name = String(path.dropLast(5))
      #expect(
        Conformance.files[name]?.count == entry["cases"] as? Int,
        "\(path) has the wrong number of cases")
    }
    let skipped = Conformance.fileNames.flatMap(Conformance.skipped)
    #expect(skipped.count == 10, "Skipped only for lone surrogates: \(skipped)")
    let contradicted = Conformance.contradicted()
    #expect(contradicted.count == 20, "Cases spec v9 contradicts: \(contradicted)")
  }

  @Test func casesSpecNineContradictsAreListedWithAReason() {
    for (name, reason) in Conformance.contradicted().sorted(by: { $0.key < $1.key }) {
      #expect(!reason.isEmpty, "\(name)")
    }
  }

  @Test(arguments: Conformance.names("cache-keys"))
  func cacheKeys(_ name: String) async throws {
    let testCase = Conformance.testCase("cache-keys", name)
    let outcome = testCase["outcome"] as! JSONObject
    let built = testCase["built"] as! JSONObject
    let params = built["params"] as? [String: String] ?? [:]
    let route = built["route"] as! String
    let visitor = testCase["visitor"] as? String
    let store = KeyLog()
    let memory = MemoryCacheStore(capacity: 10)
    let api = FakeAPI(host: "*") { request in
      .json(body(forPath: request.path), headers: ["ETag": "\"conformance\""])
    }
    var options = api.options()
    options.baseURL = URL(string: built["baseUrl"] as! String)!
    let asOf = instant(testCase["asOfInput"] ?? testCase["asOf"])
    let customer: any Customer
    var server: EntitlerServer?
    switch testCase["principalKind"] as! String {
    case "key":
      server = try EntitlerServer(
        key: testCase["credential"] as! String, cache: store, options: options)
      customer = try server!.customer(params["id"] ?? "x")
    default:
      customer = try EntitlerClient(
        token: testCase["credential"] as! String, visitor: visitor, cache: memory, options: options
      ).me
    }
    try await api.run {
      switch route {
      case "/customers/{id}/entitlements/{feature}" where asOf != nil:
        _ = try await (customer as! ServerCustomer).check(params["feature"]!, asOf: asOf)
      case "/customers/{id}/entitlements/{feature}":
        _ = try await customer.check(params["feature"]!)
      case "/customers/{id}/entitlements": _ = try await customer.entitlements()
      case "/customers/{id}/plans": _ = try await customer.plans()
      case "/customers/{id}/pricing":
        _ = try await customer.pricing(visitor: server == nil ? nil : visitor)
      case "/pricing": _ = try await server!.pricing(visitor: visitor)
      default: _ = try await server!.features()
      }
    }
    if server == nil {
      #expect(await memory.entry(forKey: outcome["cacheKey"] as! String) != nil)
    } else {
      #expect(store.asked.get == [outcome["cacheKey"] as! String])
    }
    #expect(sha256(outcome["serialised"] as! String) == outcome["cacheKey"] as? String)
    #expect(api.last.url.absoluteString == testCase["url"] as? String)
    let expected = outcome["requestHeaders"] as! JSONObject
    for header in [
      "Authorization", "Entitler-Identity-Token", "Entitler-As-Of", "Entitler-Visitor",
    ] {
      #expect(api.last.header(header) == expected[header] as? String, "\(header)")
    }
  }

  @Test(arguments: Conformance.names("path-encoding"))
  func pathEncoding(_ name: String) async throws {
    let testCase = Conformance.testCase("path-encoding", name)
    let outcome = testCase["outcome"] as! JSONObject
    let request = testCase["request"] as? JSONObject ?? [:]
    let params = request["params"] as? [String: String] ?? [:]
    let api = FakeAPI(host: "*") { _ in .json(checkBody) }
    var options = api.options()
    if let base = testCase["baseUrl"] as? String { options.baseURL = URL(string: base)! }
    let server = try EntitlerServer(key: "ent_test_conformance_server_key", options: options)
    let call: () async throws -> Void
    switch testCase["kind"] as! String {
    case "query":
      let value = testCase["value"] as! String
      call = {
        var iterator = server.customers.list(query: value).pages.makeAsyncIterator()
        _ = try? await iterator.next()
      }
    default:
      let id = testCase["id"] as? String
      let parameter = testCase["parameter"] as? String ?? "customer"
      let route = request["route"] as! String
      call = {
        let customer = try server.customer(
          parameter == "customer" ? id ?? params["id"]! : params["id"]!)
        let value = id ?? ""
        do {
          switch route {
          case "/customers/{id}/entitlements/{feature}":
            _ = try await customer.check(parameter == "feature" ? value : params["feature"]!)
          case "/customers/{id}/subscription/add-ons/{plan}":
            _ = try await customer.cancel(addOn: value)
          case "/customers/{id}/usage/holds/{holdId}": _ = try await customer.hold(id: value)
          case "/customers/{id}/grants/{grantId}": _ = try await customer.revokeGrant(id: value)
          default: _ = try await customer.cancelUsage(id: value)
          }
        } catch is EntitlerError {}
      }
    }
    if outcome["kind"] as? String == "ArgumentError" {
      await expectArgumentError(outcome) { try await api.run(call) }
      #expect(api.count == 0)
    } else {
      try await api.run(call)
      #expect(
        api.last.url.absoluteString == outcome["url"] as? String, "\(api.last.url.absoluteString)")
    }
  }

  @Test(arguments: Conformance.names("idempotency-keys"))
  func idempotencyKeys(_ name: String) async throws {
    let testCase = Conformance.testCase("idempotency-keys", name)
    let outcome = testCase["outcome"] as! JSONObject
    let key = testCase["key"] as? String
    let credits = Feature<Metered>("ai_credits")
    let api = FakeAPI(host: "*") { request in
      if request.path == "/usage/events" {
        let events = (request.json?["events"] as? [Any])?.count ?? 0
        let results = (0..<events).map {
          #"{"index":\#($0),"outcome":"recorded","id":"u","late":false,"error":null}"#
        }
        return .json(
          #"{"results":[\#(results.joined(separator: ","))],"recorded":0,"duplicates":0,"errors":0}"#
        )
      }
      return .json(Fixture.usage(outcome: "held", holdID: #""h_1""#, amount: 10))
    }
    let server = try EntitlerServer(key: "ent_test_conformance_server_key", options: api.options())
    let customer = try server.customer("user_42")
    let call: () async throws -> Void
    switch testCase["method"] as! String {
    case "write":
      call = { _ = try await customer.recordUsage(of: credits, amount: 1, idempotencyKey: key!) }
    case "withHold":
      call = {
        _ = try await customer.withHold(of: credits, amount: 10, idempotencyKey: key!) { hold in
          try hold.use(15)
        }
      }
    default:
      let answer = Box<UsageBatchResult?>(nil)
      call = {
        answer.with {
          $0 = nil
        }
        let result = try await server.recordUsageBatch([
          UsageBatchEvent(customer: "user_42", feature: credits, amount: 1, idempotencyKey: key!)
        ])
        answer.with { $0 = result }
      }
      if outcome["valid"] as? Bool != true {
        try await api.run(call)
        let result = try #require(answer.get?.results.first)
        #expect(result.outcome == .error)
        #expect(result.error?.code == .invalidIdempotencyKey)
        #expect(result.error?.message == outcome["message"] as? String)
        #expect(api.count == 0)
        return
      }
    }
    guard outcome["valid"] as? Bool == true else {
      await expectArgumentError(outcome) { try await api.run(call) }
      #expect(api.count == 0)
      return
    }
    try await api.run(call)
    let requests = api.requests.get
    switch testCase["method"] as! String {
    case "write": #expect(requests.first?.header("Idempotency-Key") == key)
    case "withHold":
      #expect(requests.first?.header("Idempotency-Key") == key)
      #expect(requests.last?.header("Idempotency-Key") == outcome["excessKey"] as? String)
    case "batchEvent":
      let event = (requests.first?.json?["events"] as? [JSONObject])?.first
      #expect(event?["idempotencyKey"] as? String == key)
    default:
      let expected = outcome["requests"] as! [JSONObject]
      #expect(requests.count == expected.count)
      for (sent, wanted) in zip(requests, expected) {
        #expect((sent.json?["events"] as? [Any])?.count == wanted["events"] as? Int)
        if let wantedKey = wanted["idempotencyKey"] as? String {
          #expect(sent.header("Idempotency-Key") == wantedKey)
        } else {
          let sentKey = sent.header("Idempotency-Key") ?? ""
          #expect(UUID(uuidString: sentKey) != nil)
        }
      }
    }
  }

  @Test(arguments: Conformance.names("retry-timing"))
  func retryTiming(_ name: String) async throws {
    let testCase = Conformance.testCase("retry-timing", name)
    let outcome = testCase["outcome"] as! JSONObject
    switch testCase["kind"] as! String {
    case "retryAfter":
      var answers: [JSONObject] = [["status": 503]]
      if let value = testCase["retryAfter"] as? String {
        answers[0]["headers"] = ["Retry-After": value]
      }
      answers.append([
        "status": 200, "body": try JSONSerialization.jsonObject(with: Data(checkBody.utf8)),
      ])
      let run = try await Attempts.run(
        answers: answers, now: testCase["now"] as? String, maxRetries: 2,
        maxRetryDelay: testCase["maxRetryDelay"] as? Double ?? 10)
      switch outcome["action"] as! String {
      case "wait":
        let seconds = outcome["seconds"] as! Double
        #expect(run.waits.map(\.min) == [seconds])
        #expect(run.waits.map(\.max) == [seconds])
      case "backoff":
        #expect(run.waits.map(\.min) == [0])
        #expect(run.waits.map(\.max) == [0.5])
      default:
        #expect(run.attempts == 1)
        #expect(run.error?.apiError?.status == 503)
      }
    case "backoff":
      let retry = testCase["retry"] as! Int
      let run = try await Attempts.run(
        answers: Array(repeating: ["status": 503], count: retry + 2), now: nil,
        maxRetries: retry + 1,
        maxRetryDelay: 10)
      #expect(run.waits.last?.min == outcome["minSeconds"] as? Double)
      #expect(run.waits.last?.max == outcome["maxSeconds"] as? Double)
    case "limits":
      let maxRetries = testCase["maxRetries"] as! Int
      let plain = try await Attempts.run(
        answers: Array(repeating: ["status": 503], count: 10), now: nil, maxRetries: maxRetries,
        maxRetryDelay: 10)
      #expect(plain.attempts == outcome["maxAttemptsWithoutUnauthorised"] as? Int)
      let withProvider = try await Attempts.run(
        answers: [["status": 401]] + Array(repeating: ["status": 503], count: 10), now: nil,
        maxRetries: maxRetries, maxRetryDelay: 10, credential: ["kind": "customerTokenProvider"],
        provider: [makeJWT(["n": 1]), makeJWT(["n": 2])])
      #expect(withProvider.attempts == outcome["maxAttempts"] as? Int)
    default:
      let credential = testCase["credential"] as! JSONObject
      let request = testCase["request"] as! JSONObject
      let run = try await Attempts.run(
        answers: testCase["answers"] as! [JSONObject], now: testCase["now"] as? String,
        maxRetries: testCase["maxRetries"] as! Int,
        maxRetryDelay: testCase["maxRetryDelay"] as? Double ?? 10,
        credential: credential, write: request["method"] as? String == "POST")
      #expect(run.attempts == outcome["attempts"] as? Int)
      if let calls = outcome["providerCalls"] as? Int { #expect(run.providerCalls == calls) }
      let waits = outcome["waits"] as! [JSONObject]
      #expect(run.waits.map(\.min) == waits.map { $0["minSeconds"] as! Double })
      #expect(run.waits.map(\.max) == waits.map { $0["maxSeconds"] as! Double })
      let result = outcome["result"] as! JSONObject
      switch result["kind"] as? String {
      case "ApiError":
        #expect(run.error?.apiError?.status == result["status"] as? Int)
        #expect(run.error?.apiError?.code.rawValue == result["code"] as? String)
      case "TimeoutError":
        if case .timeout = run.error {
        } else {
          Issue.record("Expected a timeout, not \(String(describing: run.error))")
        }
      case "ConnectionError":
        if case .connection = run.error {} else { Issue.record("Expected a connection error") }
      case "TokenError":
        if case .token = run.error {} else { Issue.record("Expected a token error") }
      default:
        #expect(run.error == nil)
      }
      if outcome["sameIdempotencyKeyOnEveryAttempt"] as? Bool == true {
        #expect(Set(run.keys).count == 1)
      }
      if outcome["errorCarriesIdempotencyKey"] as? Bool == true {
        #expect(run.error?.apiError?.idempotencyKey == run.keys.first ?? nil)
      }
    }
  }

  @Test(arguments: Conformance.names("token-refresh"))
  func tokenRefresh(_ name: String) async throws {
    let testCase = Conformance.testCase("token-refresh", name)
    let outcome = testCase["outcome"] as! JSONObject
    let token = testCase["token"] as! String
    let calls = Box(0)
    let api = FakeAPI(host: "*") { _ in .json(checkBody) }
    api.clock.with { $0 = instant(testCase["receivedAt"])! }
    let client = try EntitlerClient(
      tokenProvider: {
        calls.with { $0 += 1 }
        return token
      }, cache: nil, options: api.options())
    if outcome["kind"] as? String == "TokenError" {
      do {
        _ = try await api.run { try await client.me.check("export_pdf") }
        Issue.record("Expected a token error")
      } catch EntitlerError.token {}
      #expect(api.count == 0)
      return
    }
    _ = try await api.run { try await client.me.check("export_pdf") }
    let expected = (outcome["requestHeaders"] as! JSONObject)["Authorization"] as? String
    #expect(api.last.header("Authorization") == expected)
    api.clock.with { $0 = instant(testCase["now"])! }
    _ = try await api.run { try await client.me.check("export_pdf") }
    #expect((calls.get == 2) == (outcome["asksProvider"] as! Bool))
  }

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
    let server = try EntitlerServer(key: "ent_test_conformance_server_key", options: api.options())
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
      #expect(check.type.rawValue == raw(outcome["type"]))
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
      if outcome.keys.contains("resetsAt") { expectInstant(check.resetsAt, outcome["resetsAt"]) }
      let environment = outcome["environment"] as! JSONObject
      #expect(check.environment.id == environment["id"] as? String)
      #expect(check.environment.name == environment["name"] as? String)
      #expect(check.environment.kind.rawValue == raw(environment["kind"]))
      let track = outcome["track"] as! JSONObject
      #expect(check.track.id == track["id"] as? String)
      #expect(check.track.name == track["name"] as? String)
      #expect(check.release == (outcome["release"] as? NSNumber)?.int64Value)
      #expect(check.change == outcome["change"] as? String)
      #expect(check.testers == outcome["testers"] as? Bool)
      if let experiment = outcome["experiment"] as? JSONObject {
        #expect(check.experiment?.id == experiment["id"] as? String)
        #expect(check.experiment?.arm.rawValue == raw(experiment["arm"]))
      } else {
        #expect(check.experiment == nil)
      }
      expectInstant(check.asOf, outcome["asOf"])
      #expect(check.stale == (outcome["stale"] as? Bool ?? false))
    }
  }

  @Test(arguments: Conformance.names("errors"))
  func errors(_ name: String) async throws {
    let testCase = Conformance.testCase("errors", name)
    let outcome = testCase["outcome"] as! JSONObject
    let call = testCase["call"] as! JSONObject
    let status = testCase["status"] as! Int
    let replyHeaders = headers(testCase["headers"])
    let replyBody = Data((testCase["body"] as? String ?? "").utf8)
    let api = FakeAPI(host: "*") { _ in
      Reply(status: status, headers: replyHeaders, body: replyBody)
    }
    if let receivedAt = instant(testCase["receivedAt"]) { api.clock.with { $0 = receivedAt } }
    let server = try EntitlerServer(
      key: "ent_test_conformance_server_key", options: api.options { $0.maxRetries = 0 })
    let customer = try server.customer(call["customer"] as! String)
    do {
      try await api.run {
        switch call["method"] as! String {
        case "check": _ = try await customer.check(call["feature"] as! String)
        case "recordUsage":
          _ = try await customer.recordUsage(
            of: Feature<Metered>(call["feature"] as! String),
            amount: (call["amount"] as! NSNumber).int64Value,
            idempotencyKey: call["idempotencyKey"] as! String)
        default:
          _ = try await customer.subscribe(
            to: call["plan"] as! String, period: call["period"] as? String,
            idempotencyKey: call["idempotencyKey"] as? String)
        }
      }
      Issue.record("Expected an APIError")
    } catch EntitlerError.api(let error) {
      #expect(error.status == outcome["status"] as? Int)
      #expect(error.code.rawValue == raw(outcome["code"]))
      #expect(error.message == outcome["message"] as? String)
      #expect(error.requestID == outcome["requestId"] as? String)
      #expect(error.retryAfter == (outcome["retryAfterSeconds"] as? NSNumber)?.doubleValue)
      #expect(error.idempotencyKey == outcome["idempotencyKey"] as? String)
      if let payment = outcome["payment"] as? JSONObject {
        #expect(error.payment?.status.rawValue == raw(payment["status"]))
        #expect(error.payment?.url == payment["url"] as? String)
      } else {
        #expect(error.payment == nil)
      }
      let gaps = outcome["listingGaps"] as? [JSONObject] ?? []
      #expect(error.listingGaps.count == gaps.count)
      for (gap, wanted) in zip(error.listingGaps, gaps) {
        #expect(gap.kind.rawValue == raw(wanted["kind"]))
        #expect(gap.plan == wanted["plan"] as? String)
        #expect(gap.key == wanted["key"] as? String)
        #expect(gap.period == wanted["period"] as? String)
        let channel = wanted["channel"] as? JSONObject
        #expect(gap.channel?.connectionID == channel?["connectionId"] as? String)
        #expect(gap.channel?.provider.rawValue == raw(channel?["provider"]))
      }
      let problems = outcome["listingProblems"] as? [JSONObject] ?? []
      #expect(error.listingProblems.count == problems.count)
      for (problem, wanted) in zip(error.listingProblems, problems) {
        #expect(problem.problem.rawValue == raw(wanted["problem"]))
        #expect(problem.plan == wanted["plan"] as? String)
        #expect(problem.period == wanted["period"] as? String)
        #expect(problem.ids == wanted["ids"] as? [String: String])
        let channel = wanted["channel"] as? JSONObject
        #expect(problem.channel.connectionID == channel?["connectionId"] as? String)
        #expect(problem.channel.provider.rawValue == raw(channel?["provider"]))
      }
    }
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
        #expect(item.type.rawValue == raw(wantedItem["type"]))
        #expect(item.entitled == wantedItem["entitled"] as? Bool)
        expectValue(item.value, wantedItem["value"])
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
    switch credential["kind"] as? String ?? (provider == nil ? nil : "customerTokenProvider") {
    case "customerToken":
      customer = try EntitlerClient(
        token: credential["token"] as! String, cache: nil, options: options
      ).me
    case "customerTokenProvider":
      customer = try EntitlerClient(
        tokenProvider: {
          let index = calls.with {
            $0 += 1
            return $0 - 1
          }
          return tokens[min(index, tokens.count - 1)]
        }, cache: nil, options: options
      ).me
    default:
      customer = try EntitlerServer(
        key: credential["key"] as? String ?? "k", cache: nil, options: options
      ).customer("user_42")
    }
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

func sha256Hex(_ data: Data) -> String {
  sha256(data)
}
