import EntitlerTesting
import Foundation
import Testing

@testable import Entitler

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized) struct ConformanceTests {
  @Test func manifestMatchesEveryFile() throws {
    let manifest =
      try JSONSerialization.jsonObject(
        with: Data(contentsOf: Conformance.directory.appendingPathComponent("manifest.json")))
      as! JSONObject
    let entries = manifest["files"] as! [JSONObject]
    #expect(entries.count == Conformance.fileNames.count)
    #expect(
      Set(entries.map { $0["path"] as! String }) == Set(Conformance.fileNames.map { $0 + ".json" }))
    for entry in entries {
      let path = entry["path"] as! String
      let data = try Data(contentsOf: Conformance.directory.appendingPathComponent(path))
      #expect(sha256(data) == entry["sha256"] as? String, "\(path) differs from the manifest")
      let name = String(path.dropLast(5))
      #expect(
        Conformance.files[name]?.count == entry["cases"] as? Int,
        "\(path) has the wrong number of cases")
    }
  }

  @Test func skipsOnlyCasesWhoseConditionSwiftRulesOut() {
    var conditions: [String: Int] = [:]
    for file in Conformance.fileNames {
      for testCase in Conformance.files[file] ?? [] {
        guard let condition = testCase["appliesWhere"] as? String else { continue }
        conditions[condition, default: 0] += 1
      }
    }
    let known = Conformance.conditionsSwiftMeets.union(Conformance.conditionsSwiftRulesOut)
    #expect(Set(conditions.keys).isSubset(of: known), "Unknown conditions: \(conditions.keys)")
    let skipped = Conformance.fileNames.flatMap(Conformance.skipped)
    #expect(skipped.count == 31, "\(skipped)")
    let run = Conformance.fileNames.flatMap(Conformance.names)
    #expect(run.count == 614)
  }

  @Test(arguments: Conformance.names("cache-keys"))
  func cacheKeys(_ name: String) async throws {
    let testCase = Conformance.testCase("cache-keys", name)
    let outcome = testCase["outcome"] as! JSONObject
    let built = testCase["built"] as! JSONObject
    let params = built["params"] as? [String: String] ?? [:]
    let route = built["route"] as! String
    let visitor = testCase["visitor"] as? String
    let clientVisitor = testCase["clientVisitor"] as? String
    let callVisitor = testCase["clientVisitor"] == nil ? nil : visitor
    let store = KeyLog()
    let memory = MemoryCacheStore(capacity: 10)
    let memoryAsked = Box<[String]>([])
    await memory.observe { key in memoryAsked.with { $0.append(key) } }
    let api = FakeAPI(host: "*") { request in
      .json(conformanceBody(forPath: request.path), headers: ["ETag": "\"conformance\""])
    }
    var options = api.options()
    options.baseURL = URL(string: built["baseUrl"] as! String)!
    let asOf = instant(testCase["asOfInput"] ?? testCase["asOf"])
    let credential = testCase["credential"] as? String ?? ""
    let read: () async throws -> Void
    let close: () -> Void
    var onServer = false
    switch testCase["principalKind"] as! String {
    case "key" where credential.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("ent_pk_"):
      let client = try EntitlerClient(
        key: credential, visitor: clientVisitor ?? visitor, cache: memory, options: options)
      close = client.close
      read = { _ = try await client.pricing(visitor: callVisitor) }
    case "key":
      onServer = true
      let server = try EntitlerServer(key: credential, cache: store, options: options)
      close = server.close
      read = {
        let customer = try server.customer(params["id"] ?? "x")
        switch route {
        case "/customers/{id}/entitlements/{feature}" where asOf != nil:
          _ = try await customer.check(params["feature"]!, asOf: asOf)
        case "/customers/{id}/entitlements/{feature}":
          _ = try await customer.check(params["feature"]!)
        case "/customers/{id}/entitlements": _ = try await customer.entitlements()
        case "/customers/{id}/plans": _ = try await customer.plans()
        case "/customers/{id}/pricing": _ = try await customer.pricing(visitor: visitor)
        case "/pricing": _ = try await server.pricing(visitor: visitor)
        default: _ = try await server.features()
        }
      }
    case let kind:
      let customer: SignedInCustomer
      if kind == "identity" {
        let client = try EntitlerClient(
          key: testCase["key"] as! String, identityToken: testCase["identityToken"] as! String,
          visitor: clientVisitor ?? visitor, cache: memory, options: options)
        customer = client.me
        close = client.close
      } else {
        let client = try EntitlerClient(
          token: credential, visitor: clientVisitor ?? visitor, cache: memory, options: options)
        customer = client.me
        close = client.close
      }
      read = {
        switch route {
        case "/customers/{id}/entitlements/{feature}":
          _ = try await customer.check(params["feature"]!)
        case "/customers/{id}/entitlements": _ = try await customer.entitlements()
        case "/customers/{id}/plans": _ = try await customer.plans()
        default: _ = try await customer.pricing(visitor: callVisitor)
        }
      }
    }
    defer { close() }
    try await api.run(read)
    let cacheKey = outcome["cacheKey"] as! String
    #expect((onServer ? store.asked.get : memoryAsked.get) == [cacheKey])
    #expect(sha256(outcome["serialised"] as! String) == cacheKey)
    #expect(api.count == 1)
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
    let options = request["options"] as? JSONObject ?? [:]
    let api = FakeAPI(host: "*") { _ in .json(conformanceCheckBody) }
    var clientOptions = api.options()
    if let base = testCase["baseUrl"] as? String { clientOptions.baseURL = URL(string: base)! }
    let server = try EntitlerServer(key: "ent_test_conformance_server_key", options: clientOptions)
    defer { server.close() }
    let call: () async throws -> Void
    switch testCase["kind"] as! String {
    case "query":
      let value = testCase["value"] as! String
      let parameter = testCase["parameter"] as! String
      let route = request["route"] as! String
      call = {
        switch parameter {
        case "q":
          var iterator = server.customers.list(query: value).pages.makeAsyncIterator()
          _ = try await iterator.next()
        case "cursor":
          var iterator = server.customers.list(cursor: value).pages.makeAsyncIterator()
          _ = try await iterator.next()
        default:
          let customer = try server.customer(params["id"]!)
          if route.hasSuffix("/pending") {
            _ = try await customer.undoPendingChange(product: value)
          } else {
            _ = try await customer.cancel(product: value)
          }
        }
      }
    case "arguments":
      let arguments = testCase["call"] as! JSONObject
      let given = arguments["options"] as! JSONObject
      call = {
        let customer = try server.customer(arguments["customer"] as! String)
        let addOn = given["addOn"] as? String
        let product = given["product"] as? String
        if arguments["method"] as? String == "undoPendingChange" {
          _ = try await customer.undoPendingChange(addOn: addOn, product: product)
        } else {
          _ = try await customer.cancel(addOn: addOn, product: product)
        }
      }
    default:
      let id = testCase["id"] as? String
      let parameter = testCase["parameter"] as? String ?? "customer"
      let route = request["route"] as! String
      call = {
        let customer = try server.customer(
          parameter == "customer" ? id ?? params["id"]! : params["id"]!)
        let value = id ?? params[parameter] ?? params["feature"] ?? ""
        switch route {
        case "/customers/{id}/entitlements/{feature}":
          _ = try await customer.check(parameter == "feature" ? value : params["feature"]!)
        case "/customers/{id}?erase=true": try await customer.erase()
        case "/customers/{id}/subscription/add-ons/{addOn}":
          _ = try await customer.cancel(addOn: value)
        case "/customers/{id}/subscription/add-ons/{addOn}/pending":
          _ = try await customer.undoPendingChange(addOn: value)
        case "/customers/{id}/add-ons/{addOn}":
          _ = try await customer.setAddOn(
            value, quantity: (options["quantity"] as! NSNumber).intValue)
        case "/customers/{id}/meters/{feature}/adjustments":
          _ = try await customer.adjustMeter(
            Feature<Metered>(value), by: (options["by"] as! NSNumber).int64Value,
            idempotencyKey: options["idempotencyKey"] as! String)
        case "/customers/{id}/usage/holds/{holdId}/settle":
          _ = try await customer.settleUsage(
            hold: value, amount: (options["amount"] as! NSNumber).int64Value)
        case "/customers/{id}/usage/holds/{holdId}":
          _ = try await customer.releaseUsage(hold: value)
        case "/customers/{id}/grants/{grantId}": _ = try await customer.revokeGrant(id: value)
        case "/customers/{id}/usage/{usageId}": _ = try await customer.cancelUsage(id: value)
        default: Issue.record("No method for \(route)")
        }
      }
    }
    if outcome["kind"] as? String == "ArgumentError" {
      await expectArgumentError(outcome) { try await api.run(call) }
      #expect(api.count == 0)
    } else {
      do {
        try await api.run(call)
      } catch is EntitlerError {}
      #expect(api.count == 1)
      #expect(
        api.last.url.absoluteString == outcome["url"] as? String, "\(api.last.url.absoluteString)")
      if let method = request["method"] as? String { #expect(api.last.method == method) }
    }
  }

  @Test(arguments: Conformance.names("idempotency-keys"))
  func idempotencyKeys(_ name: String) async throws {
    let testCase = Conformance.testCase("idempotency-keys", name)
    if testCase["method"] as? String == "recordUsageBatch" {
      try await batch(testCase)
      return
    }
    let outcome = testCase["outcome"] as! JSONObject
    let key = testCase["key"] as? String
    let credits = Feature<Metered>("ai_credits")
    let api = FakeAPI(host: "*") { request in
      let answer: Data
      if request.path.hasSuffix("/usage/holds") {
        answer = FakeAnswers.usageResult(
          feature: "ai_credits", outcome: .held, amount: 1, held: 1, holdID: "hold_1",
          expiresAt: Date(timeIntervalSince1970: 1_900_000_000))
      } else if request.path.hasSuffix("/settle") {
        answer = FakeAnswers.usageResult(feature: "ai_credits", outcome: .settled, amount: 1)
      } else if request.path.hasSuffix("/usage") {
        answer = FakeAnswers.usageResult(
          feature: "ai_credits", outcome: .recorded, amount: 1, mode: .observe)
      } else {
        answer = Data("{}".utf8)
      }
      return Reply(headers: ["Content-Type": "application/json"], body: answer)
    }
    let server = try EntitlerServer(key: "ent_test_conformance_server_key", options: api.options())
    defer { server.close() }
    let customer = try server.customer("user_42")
    let given = key ?? ""
    let call: () async throws -> Void
    switch testCase["method"] as! String {
    case "recordUsage":
      call = { _ = try await customer.recordUsage(of: credits, amount: 1, idempotencyKey: given) }
    case "holdUsage":
      call = { _ = try await customer.holdUsage(of: credits, amount: 1, idempotencyKey: given) }
    case "startHold":
      call = {
        let hold = try await customer.startHold(of: credits, amount: 1, idempotencyKey: given)
        try hold.use(2)
        _ = try await hold.finish()
      }
    case "withHold":
      call = {
        try await customer.withHold(of: credits, amount: 1, idempotencyKey: given) { hold in
          try hold.use(2)
        }
      }
    case "adjustMeter":
      call = {
        try await answerIgnored {
          _ = try await customer.adjustMeter(credits, by: 1, idempotencyKey: given)
        }
      }
    case "cancel":
      call = { try await answerIgnored { _ = try await customer.cancel(idempotencyKey: key) } }
    case "token":
      call = { try await answerIgnored { _ = try await customer.token() } }
    case "snapshot":
      call = { try await answerIgnored { _ = try await customer.snapshot() } }
    case "billingPortal":
      call = {
        try await answerIgnored {
          _ = try await customer.billingPortal(
            returnURL: URL(string: "https://app.example.com/billing")!)
        }
      }
    default:
      call = { try await answerIgnored { _ = try await customer.syncBilling() } }
    }
    guard outcome["valid"] as? Bool == true else {
      await expectArgumentError(outcome) { try await api.run(call) }
      #expect(api.count == 0)
      return
    }
    try await api.run(call)
    let first = api.requests.get.first?.header("Idempotency-Key")
    if let key {
      #expect(first == key)
    } else {
      #expect(isUUIDv4(first), "\(first ?? "none")")
      try await api.run(call)
      let second = api.last.header("Idempotency-Key")
      #expect(isUUIDv4(second))
      #expect(first != second)
    }
    if let excessKey = outcome["excessKey"] as? String {
      let excess = api.requests.get.last { $0.path.hasSuffix("/usage") }
      #expect(excess?.header("Idempotency-Key") == excessKey)
      #expect(excess?.json?["amount"] as? Int == 1)
    }
  }

  func batch(_ testCase: JSONObject) async throws {
    let outcome = testCase["outcome"] as! JSONObject
    var events = (testCase["events"] as? [JSONObject]) ?? []
    if let pattern = testCase["eventPattern"] as? JSONObject {
      let customers = pattern["customers"] as! Int
      events = (0..<(pattern["count"] as! Int)).map { index in
        [
          "customer": "\(pattern["customerPrefix"] as! String)\(index % customers)",
          "feature": pattern["feature"] as! String, "amount": index + 1,
          "idempotencyKey": "\(pattern["keyPrefix"] as! String)\(index)",
        ]
      }
    }
    for override in testCase["overrides"] as? [JSONObject] ?? [] {
      events[override["index"] as! Int] = override["event"] as! JSONObject
    }
    let batchEvents = events.map { event in
      UsageBatchEvent(
        customer: event["customer"] as! String,
        feature: Feature<Metered>(event["feature"] as! String),
        amount: (event["amount"] as! NSNumber).int64Value, occurredAt: instant(event["occurredAt"]),
        idempotencyKey: event["idempotencyKey"] as! String)
    }
    let api = FakeAPI(host: "*") { request in
      let count = (request.json?["events"] as? [Any])?.count ?? 0
      let results = (0..<count).map {
        #"{"index":\#($0),"outcome":"recorded","id":"u_\#($0)","late":false,"error":null}"#
      }
      return .json(
        #"{"results":[\#(results.joined(separator: ","))],"recorded":\#(count),"duplicates":0,"errors":0}"#
      )
    }
    let server = try EntitlerServer(key: "ent_test_conformance_server_key", options: api.options())
    defer { server.close() }
    let calls = testCase["calls"] as? Int ?? 1
    let expectedRequests = outcome["requests"] as! [JSONObject]
    let refused = outcome["refused"] as! [JSONObject]
    for round in 0..<calls {
      let result = try await api.run {
        if let register = testCase["register"] as? Bool {
          try await server.recordUsageBatch(batchEvents, register: register)
        } else {
          try await server.recordUsageBatch(batchEvents)
        }
      }
      #expect(result.results.count == events.count)
      for (index, answered) in result.results.enumerated() {
        #expect(answered.index == index)
        #expect(answered.idempotencyKey == events[index]["idempotencyKey"] as? String)
      }
      let refusedIndexes = Set(refused.map { $0["index"] as! Int })
      for wanted in refused {
        let answered = result.results[wanted["index"] as! Int]
        #expect(answered.outcome == .error)
        #expect(answered.error?.code.rawValue == wanted["code"] as? String)
        #expect(answered.error?.message == wanted["message"] as? String)
      }
      for answered in result.results where !refusedIndexes.contains(answered.index) {
        #expect(answered.outcome == .recorded)
      }
      let sent = api.requests.get.dropFirst(round * expectedRequests.count)
      #expect(sent.count == expectedRequests.count)
      for (request, wanted) in zip(sent, expectedRequests) {
        let serialised = wanted["serialised"] as! String
        let key = wanted["idempotencyKey"] as! String
        #expect(key == "batch:" + sha256(serialised))
        #expect(request.header("Idempotency-Key") == key)
        let parsed =
          try JSONSerialization.jsonObject(with: Data(serialised.utf8)) as! [Any]
        let rows = parsed[2] as! [[Any]]
        let body = try #require(request.json)
        let bodyEvents = body["events"] as! [JSONObject]
        #expect(bodyEvents.count == wanted["events"] as? Int)
        #expect(rows.count == bodyEvents.count)
        #expect((body["register"] as? Bool ?? false) == (parsed[1] as? Bool))
        for (row, event) in zip(rows, bodyEvents) {
          #expect(event["customer"] as? String == row[0] as? String)
          #expect(event["feature"] as? String == row[1] as? String)
          #expect((event["amount"] as? NSNumber)?.int64Value == (row[2] as? NSNumber)?.int64Value)
          #expect(event["occurredAt"] as? String == row[3] as? String)
          #expect(event["idempotencyKey"] as? String == row[4] as? String)
        }
      }
    }
    #expect(api.count == calls * expectedRequests.count)
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
        "status": 200,
        "body": try JSONSerialization.jsonObject(with: Data(conformanceCheckBody.utf8)),
      ])
      let run = try await Attempts.run(
        answers: answers, now: testCase["now"] as? String, maxRetries: 2,
        maxRetryDelay: testCase["maxRetryDelay"] as? Double ?? 10)
      switch outcome["action"] as! String {
      case "wait":
        let seconds = outcome["seconds"] as! Double
        #expect(run.waits.map(\.min) == [seconds])
        #expect(run.waits.map(\.max) == [seconds])
        #expect(run.error == nil)
      case "backoff":
        #expect(run.waits.map(\.min) == [0])
        #expect(run.waits.map(\.max) == [0.5])
        #expect(run.error == nil)
      default:
        #expect(run.attempts == 1)
        #expect(run.error?.apiError?.status == 503)
      }
    case "backoff":
      let retry = testCase["retry"] as! Int
      let run = try await Attempts.run(
        answers: Array(repeating: ["status": 503], count: retry + 2), now: nil,
        maxRetries: retry + 1, maxRetryDelay: 10)
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
        if case .connection = run.error {
        } else {
          Issue.record("Expected a connection error, not \(String(describing: run.error))")
        }
      case "TokenError":
        if case .token = run.error {
        } else {
          Issue.record("Expected a token error, not \(String(describing: run.error))")
        }
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
    let api = FakeAPI(host: "*") { _ in .json(conformanceCheckBody) }
    api.clock.with { $0 = instant(testCase["receivedAt"])! }
    let provider: TokenProvider = {
      calls.with { $0 += 1 }
      return token
    }
    let customer: SignedInCustomer
    let close: () -> Void
    if let key = testCase["key"] as? String {
      let client = try EntitlerClient(
        key: key, identityTokenProvider: provider, cache: nil, options: api.options())
      customer = client.me
      close = client.close
    } else {
      let client = try EntitlerClient(tokenProvider: provider, cache: nil, options: api.options())
      customer = client.me
      close = client.close
    }
    defer { close() }
    if outcome["kind"] as? String == "TokenError" {
      do {
        _ = try await api.run { try await customer.check("export_pdf") }
        Issue.record("Expected a token error")
      } catch EntitlerError.token {}
      #expect(api.count == 0)
      return
    }
    _ = try await api.run { try await customer.check("export_pdf") }
    let expected = outcome["requestHeaders"] as! JSONObject
    for header in ["Authorization", "Entitler-Identity-Token"] {
      #expect(api.last.header(header) == expected[header] as? String, "\(header)")
    }
    for _ in 0..<(testCase["close"] as? Int ?? 0) { close() }
    api.clock.with { $0 = instant(testCase["now"])! }
    if let later = outcome["later"] as? JSONObject {
      do {
        _ = try await api.run { try await customer.check("export_pdf") }
        Issue.record("Expected the closed client to fail")
      } catch let error as ClientClosedError {
        #expect(later["kind"] as? String == "ClosedError")
        #expect(error.message == later["message"] as? String)
      }
      #expect(api.count == 1)
    } else {
      _ = try await api.run { try await customer.check("export_pdf") }
    }
    #expect((calls.get == 2) == (outcome["asksProvider"] as! Bool))
  }

  @Test(arguments: Conformance.names("construction"))
  func construction(_ name: String) throws {
    let testCase = Conformance.testCase("construction", name)
    let outcome = testCase["outcome"] as! JSONObject
    let credentials = testCase["credentials"] as! JSONObject
    let provider: TokenProvider = {
      Issue.record("Construction asked the provider")
      return ""
    }
    func isProvider(_ name: String) -> Bool {
      (credentials[name] as? JSONObject)?["provider"] as? Bool == true
    }
    let key = credentials["key"] as? String
    let token = credentials["token"] as? String
    let identityToken = credentials["identityToken"] as? String
    do {
      let forms: [String]
      if testCase["client"] as? String == "EntitlerServer" {
        let server = try EntitlerServer(key: key!)
        defer { server.close() }
        forms = stringForms(server)
      } else if let token {
        let client = try EntitlerClient(token: token)
        defer { client.close() }
        forms = stringForms(client)
      } else if isProvider("token") {
        let client = try EntitlerClient(tokenProvider: provider)
        defer { client.close() }
        forms = stringForms(client)
      } else if let identityToken {
        let client = try EntitlerClient(key: key!, identityToken: identityToken)
        defer { client.close() }
        forms = stringForms(client)
      } else if isProvider("identityToken") {
        let client = try EntitlerClient(key: key!, identityTokenProvider: provider)
        defer { client.close() }
        forms = stringForms(client)
      } else {
        let client = try EntitlerClient(key: key!)
        defer { client.close() }
        forms = stringForms(client)
      }
      #expect(outcome["valid"] as? Bool == true, "Expected \(outcome)")
      for omitted in outcome["stringFormOmits"] as? [String] ?? [] {
        for form in forms { #expect(!form.contains(omitted)) }
      }
    } catch let error as ArgumentError {
      #expect(outcome["kind"] as? String == "ArgumentError")
      #expect(error.message == outcome["message"] as? String)
    }
  }

  func answerIgnored(_ body: () async throws -> Void) async throws {
    do {
      try await body()
    } catch is EntitlerError {}
  }

  func stringForms(_ value: Any) -> [String] {
    var dumped = ""
    dump(value, to: &dumped)
    return [String(describing: value), String(reflecting: value), dumped]
  }
}
