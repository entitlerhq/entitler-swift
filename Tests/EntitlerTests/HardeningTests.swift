import Foundation
import Testing

@testable import Entitler

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite struct RequestHardeningTests {
  @Test(arguments: [301, 302, 303, 307, 308])
  func redirectsAreNeverFollowed(status: Int) async throws {
    let elsewhere = FakeAPI { _ in .json(Fixture.check()) }
    let api = FakeAPI { _ in
      Reply(status: status, headers: ["Location": "https://\(elsewhere.host)/steal"])
    }
    let clients: [any Customer] = [
      try api.server().customer("u"),
      try EntitlerClient(token: "tok", options: api.options()).me,
      try EntitlerClient(key: "pk", identityToken: makeJWT(["sub": "s"]), options: api.options())
        .me,
    ]
    for customer in clients {
      for write in [false, true] {
        do {
          if write {
            _ = try await api.run {
              try await customer.recordUsage(of: Feature<Metered>("ai_credits"), amount: 1)
            }
          } else {
            _ = try await api.run { try await customer.check("sso") }
          }
          Issue.record("Expected an error")
        } catch EntitlerError.api(let error) {
          #expect(error.status == status)
          #expect(error.code == .httpError)
        }
      }
    }
    #expect(elsewhere.count == 0)
  }

  @Test func requestsBypassThePlatformCache() async throws {
    let api = FakeAPI { _ in .json(Fixture.check()) }
    _ = try await api.run { try await api.server().customer("u").check("sso") }
    #expect(api.last.cachePolicy == .reloadIgnoringLocalCacheData)
    #expect(defaultSession.configuration.urlCache == nil)
  }

  @Test func idsMadeOfDotsAreRefused() async throws {
    let api = FakeAPI()
    let server = try api.server()
    for id in [".", "..", "..."] {
      await #expect(throws: ArgumentError(message: "Pass an id that is not made only of dots.")) {
        try await server.customer(id).check("sso")
      }
      await #expect(throws: ArgumentError(message: "Pass an id that is not made only of dots.")) {
        try await server.customer("u").vendor.revokeGrant(id)
      }
    }
    _ = try? await api.run { try await server.customer(".a.").check("sso") }
    #expect(api.last.path == "/customers/.a./entitlements/sso")
  }

  @Test func idempotencyKeysMayNotStartOrEndWithASpace() async throws {
    let customer = try FakeAPI().server().customer("u")
    for key in [" lead", "trail "] {
      await #expect(
        throws: ArgumentError(
          message: "Pass idempotencyKey as 1 to 200 printable ASCII characters.")
      ) {
        try await customer.recordUsage(
          of: Feature<Metered>("ai_credits"), amount: 1, idempotencyKey: key)
      }
    }
  }

  @Test func userAgentNamesTheSDKAndSwift() async throws {
    let api = FakeAPI { _ in .json(Fixture.check()) }
    _ = try await api.run { try await api.server().customer("u").check("sso") }
    let agent = try #require(api.last.header("User-Agent"))
    #expect(
      agent.range(of: #"^entitler-swift/0\.1\.0 swift/6\.\d$"#, options: .regularExpression) != nil)
  }

  @Test func snapshotKeysSendNoCredentialVisitorOrAsOf() async throws {
    let api = FakeAPI { _ in .json(#"{"keys":[]}"#) }
    struct Offline: Error {}
    let client = try EntitlerClient(
      tokenProvider: { throw Offline() }, visitor: "abcdefghijklmnop",
      options: api.options { $0.asOf = Date(timeIntervalSince1970: 0) })
    _ = try await api.run { try await client.snapshotKeys() }
    for name in ["Authorization", "Entitler-Identity-Token", "Entitler-Visitor", "Entitler-As-Of"] {
      #expect(api.last.header(name) == nil)
    }
  }

  @Test func explicitNullMetadataIsSentAndAbsentOptionsOmitted() async throws {
    let api = FakeAPI { _ in
      .json(
        #"{"id":"c","externalId":"u","environmentId":"e","createdAt":"2026-10-09T01:47:13Z","created":false}"#
      )
    }
    _ = try await api.run {
      try await api.server().customer("u").register(metadata: ["old": nil, "new": "1"])
    }
    let metadata = try #require(api.last.json?["metadata"] as? [String: Any])
    #expect(metadata["old"] is NSNull)
    #expect(metadata["new"] as? String == "1")
    #expect(api.last.json?.keys.sorted() == ["metadata"])
  }

  @Test func connectionErrorsKeepNoRequest() async throws {
    let api = FakeAPI { _ in .failure(.cannotConnectToHost) }
    do {
      _ = try await api.run { try await api.server { $0.maxRetries = 0 }.customer("u").billing() }
    } catch EntitlerError.connection(let error) {
      let underlying = try #require(error.underlyingError as? URLError)
      #expect(underlying.code == .cannotConnectToHost)
      #expect(underlying.userInfo.isEmpty)
    }
  }
}

@Suite struct CacheHardeningTests {
  @Test func keysFollowTheVersionOneFormat() throws {
    let server = try EntitlerServer(
      key: "sk_test", options: EntitlerOptions(baseURL: URL(string: "https://api.entitler.dev")!))
    var request = try Request("GET", ["customers", "u", "entitlements", "sso"])
    request.visitor = "abcdefghijklmnop"
    let principal = sha256("sk_test")
    let expected = sha256(
      #"["entitler-cache-v1","GET","https://api.entitler.dev/customers/u/entitlements/sso","key",""#
        + principal + #"",null,"abcdefghijklmnop"]"#)
    #expect(server.core.cacheKey(request, token: "sk_test") == expected)
    let identity = try EntitlerClient(key: "pk", identityToken: "id.token.x")
    let key = identity.core.cacheKey(try Request("GET", ["customers", "me"]), token: "id.token.x")
    #expect(key.count == 64)
    #expect(jsonString("a\"b\\c\n\u{01}é/") == #""a\"b\\c\n\u0001é/""#)
  }

  @Test func ageCountsTowardsFreshness() async throws {
    let api = FakeAPI { _ in
      .json(
        Fixture.check(), headers: ["Cache-Control": "max-age=30", "Age": "25", "ETag": "\"e\""])
    }
    let customer = try api.server().customer("u")
    try await api.run {
      _ = try await customer.check("sso")
      api.advance(4)
      _ = try await customer.check("sso")
      #expect(api.count == 1)
      api.advance(2)
      _ = try await customer.check("sso")
      #expect(api.count == 2)
    }
  }

  @Test func noCacheAlwaysRevalidates() async throws {
    let api = FakeAPI { _ in
      .json(
        Fixture.check(),
        headers: ["Cache-Control": "private, no-cache, max-age=60", "ETag": "\"e\""])
    }
    let customer = try api.server().customer("u")
    try await api.run {
      _ = try await customer.check("sso")
      _ = try await customer.check("sso")
    }
    #expect(api.count == 2)
    #expect(api.last.header("If-None-Match") == "\"e\"")
  }

  @Test func notModifiedKeepsHeadersItLeavesOut() async throws {
    let store = RecordingStore()
    let api = FakeAPI(replies: [
      .json(Fixture.check(), headers: ["ETag": "\"e1\"", "Cache-Control": "private, no-cache"]),
      Reply(status: 304, headers: ["Cache-Control": "max-age=60"]),
      .json(Fixture.check()),
    ])
    let customer = try api.server { $0.cache = store }.customer("u")
    try await api.run {
      _ = try await customer.check("sso")
      _ = try await customer.check("sso")
      _ = try await customer.check("sso")
    }
    #expect(api.count == 2)
    let key = try #require(store.keys.first)
    let entry = try #require(await store.inner.entry(forKey: key))
    #expect(entry.etag == "\"e1\"")
    #expect(entry.cacheControl == "max-age=60")
  }

  @Test func aReadOverlappingAWriteIsNeverKeptAsFresh() async throws {
    let first = Box(true)
    let api = FakeAPI { request in
      guard request.method == "GET" else { return .json(Fixture.usage()) }
      let isFirst = first.with { value in
        defer { value = false }
        return value
      }
      var reply = Reply.json(
        Fixture.check(), headers: ["Cache-Control": "max-age=300", "ETag": "\"e\""])
      reply.delay = isFirst ? 0.3 : 0
      return reply
    }
    let customer = try api.server().customer("u")
    let hooks = api.hooks
    let read = Task {
      try await Hooks.$current.withValue(hooks) { try await customer.check("sso") }
    }
    while api.count == 0 { try await Task.sleep(nanoseconds: 5_000_000) }
    _ = try await api.run {
      try await customer.vendor.setMeter(Feature<Metered>("ai_credits"), to: 1)
    }
    _ = try await read.value
    _ = try await api.run { try await customer.check("sso") }
    #expect(api.count == 3)
    #expect(api.last.header("If-None-Match") == "\"e\"")
  }

  @Test func tokenAndCheckoutWritesKeepFreshAnswers() async throws {
    let api = FakeAPI { request in
      switch request.method {
      case "GET":
        .json(Fixture.check(), headers: ["Cache-Control": "max-age=300", "ETag": "\"e\""])
      default:
        request.path.hasSuffix("tokens")
          ? .json(#"{"token":"t","customer":"u","scopes":[],"expiresAt":"2027-01-01T00:00:00Z"}"#)
          : .json(#"{"token":"a.b.c","expiresAt":"2027-01-01T00:00:00Z","keyId":"k"}"#)
      }
    }
    let customer = try api.server().customer("u")
    try await api.run {
      _ = try await customer.check("sso")
      api.advance(1)
      _ = try await customer.token()
      _ = try await customer.snapshot()
      _ = try await customer.check("sso")
    }
    #expect(api.count == 3)
  }

  @Test func failingStoresCountAsMisses() async throws {
    struct Broken: Error {}
    final class BrokenStore: CacheStore {
      func entry(forKey key: String) async throws -> CacheEntry? { throw Broken() }
      func setEntry(_ entry: CacheEntry, forKey key: String, timeToLive: TimeInterval) async throws
      {
        throw Broken()
      }
    }
    let errors = Box(0)
    let api = FakeAPI { _ in .json(Fixture.check(), headers: ["ETag": "\"e\""]) }
    let customer = try api.server {
      $0.cache = BrokenStore()
      $0.onError = { error in if error is Broken { errors.with { $0 += 1 } } }
    }.customer("u")
    let check = try await api.run { try await customer.check("sso") }
    #expect(check.entitled)
    #expect(errors.get == 2)
  }

  @Test func storesReceiveATimeToLive() async throws {
    let lives = Box<[TimeInterval]>([])
    final class TimingStore: CacheStore {
      let lives: Box<[TimeInterval]>
      init(_ lives: Box<[TimeInterval]>) { self.lives = lives }
      func entry(forKey key: String) async throws -> CacheEntry? { nil }
      func setEntry(_ entry: CacheEntry, forKey key: String, timeToLive: TimeInterval) async throws
      {
        lives.with { $0.append(timeToLive) }
      }
    }
    let api = FakeAPI { _ in .json(Fixture.check(), headers: ["Cache-Control": "max-age=60"]) }
    _ = try await api.run {
      try await api.server {
        $0.cache = TimingStore(lives)
        $0.staleFor = 100
      }.customer("u").check("sso")
    }
    #expect(lives.get == [160])
  }

  @Test func anOutageAnswersFromTheCacheForThirtySecondsThenTestsTheAPI() async throws {
    let errors = Box(0)
    let api = FakeAPI(replies: [
      .json(Fixture.check(), headers: ["ETag": "\"e\""]), .failure(.notConnectedToInternet),
    ])
    let customer = try api.server {
      $0.maxRetries = 0
      $0.onError = { _ in errors.with { $0 += 1 } }
    }.customer("u")
    try await api.run {
      _ = try await customer.check("sso")
      #expect(try await customer.check("sso").stale)
      #expect(api.count == 2)
      api.advance(10)
      #expect(try await customer.check("sso").stale)
      #expect(api.count == 2)
      api.advance(21)
      api.answer { _ in .json(Fixture.check(), headers: ["ETag": "\"e\""]) }
      #expect(try await !customer.check("sso").stale)
      #expect(api.count == 3)
    }
    #expect(errors.get == 1)
  }

  @Test func undecodableAnswersFallBackToStale() async throws {
    let api = FakeAPI(replies: [
      .json(Fixture.check(), headers: ["ETag": "\"e\""]), .json("<html>captive portal</html>"),
    ])
    let customer = try api.server().customer("u")
    let stale = try await api.run { () -> Check in
      _ = try await customer.check("sso")
      return try await customer.check("sso")
    }
    #expect(stale.stale)
    #expect(api.count == 2)
  }

  @Test func featureListsCarryStale() async throws {
    let list =
      #"{"environment":{"id":"e","name":"d","kind":"test"},"track":{"id":"t","name":"All customers"},"release":1,"change":null,"features":[]}"#
    let api = FakeAPI(replies: [
      .json(list, headers: ["ETag": "\"e\""]), .error(503, code: "unavailable"),
    ])
    let server = try api.server { $0.maxRetries = 0 }
    let stale = try await api.run { () -> FeatureList in
      _ = try await server.features()
      return try await server.features()
    }
    #expect(stale.stale)
  }

  @Test func isEntitledAnswersDefaultForABlankKeyAndReportsIt() async throws {
    let reported = Box<[any Error]>([])
    let api = FakeAPI()
    let customer = try api.server { $0.onError = { error in reported.with { $0.append(error) } } }
      .customer("u")
    #expect(await customer.isEntitled(to: " ", default: true))
    #expect((reported.get.first as? ArgumentError)?.message == "Name the feature by its key.")
    #expect(api.count == 0)
  }
}

@Suite struct TokenHardeningTests {
  @Test func aShortLivedTokenIsAskedForAtMostOncePerRequest() async throws {
    let calls = Box(0)
    let api = FakeAPI { _ in .json(Fixture.check()) }
    let client = try EntitlerClient(
      tokenProvider: {
        calls.with { $0 += 1 }
        return makeJWT(["sub": "u", "iat": 1_800_000_000, "exp": 1_800_000_060])
      }, options: api.options())
    try await api.run {
      _ = try await client.me.check("sso")
      #expect(calls.get == 1)
      api.advance(31)
      _ = try await client.me.check("export_pdf")
      #expect(calls.get == 2)
    }
  }

  @Test func oneWaiterCancellingLeavesTheSharedRefreshRunning() async throws {
    let calls = Box(0)
    let api = FakeAPI { _ in .json(Fixture.check()) }
    let client = try EntitlerClient(
      tokenProvider: {
        calls.with { $0 += 1 }
        try await Task.sleep(nanoseconds: 200_000_000)
        return makeJWT(["sub": "u"])
      }, options: api.options { $0.cache = nil })
    let hooks = api.hooks
    let cancelled = Task {
      try await Hooks.$current.withValue(hooks) { try await client.me.check("sso") }
    }
    let waiting = Task {
      try await Hooks.$current.withValue(hooks) { try await client.me.check("sso") }
    }
    try await Task.sleep(nanoseconds: 50_000_000)
    cancelled.cancel()
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(try await waiting.value.entitled)
    #expect(calls.get == 1)
  }

  @Test func aHangingProviderTimesOutAndIsAskedAgainNextTime() async throws {
    let calls = Box(0)
    let api = FakeAPI { _ in .json(Fixture.check()) }
    let client = try EntitlerClient(
      tokenProvider: {
        let n = calls.with {
          $0 += 1
          return $0
        }
        if n == 1 { try await Task.sleep(nanoseconds: 10_000_000_000) }
        return makeJWT(["sub": "u"])
      }, options: api.options { $0.timeout = 0.05 })
    do {
      _ = try await api.run { try await client.me.check("sso") }
      Issue.record("Expected a token error")
    } catch EntitlerError.token(let error) {
      #expect(error.message.contains("did not answer"))
    }
    _ = try await api.run { try await client.me.check("sso") }
    #expect(calls.get == 2)
  }

  @Test func transientFailureThenUnauthorisedThenSuccess() async throws {
    let calls = Box(0)
    let api = FakeAPI(replies: [
      .error(503, code: "unavailable"), .error(401, code: "unauthorised"), .json(Fixture.usage()),
    ])
    let client = try EntitlerClient(
      tokenProvider: {
        calls.with {
          $0 += 1
          return makeJWT(["sub": "u", "n": $0])
        }
      },
      options: api.options { $0.maxRetries = 1 })
    _ = try await api.run {
      try await client.me.recordUsage(of: Feature<Metered>("ai_credits"), amount: 1)
    }
    #expect(api.count == 3)
    #expect(calls.get == 2)
    #expect(Set(api.requests.get.map { $0.header("Idempotency-Key") }).count == 1)
  }

  @Test func anUnauthorisedOlderTokenRetriesWithTheCurrentOne() async throws {
    let calls = Box(0)
    let api = FakeAPI { request in
      request.header("Authorization")?.contains("first") == true && request.path.hasSuffix("sso")
        ? .error(401, code: "unauthorised") : .json(Fixture.check())
    }
    let source = TokenSource(
      provider: {
        calls.with {
          $0 += 1
          return $0 == 1 ? makeJWT(["v": "first"]) : makeJWT(["v": "second"])
        }
      }, blankMessage: "")
    let first = try await source.token(now: Date(), timeout: 1)
    let second = try await source.refresh(replacing: first, now: Date(), timeout: 1)
    #expect(try await source.refresh(replacing: first, now: Date(), timeout: 1) == second)
    #expect(calls.get == 2)
    _ = api
  }
}

@Suite struct BatchHardeningTests {
  @Test func anEmptyBatchSendsNothing() async throws {
    let api = FakeAPI()
    let result = try await api.run { try await api.server().recordUsageBatch([]) }
    #expect(result.results.isEmpty)
    #expect(api.count == 0)
  }

  @Test func eachRequestSendsItsOwnKeyAndFailedRequestsAnswerErrors() async throws {
    let api = FakeAPI { request in
      if request.header("Idempotency-Key") == "batch:1" { return .failure(.notConnectedToInternet) }
      let events = (request.json?["events"] as? [[String: Any]]) ?? []
      let results = events.indices.map {
        #"{"index":\#($0),"outcome":"recorded","id":"u","late":false,"error":null}"#
      }
      return .json(
        #"{"results":[\#(results.joined(separator: ","))],"recorded":0,"duplicates":0,"errors":0}"#)
    }
    let events = (0..<1_200).map {
      UsageBatchEvent(
        customer: "c", feature: Feature<Metered>("ai_credits"), idempotencyKey: "e\($0)")
    }
    let result = try await api.run {
      try await api.server { $0.maxRetries = 0 }.recordUsageBatch(events, idempotencyKey: "batch")
    }
    #expect(
      Set(api.requests.get.compactMap { $0.header("Idempotency-Key") }) == [
        "batch:0", "batch:1", "batch:2",
      ])
    #expect(result.results.count == 1_200)
    #expect(result.results[500].outcome == .error)
    #expect(result.results[500].error?.code == .connectionFailed)
    #expect(result.results[500].idempotencyKey == "e500")
    #expect(result.recorded == 700)
    #expect(result.errors == 500)
  }

  @Test func timedOutAndRefusedRequestsCarryTheirCodes() async throws {
    let api = FakeAPI { _ in .hanging }
    let one = [UsageBatchEvent(customer: "c", feature: Feature<Metered>("ai_credits"))]
    let timedOut = try await api.run {
      try await api.server {
        $0.maxRetries = 0
        $0.timeout = 0.05
      }.recordUsageBatch(one)
    }
    #expect(timedOut.results.first?.error?.code == .timedOut)
    api.answer { _ in .error(403, code: "scope_required") }
    let refused = try await api.run { try await api.server().recordUsageBatch(one) }
    #expect(refused.results.first?.error?.code == .scopeRequired)
  }
}
