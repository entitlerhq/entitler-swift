import Foundation
import Testing

@testable import Entitler

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite struct RetryTests {
  @Test(arguments: [408, 429, 500, 502, 503, 504])
  func retriesTransientStatuses(status: Int) async throws {
    let api = FakeAPI(replies: [.error(status, code: "unavailable"), .json(Fixture.check())])
    let check = try await api.run { try await api.server().customer("u").check("sso") }
    #expect(check.entitled)
    #expect(api.count == 2)
    #expect(api.sleeps.get == [0.5])
  }

  @Test(arguments: [400, 401, 403, 404, 409, 422])
  func neverRetriesOtherStatuses(status: Int) async throws {
    let api = FakeAPI(replies: [.error(status, code: "x"), .json(Fixture.check())])
    await #expect(throws: EntitlerError.self) {
      try await api.run { try await api.server().customer("u").check("sso") }
    }
    #expect(api.count == 1)
  }

  @Test func retriesConnectionFailuresWithBackoffThenFails() async throws {
    let api = FakeAPI { _ in .failure(.networkConnectionLost) }
    do {
      _ = try await api.run { try await api.server { $0.maxRetries = 3 }.customer("u").vendor.cancelUsage("u_1") }
      Issue.record("Expected an error")
    } catch EntitlerError.connection(let error) {
      #expect(error.idempotencyKey != nil)
      #expect((error.underlyingError as? URLError)?.code == .networkConnectionLost)
    }
    #expect(api.count == 4)
    #expect(api.sleeps.get == [0.5, 1, 2])
    let keys = Set(api.requests.get.map { $0.header("Idempotency-Key") })
    #expect(keys.count == 1)
  }

  @Test func backoffIsCappedAtEightSeconds() async throws {
    let api = FakeAPI { _ in .error(503, code: "unavailable") }
    await #expect(throws: EntitlerError.self) {
      try await api.run { try await api.server { $0.maxRetries = 6 }.customer("u").billing() }
    }
    #expect(api.sleeps.get == [0.5, 1, 2, 4, 8, 8])
  }

  @Test func backoffIsRandomWithinBounds() async throws {
    let api = FakeAPI(replies: [.error(500, code: "internal"), .json(Fixture.check())])
    let picked = Box<[ClosedRange<Double>]>([])
    var hooks = api.hooks
    hooks.random = { range in
      picked.with { $0.append(range) }
      return range.lowerBound
    }
    _ = try await Hooks.$current.withValue(hooks) {
      try await api.server().customer("u").check("sso")
    }
    #expect(picked.get == [0...0.5])
  }

  @Test func retryAfterSecondsAndDatesAreHonoured() async throws {
    let api = FakeAPI(replies: [
      .error(429, code: "rate_limited", headers: ["Retry-After": "3"]),
      .error(503, code: "unavailable", headers: ["Retry-After": "Thu, 15 Jan 2027 08:00:05 GMT"]),
      .json(Fixture.check()),
    ])
    api.clock.with { $0 = try! #require(parseInstant("2027-01-15T07:59:58Z")) }
    _ = try await api.run { try await api.server().customer("u").check("sso") }
    #expect(api.sleeps.get == [3, 4])
  }

  @Test func retryAfterBeyondTheMaximumFailsAtOnce() async throws {
    let api = FakeAPI(replies: [.error(503, code: "unavailable", headers: ["Retry-After": "60"])])
    do {
      _ = try await api.run { try await api.server().customer("u").billing() }
      Issue.record("Expected an error")
    } catch EntitlerError.api(let error) {
      #expect(error.retryAfter == 60)
    }
    #expect(api.count == 1)
    #expect(api.sleeps.get.isEmpty)
  }

  @Test func retryAfterParsing() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(retryAfter("12", now: now) == 12)
    #expect(retryAfter("soon", now: now) == nil)
    #expect(retryAfter("Thu, 01 Jan 1970 00:00:10 GMT", now: now) == 10)
  }

  @Test func timeoutsAreRetriedThenThrown() async throws {
    let api = FakeAPI { _ in .hanging }
    do {
      _ = try await api.run {
        try await api.server { $0.maxRetries = 1 }.customer("u").recordUsage(of: "ai_credits", amount: 1, timeout: 0.05)
      }
      Issue.record("Expected an error")
    } catch EntitlerError.timeout(let error) {
      #expect(error.timeout == 0.05)
      #expect(error.idempotencyKey != nil)
    }
    #expect(api.count == 2)
  }

  @Test func idleTimeoutsFromURLSessionAreTimeouts() async throws {
    let api = FakeAPI { _ in .failure(.timedOut) }
    await #expect(throws: EntitlerError.self) {
      try await api.run { try await api.server { $0.maxRetries = 0 }.customer("u").billing() }
    }
  }

  @Test func cancellationEndsARetryWait() async throws {
    let api = FakeAPI { _ in .error(503, code: "unavailable") }
    var hooks = api.hooks
    hooks.sleep = { _ in try await Task.sleep(nanoseconds: 10_000_000_000) }
    let task = Task {
      try await Hooks.$current.withValue(hooks) { try await api.server().customer("u").billing() }
    }
    try await Task.sleep(nanoseconds: 100_000_000)
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  @Test func cancelledRequestsSurfaceCancellationError() async throws {
    let api = FakeAPI { _ in .failure(.cancelled) }
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await api.run { try await api.server().customer("u").billing() }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  @Test func callersIdempotencyKeyIsSentAndValidated() async throws {
    let api = FakeAPI { _ in .json(Fixture.usage()) }
    let customer = try api.server().customer("u")
    _ = try await api.run { try await customer.recordUsage(of: "ai_credits", amount: 1, idempotencyKey: "job-42") }
    #expect(api.last.header("Idempotency-Key") == "job-42")
    for bad in ["", String(repeating: "a", count: 201), "tab\there", "é"] {
      await #expect(throws: ArgumentError(message: "Pass idempotencyKey as 1 to 200 printable ASCII characters.")) {
        try await customer.recordUsage(of: "ai_credits", amount: 1, idempotencyKey: bad)
      }
    }
    #expect(api.count == 1)
  }
}

@Suite struct CacheTests {
  @Test func freshAnswersNeedNoRequest() async throws {
    let api = FakeAPI { _ in .json(Fixture.check(), headers: ["Cache-Control": "private, max-age=30", "ETag": "\"e1\""]) }
    let customer = try api.server().customer("u")
    try await api.run {
      _ = try await customer.check("sso")
      _ = try await customer.check("sso")
      #expect(api.count == 1)
      api.advance(31)
      _ = try await customer.check("sso")
      #expect(api.count == 2)
      #expect(api.last.header("If-None-Match") == "\"e1\"")
    }
  }

  @Test func writesForceRevalidation() async throws {
    let api = FakeAPI { request in
      request.method == "GET"
        ? .json(Fixture.check(), headers: ["Cache-Control": "max-age=300", "ETag": "\"e1\""])
        : .json(Fixture.usage())
    }
    let server = try api.server()
    try await api.run {
      _ = try await server.customer("u").check("sso")
      _ = try await server.customer("other").vendor.cancelUsage("x")
      _ = try await server.customer("u").check("sso")
      #expect(api.count == 2)
      api.advance(1)
      _ = try await server.customer("u").recordUsage(of: "ai_credits", amount: 1)
      _ = try await server.customer("u").check("sso")
      #expect(api.count == 4)
      #expect(api.last.header("If-None-Match") == "\"e1\"")
    }
  }

  @Test func notModifiedAnswersTheKeptBody() async throws {
    let api = FakeAPI(replies: [
      .json(Fixture.entitlements, headers: ["Cache-Control": "private, no-cache", "ETag": "\"e1\""]),
      Reply(status: 304, headers: ["ETag": "\"e1\"", "Cache-Control": "max-age=60"]),
    ])
    let customer = try api.server().customer("u")
    try await api.run {
      let first = try await customer.entitlements()
      let second = try await customer.entitlements()
      #expect(first == second)
      #expect(api.requests.get[1].header("If-None-Match") == "\"e1\"")
      _ = try await customer.entitlements()
      #expect(api.count == 2)
    }
  }

  @Test func notModifiedWithoutKeptAnswerIsAnHTTPError() async throws {
    let api = FakeAPI(replies: [Reply(status: 304)])
    do {
      _ = try await api.run { try await api.server { $0.cache = nil }.customer("u").check("sso") }
      Issue.record("Expected an error")
    } catch EntitlerError.api(let error) {
      #expect(error.status == 304)
      #expect(error.code == .httpError)
      #expect(error.message == "Entitler request failed with HTTP 304.")
    }
  }

  @Test func noStoreIsNeverKept() async throws {
    let api = FakeAPI { _ in .json(Fixture.check(), headers: ["Cache-Control": "no-store, max-age=60", "ETag": "\"e\""]) }
    let customer = try api.server().customer("u")
    try await api.run {
      _ = try await customer.check("sso")
      _ = try await customer.check("sso")
    }
    #expect(api.count == 2)
    #expect(api.last.header("If-None-Match") == nil)
  }

  @Test func cachingCanBeTurnedOff() async throws {
    let api = FakeAPI { _ in .json(Fixture.check(), headers: ["Cache-Control": "max-age=60"]) }
    let customer = try api.server { $0.cache = nil }.customer("u")
    try await api.run {
      _ = try await customer.check("sso")
      _ = try await customer.check("sso")
    }
    #expect(api.count == 2)
  }

  @Test func keysSeparatePrincipalAsOfAndVisitor() async throws {
    let store = RecordingStore()
    let pricing = #"{\#(Fixture.context),"customer":"u","defaultPlan":null,"products":[],"plans":[]}"#
    let api = FakeAPI { request in
      .json(request.path.hasSuffix("pricing") ? pricing : Fixture.check(), headers: ["Cache-Control": "max-age=60"])
    }
    try await api.run {
      _ = try await EntitlerServer(key: "a", options: api.options { $0.cache = store }).customer("u").check("sso")
      _ = try await EntitlerServer(key: "b", options: api.options { $0.cache = store }).customer("u").check("sso")
      _ = try await EntitlerServer(key: "a", options: api.options { $0.cache = store; $0.asOf = Date(timeIntervalSince1970: 0) })
        .customer("u").check("sso")
      let server = try EntitlerServer(key: "a", options: api.options { $0.cache = store })
      _ = try await server.customer("u").pricing(visitor: "aaaaaaaaaaaaaaaa")
      _ = try await server.customer("u").pricing(visitor: "bbbbbbbbbbbbbbbb")
      _ = try await server.customer("u").check("sso")
    }
    #expect(api.count == 5)
    #expect(store.keys.count == 5)
    #expect(store.keys.allSatisfy { $0.count == 64 && $0.allSatisfy(\.isHexDigit) })
  }

  @Test func refreshedTokensKeepTheirCustomersAnswers() async throws {
    let tokens = Box(0)
    let api = FakeAPI { _ in .json(Fixture.check(), headers: ["Cache-Control": "max-age=300"]) }
    let client = try EntitlerClient(
      tokenProvider: {
        let n = tokens.with { $0 += 1; return $0 }
        return makeJWT(["iss": "entitler", "eid": "env", "sub": "user_1", "exp": 1_800_000_100 + n * 50, "n": n])
      }, options: api.options())
    try await api.run {
      _ = try await client.me.check("sso")
      api.advance(95)
      _ = try await client.me.check("sso")
    }
    #expect(tokens.get == 2)
    #expect(api.count == 1)
  }

  @Test func memoryStoreEvictsTheLeastRecentlyUsed() async {
    let store = MemoryCacheStore(capacity: 2)
    let entry = CacheEntry(body: Data(), etag: nil, maxAge: nil, receivedAt: Date())
    await store.setEntry(entry, forKey: "a")
    await store.setEntry(entry, forKey: "b")
    _ = await store.entry(forKey: "a")
    await store.setEntry(entry, forKey: "c")
    #expect(await store.entry(forKey: "a") != nil)
    #expect(await store.entry(forKey: "b") == nil)
    #expect(await store.entry(forKey: "c") != nil)
  }

  @Test func concurrentReadsAreSafe() async throws {
    let api = FakeAPI { _ in .json(Fixture.check(), headers: ["Cache-Control": "max-age=60", "ETag": "\"e\""]) }
    let customer = try api.server().customer("u")
    try await api.run {
      try await withThrowingTaskGroup(of: Bool.self) { group in
        for index in 0..<50 {
          group.addTask { try await customer.check(index % 2 == 0 ? "sso" : "export_pdf").entitled }
        }
        for try await entitled in group { #expect(entitled) }
      }
    }
    #expect(api.count <= 50)
  }

  @Test func staleAnswersStandInWhenUnreachable() async throws {
    let errors = Box<[EntitlerError]>([])
    let api = FakeAPI(replies: [
      .json(Fixture.check(), headers: ["ETag": "\"e\""]), .error(503, code: "unavailable"),
      .error(503, code: "unavailable"), .error(503, code: "unavailable"),
    ])
    let customer = try api.server { options in options.onError = { error in errors.with { $0.append(error) } } }.customer("u")
    try await api.run {
      _ = try await customer.check("sso")
      let stale = try await customer.check("sso")
      #expect(stale.stale)
      #expect(stale.entitled)
    }
    #expect(errors.get.count == 1)
  }

  @Test func staleAnswersExpireAfterStaleFor() async throws {
    let api = FakeAPI(replies: [.json(Fixture.check(), headers: ["ETag": "\"e\""]), .failure(.notConnectedToInternet)])
    let customer = try api.server { $0.staleFor = 60; $0.maxRetries = 0 }.customer("u")
    try await api.run {
      _ = try await customer.check("sso")
      api.advance(61)
      await #expect(throws: EntitlerError.self) { try await customer.check("sso") }
    }
  }

  @Test func otherFailuresAreNotHiddenByStaleAnswers() async throws {
    let api = FakeAPI(replies: [.json(Fixture.check(), headers: ["ETag": "\"e\""]), .error(403, code: "scope_required")])
    let customer = try api.server().customer("u")
    try await api.run {
      _ = try await customer.check("sso")
      await #expect(throws: EntitlerError.self) { try await customer.check("sso") }
    }
  }

  @Test func eachStaleAnswerTypeIsMarked() async throws {
    let replies: [String] = [
      Fixture.entitlements,
      #"{"customer":"u","asOf":"2026-10-09T01:47:13Z","held":[],"options":[],\#(Fixture.context)}"#,
      #"{\#(Fixture.context),"customer":"u","defaultPlan":null,"products":[],"plans":[]}"#,
      Fixture.meteredCheck,
    ]
    let api = FakeAPI { _ in .failure(.notConnectedToInternet) }
    let customer = try api.server { $0.maxRetries = 0 }.customer("u")
    for (index, body) in replies.enumerated() {
      api.answer { _ in .json(body, headers: ["ETag": "\"e\""]) }
      try await api.run {
        switch index {
        case 0: _ = try await customer.entitlements()
        case 1: _ = try await customer.planSpace()
        case 2: _ = try await customer.pricing()
        default: _ = try await customer.check(Feature<Metered>("ai_credits"))
        }
      }
    }
    api.answer { _ in .failure(.notConnectedToInternet) }
    let stale = try await api.run {
      [
        try await customer.entitlements().stale, try await customer.planSpace().stale,
        try await customer.pricing().stale, try await customer.check(Feature<Metered>("ai_credits")).stale,
      ]
    }
    #expect(stale == [true, true, true, true])
  }

  @Test func isEntitledAnswersDefaultsAndReportsErrors() async throws {
    let errors = Box(0)
    let api = FakeAPI { _ in .error(404, code: "feature_not_found") }
    let customer = try api.server { $0.onError = { _ in errors.with { $0 += 1 } } }.customer("u")
    await api.run {
      #expect(await customer.isEntitled(to: "missing", default: true))
      #expect(await !customer.isEntitled(to: Feature<OnOff>("missing"), default: false))
    }
    #expect(errors.get == 2)
    api.answer { _ in .json(Fixture.check(entitled: false, value: "0")) }
    await api.run { #expect(await !customer.isEntitled(to: "sso", default: true)) }
  }

  @Test func isEntitledAnswersDefaultOnCancellationWithoutOnError() async throws {
    let errors = Box(0)
    let api = FakeAPI { _ in .hanging }
    let customer = try api.server { $0.onError = { _ in errors.with { $0 += 1 } } }.customer("u")
    let task = Task { await api.run { await customer.isEntitled(to: "sso", default: true) } }
    try await Task.sleep(nanoseconds: 50_000_000)
    task.cancel()
    #expect(await task.value)
    #expect(errors.get == 0)
  }
}

@Suite struct TokenTests {
  @Test func providerIsAskedOnFirstUseAndBeforeExpiry() async throws {
    let calls = Box(0)
    let api = FakeAPI { _ in .json(Fixture.check()) }
    let client = try EntitlerClient(
      tokenProvider: {
        let n = calls.with { $0 += 1; return $0 }
        return makeJWT(["sub": "user_1", "exp": 1_800_000_100, "n": n])
      }, options: api.options { $0.cache = nil })
    try await api.run {
      #expect(calls.get == 0)
      _ = try await client.me.check("sso")
      _ = try await client.me.check("sso")
      #expect(calls.get == 1)
      api.advance(41)
      _ = try await client.me.check("sso")
      #expect(calls.get == 2)
    }
    #expect(api.last.header("Authorization")?.hasPrefix("Bearer ey") == true)
    #expect(api.last.path == "/customers/me/entitlements/sso")
    #expect(api.last.header("Entitler-Visitor") == client.visitor)
  }

  @Test func unauthorisedRefreshesOnceAndRetries() async throws {
    let calls = Box(0)
    let api = FakeAPI(replies: [.error(401, code: "unauthorised"), .json(Fixture.check())])
    let client = try EntitlerClient(
      tokenProvider: { calls.with { $0 += 1; return makeJWT(["sub": "u", "n": $0]) } },
      options: api.options())
    _ = try await api.run { try await client.me.check("sso") }
    #expect(calls.get == 2)
    #expect(api.count == 2)
    #expect(api.requests.get[0].header("Authorization") != api.requests.get[1].header("Authorization"))
  }

  @Test func secondUnauthorisedFails() async throws {
    let api = FakeAPI { _ in .error(401, code: "unauthorised") }
    let client = try EntitlerClient(tokenProvider: { makeJWT(["sub": "u", "r": Int.random(in: 0...1_000_000)]) }, options: api.options())
    await #expect(throws: EntitlerError.self) { try await api.run { try await client.me.check("sso") } }
    #expect(api.count == 2)
  }

  @Test func fixedTokensAreNotRefreshed() async throws {
    let api = FakeAPI { _ in .error(401, code: "unauthorised") }
    let client = try EntitlerClient(token: "fixed", options: api.options())
    await #expect(throws: EntitlerError.self) { try await api.run { try await client.me.check("sso") } }
    #expect(api.count == 1)
    #expect(api.last.header("Authorization") == "Bearer fixed")
  }

  @Test func credentialNotAllowedIsNeitherRetriedNorRefreshed() async throws {
    let calls = Box(0)
    let api = FakeAPI { _ in .error(403, code: "credential_not_allowed") }
    let client = try EntitlerClient(tokenProvider: { calls.with { $0 += 1 }; return makeJWT(["sub": "u"]) }, options: api.options())
    do {
      _ = try await api.run { try await client.me.check("sso") }
    } catch EntitlerError.api(let error) {
      #expect(error.code == .credentialNotAllowed)
    }
    #expect(calls.get == 1)
    #expect(api.count == 1)
  }

  @Test func concurrentRequestsShareOneRefresh() async throws {
    let calls = Box(0)
    let api = FakeAPI { _ in .json(Fixture.check()) }
    let client = try EntitlerClient(
      tokenProvider: {
        calls.with { $0 += 1 }
        try await Task.sleep(nanoseconds: 50_000_000)
        return makeJWT(["sub": "u"])
      }, options: api.options { $0.cache = nil })
    try await api.run {
      try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<10 { group.addTask { _ = try await client.me.check("sso") } }
        try await group.waitForAll()
      }
    }
    #expect(calls.get == 1)
  }

  @Test func failingAndUnusableProvidersThrowTokenErrors() async throws {
    struct Boom: Error {}
    let api = FakeAPI { _ in .json(Fixture.check()) }
    let failing = try EntitlerClient(tokenProvider: { throw Boom() }, options: api.options())
    do {
      _ = try await api.run { try await failing.me.check("sso") }
      Issue.record("Expected an error")
    } catch EntitlerError.token(let error) {
      #expect(error.underlyingError is Boom)
      #expect(error.message.hasPrefix("The token provider failed"))
    }
    let blank = try EntitlerClient(key: "pk", identityTokenProvider: { "  " }, options: api.options())
    do {
      _ = try await api.run { try await blank.me.check("sso") }
    } catch EntitlerError.token(let error) {
      #expect(error.message == "Provide the identity token your sign-in provider issued.")
    }
    let unreadable = try EntitlerClient(tokenProvider: { "not-a-jwt" }, options: api.options())
    do {
      _ = try await api.run { try await unreadable.me.check("sso") }
    } catch EntitlerError.token(let error) {
      #expect(!error.message.contains("not-a-jwt"))
    }
    #expect(api.count == 0)
  }

  @Test func identityClientsSendKeyAndToken() async throws {
    let api = FakeAPI { request in
      request.path == "/keys/self"
        ? .json(#"{"scopes":["customers:register","entitlements:read"],"registration":false}"#)
        : request.path == "/customers/snapshot-keys" ? .json(#"{"keys":[]}"#)
        : .json(#"{"id":"c","externalId":"google:1","environmentId":"e","createdAt":"2026-10-09T01:47:13Z","created":true}"#, status: 201)
    }
    let token = makeJWT(["iss": "https://accounts.google.com", "sub": "1"])
    let client = try EntitlerClient(key: "pk_live", identityToken: token, options: api.options())
    try await api.run {
      let registered = try await client.register()
      #expect(registered.created)
      #expect(registered.externalID == "google:1")
      #expect(api.last.method == "PUT")
      #expect(api.last.path == "/customers/me")
      #expect(api.last.body == nil || api.last.body?.isEmpty == true)
      #expect(api.last.header("Authorization") == "Bearer pk_live")
      #expect(api.last.header("Entitler-Identity-Token") == token)
      let scopes = try await client.scopes()
      #expect(scopes.scopes == [.entitlementsRead, .customersRegister])
      #expect(scopes.registration == false)
      _ = try await client.snapshotKeys()
      #expect(api.last.header("Entitler-Identity-Token") == nil)
    }
  }

  @Test func signedInIdComesFromTheLatestAnswer() async throws {
    let api = FakeAPI { _ in .json(Fixture.check(customer: "user_9")) }
    let client = try EntitlerClient(token: "t", options: api.options())
    #expect(await client.me.id == nil)
    _ = try await api.run { try await client.me.check("sso") }
    #expect(await client.me.id == "user_9")
    #expect(try EntitlerServer(key: "k").customer("x").id == "x")
  }
}

final class RecordingStore: CacheStore {
  let inner = MemoryCacheStore(capacity: 100)
  let written = Box<Set<String>>([])
  var keys: Set<String> { written.get }
  func entry(forKey key: String) async -> CacheEntry? { await inner.entry(forKey: key) }
  func setEntry(_ entry: CacheEntry, forKey key: String) async {
    written.with { _ = $0.insert(key) }
    await inner.setEntry(entry, forKey: key)
  }
}

func makeJWT(_ claims: [String: Any]) -> String {
  let header = Base64URL.encode(Data(#"{"alg":"none"}"#.utf8))
  let payload = Base64URL.encode(try! JSONSerialization.data(withJSONObject: claims))
  return "\(header).\(payload).sig"
}
