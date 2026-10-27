import Foundation
import Testing

@testable import Entitler

@Suite struct TransportTests {
  @Test func aRefusalCarriesTheAPIsCodeReasonParametersAndRequestID() async throws {
    let api = FakeAPI([
      Answer(
        status: 400, headers: ["x-request-id": "rq_1"],
        body: refusal(
          "InvalidArgument", "FEATURE_KEY_INVALID", parameters: ["field": "feature_key"]))
    ])
    do {
      _ = try await api.server().customer("ada").check("priority_support")
      Issue.record("Expected a refusal.")
    } catch EntitlerError.api(let error) {
      #expect(error.status == 400)
      #expect(error.code == "InvalidArgument")
      #expect(error.reason == Reason(rawValue: "FEATURE_KEY_INVALID"))
      #expect(error.parameters == ["field": "feature_key"])
      #expect(error.requestID == "rq_1")
      #expect(api.requests.count == 1)
    }
  }

  @Test(arguments: [
    (status: 404, code: "NotFound"), (status: 409, code: "Aborted"),
    (status: 502, code: "Internal"),
    (status: 418, code: "Unknown"),
  ])
  func anUnreadableRefusalTakesTheCodeOfItsStatus(status: Int, code: String) async throws {
    let api = FakeAPI([Answer(status: status, body: "<html>")])
    let server = try api.server(options: EntitlerOptions(maxRetries: 0))
    do {
      _ = try await server.customer("ada").check("priority_support")
      Issue.record("Expected a refusal.")
    } catch EntitlerError.api(let error) {
      #expect(error.code == code)
      #expect(error.reason == nil)
    }
  }

  @Test func retriesAfterTheWaitTheAPIAsksFor() async throws {
    let slept = LockedValue<[TimeInterval]>([])
    let api = FakeAPI([
      Answer(
        status: 429, headers: ["Retry-After": "3"],
        body: refusal("ResourceExhausted", "API_RATE_LIMITED")),
      Answer(body: switchCheck),
    ])
    var hooks = instantHooks
    hooks.sleep = { seconds in slept.update { $0.append(seconds) } }
    let check = try await api.server(hooks: hooks).customer("ada").check("priority_support")
    #expect(check.entitled)
    #expect(slept.read() == [3])
    #expect(api.requests.count == 2)
  }

  @Test func aWaitLongerThanMaxRetryDelayFailsAtOnce() async throws {
    let api = FakeAPI([
      Answer(
        status: 429, headers: ["Retry-After": "60"],
        body: refusal("ResourceExhausted", "API_RATE_LIMITED"))
    ])
    do {
      _ = try await api.server().customer("ada").check("priority_support")
      Issue.record("Expected a refusal.")
    } catch EntitlerError.api(let error) {
      #expect(error.retryAfter == 60)
      #expect(api.requests.count == 1)
    }
  }

  @Test func serverErrorsAndLostConnectionsAreRetriedWithBackoff() async throws {
    let api = FakeAPI([
      Answer(status: 503, body: refusal("Unavailable", nil)),
      Answer(failure: .networkConnectionLost),
      Answer(body: switchCheck),
    ])
    let check = try await api.server().customer("ada").check("priority_support")
    #expect(check.entitled)
    #expect(api.requests.count == 3)
  }

  @Test func retriesStopAtMaxRetries() async throws {
    let api = FakeAPI(
      Array(repeating: Answer(status: 500, body: refusal("Internal", nil)), count: 5))
    await #expect(throws: EntitlerError.self) {
      try await api.server(options: EntitlerOptions(maxRetries: 2)).customer("ada").check(
        "priority_support")
    }
    #expect(api.requests.count == 3)
  }

  @Test func aConnectionFailureIsAConnectionError() async throws {
    let api = FakeAPI([Answer(failure: .cannotFindHost)])
    do {
      _ = try await api.server(options: EntitlerOptions(maxRetries: 0)).customer("ada").check(
        "priority_support")
      Issue.record("Expected a failure.")
    } catch EntitlerError.connection(let error) {
      #expect((error.underlyingError as? URLError)?.code == .cannotFindHost)
    }
  }

  @Test func aKeptAnswerIsRevalidatedWithItsETag() async throws {
    let api = FakeAPI([
      Answer(
        headers: ["ETag": "W/\"v1\"", "Cache-Control": "private, no-cache"], body: switchCheck),
      Answer(status: 304, headers: ["ETag": "W/\"v1\""], body: ""),
    ])
    let customer = try api.server().customer("ada")
    _ = try await customer.check("priority_support")
    let again = try await customer.check("priority_support")

    #expect(again.entitled)
    #expect(api.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "W/\"v1\"")
  }

  @Test func aFreshAnswerIsServedWithoutARequest() async throws {
    let api = FakeAPI([Answer(headers: ["Cache-Control": "private, max-age=60"], body: switchCheck)]
    )
    let customer = try api.server().customer("ada")
    _ = try await customer.check("priority_support")
    _ = try await customer.check("priority_support")
    #expect(api.requests.count == 1)
  }

  @Test func aKeptAnswerStandsInWhileEntitlerIsUnreachable() async throws {
    let api = FakeAPI([
      Answer(
        headers: ["ETag": "W/\"v1\"", "Cache-Control": "private, no-cache"], body: switchCheck),
      Answer(failure: .notConnectedToInternet),
    ])
    let customer = try api.server(options: EntitlerOptions(maxRetries: 0)).customer("ada")
    _ = try await customer.check("priority_support")
    let stale = try await customer.check("priority_support")

    #expect(stale.entitled)
    #expect(stale.stale)
  }

  @Test func aDirectiveThatOnlyStartsWithNoStoreKeepsTheAnswer() async throws {
    let api = FakeAPI([
      Answer(headers: ["Cache-Control": "private, max-age=60, no-store-ish"], body: switchCheck)
    ])
    let customer = try api.server().customer("ada")
    _ = try await customer.check("priority_support")
    _ = try await customer.check("priority_support")
    #expect(api.requests.count == 1)
  }

  @Test func aNotModifiedAnswerMarkedNoStoreIsNotKept() async throws {
    let store = MemoryCacheStore(capacity: 10)
    let api = FakeAPI([
      Answer(
        headers: ["ETag": "W/\"v1\"", "Cache-Control": "private, no-cache"], body: switchCheck),
      Answer(status: 304, headers: ["ETag": "W/\"v2\"", "Cache-Control": "no-store"], body: ""),
    ])
    let server = try api.server(cache: store)
    let request = try Wire.entitlementsCheckFeature.request([
      "customer.external_id": "ada", "feature_key": "priority_support",
    ])
    _ = try await server.customer("ada").check("priority_support")
    let revalidated = try await server.customer("ada").check("priority_support")

    #expect(revalidated.entitled)
    #expect(await store.entry(forKey: server.core.cacheKey(request))?.etag == "W/\"v1\"")
  }

  @Test func anUnreadableKeptAnswerIsAMiss() async throws {
    let store = MemoryCacheStore(capacity: 10)
    let api = FakeAPI([Answer(body: switchCheck)])
    let server = try api.server(cache: store)
    let request = try Wire.entitlementsCheckFeature.request([
      "customer.external_id": "ada", "feature_key": "priority_support",
    ])
    await store.setEntry(
      CacheEntry(
        body: "{", etag: "W/\"v0\"", cacheControl: "private, max-age=600", age: nil,
        receivedAt: Date()),
      forKey: server.core.cacheKey(request), timeToLive: 600)

    let check = try await server.customer("ada").check("priority_support")

    #expect(check.entitled)
    #expect(api.requests.count == 1)
    #expect(api.requests.first?.value(forHTTPHeaderField: "If-None-Match") == nil)
  }

  @Test(arguments: [
    (header: "private, max-age=60", expected: true), (header: "no-store-ish", expected: false),
    (header: "x-max-age-hint=5", expected: false), (header: " Max-Age = 5", expected: true),
  ])
  func cacheDirectivesMatchByExactName(header: String, expected: Bool) {
    #expect(hasCacheDirective("max-age", in: header) == expected)
  }

  @Test func theCacheKeyHoldsNoCredential() throws {
    let server = try FakeAPI([]).server()
    let request = try Wire.entitlementsListEntitlements.request(["customer.external_id": "ada"])
    let key = server.core.cacheKey(request)
    #expect(key.count == 64)
    #expect(!key.contains("test-secret-key"))
  }
}
