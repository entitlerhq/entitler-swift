import Foundation
import Testing

@testable import Entitler

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct Recorded: Sendable {
  let method: String
  let url: URL
  let headers: [String: String]
  let body: Data?

  var path: String {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
  }
  var query: String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery
  }
  func header(_ name: String) -> String? {
    headers.first { $0.key.lowercased() == name.lowercased() }?.value
  }
  var json: [String: Any]? {
    body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
  }
}

struct Reply: Sendable {
  var status = 200
  var headers: [String: String] = [:]
  var body = Data()
  var failure: URLError.Code?
  var hang = false

  static func json(_ text: String, status: Int = 200, headers: [String: String] = [:]) -> Reply {
    Reply(
      status: status, headers: headers.merging(["Content-Type": "application/json"]) { $1 },
      body: Data(text.utf8))
  }

  static func error(
    _ status: Int, code: String, message: String = "Refused.", headers: [String: String] = [:]
  ) -> Reply {
    .json(
      #"{"error":{"code":"\#(code)","message":"\#(message)"}}"#, status: status, headers: headers)
  }

  static func failure(_ code: URLError.Code) -> Reply { Reply(failure: code) }
  static let hanging = Reply(hang: true)
}

final class Box<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value
  init(_ value: Value) { self.value = value }
  func with<T>(_ body: (inout Value) -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body(&value)
  }
  var get: Value { with { $0 } }
}

/// A fake API: answers each request from a handler and records it.
final class FakeAPI: Sendable {
  let host = "t\(UUID().uuidString.prefix(8).lowercased()).test"
  let requests = Box<[Recorded]>([])
  let handler: Box<@Sendable (Recorded) -> Reply>
  let clock = Box(Date(timeIntervalSince1970: 1_800_000_000))
  let sleeps = Box<[TimeInterval]>([])

  init(_ handler: @escaping @Sendable (Recorded) -> Reply = { _ in .json("{}") }) {
    self.handler = Box(handler)
    FakeProtocol.apis.with { $0[host] = self }
  }

  convenience init(replies: [Reply]) {
    let queue = Box(replies)
    self.init { _ in queue.with { $0.isEmpty ? Reply.json("{}") : $0.removeFirst() } }
  }

  func answer(_ handler: @escaping @Sendable (Recorded) -> Reply) {
    self.handler.with { $0 = handler }
  }

  var baseURL: URL { URL(string: "https://\(host)/")! }

  var session: URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FakeProtocol.self]
    return URLSession(configuration: configuration)
  }

  func options(_ change: (inout EntitlerOptions) -> Void = { _ in }) -> EntitlerOptions {
    var options = EntitlerOptions(baseURL: baseURL, session: session)
    change(&options)
    return options
  }

  var hooks: Hooks {
    var hooks = Hooks()
    let clock = clock
    let sleeps = sleeps
    hooks.now = { clock.get }
    hooks.sleep = { seconds in
      try Task.checkCancellation()
      sleeps.with { $0.append(seconds) }
      clock.with { $0 += seconds }
      await Task.yield()
      try Task.checkCancellation()
    }
    hooks.random = { $0.upperBound }
    return hooks
  }

  func advance(_ seconds: TimeInterval) { clock.with { $0 += seconds } }

  var last: Recorded { requests.get.last! }
  var count: Int { requests.get.count }

  func run<T>(_ body: () async throws -> T) async rethrows -> T {
    try await Hooks.$current.withValue(hooks) { try await body() }
  }

  func server(_ change: (inout EntitlerOptions) -> Void = { _ in }) throws -> EntitlerServer {
    try EntitlerServer(key: "sk_test", options: options(change))
  }
}

final class FakeProtocol: URLProtocol {
  static let apis = Box<[String: FakeAPI]>([:])

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url, let api = Self.apis.get[url.host ?? ""] else {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
      return
    }
    var body = request.httpBody
    if body == nil, let stream = request.httpBodyStream {
      var data = Data()
      stream.open()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        if read <= 0 { break }
        data.append(buffer, count: read)
      }
      stream.close()
      body = data
    }
    let recorded = Recorded(
      method: request.httpMethod ?? "GET", url: url, headers: request.allHTTPHeaderFields ?? [:],
      body: body)
    api.requests.with { $0.append(recorded) }
    let reply = api.handler.get(recorded)
    if reply.hang { return }
    if let failure = reply.failure {
      client?.urlProtocol(self, didFailWithError: URLError(failure))
      return
    }
    let response = HTTPURLResponse(
      url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: reply.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

enum Fixture {
  static let context = """
    "environment":{"id":"env_1","name":"development","kind":"test"},"track":{"id":"trk_1","name":"All customers"},\
    "release":2,"change":null,"testers":true,"experiment":null
    """

  static func check(
    _ feature: String = "sso", entitled: Bool = true, value: String = "true",
    customer: String = "user_1"
  ) -> String {
    #"{"customer":"\#(customer)","asOf":"2026-10-09T01:47:13.968Z","feature":"\#(feature)","type":"boolean","entitled":\#(entitled),"value":\#(value),"sources":[{"type":"plan","plan":"pro","name":"Pro","version":1,"byDefault":false,"value":true}],"upgrades":[],\#(context)}"#
  }

  static let meteredCheck =
    #"{"customer":"user_1","asOf":"2026-10-09T01:47:13Z","feature":"ai_credits","type":"metered","entitled":true,"value":300,"sources":[],"used":10,"held":5,"remaining":285,"resetsAt":"2026-10-18T21:30:35.544+02:00","upgrades":[],\#(context),"futureField":{"x":1}}"#

  static func usage(
    outcome: String = "recorded", refusal: String = "null", holdID: String = "null", amount: Int = 3
  ) -> String {
    #"{"customer":"user_1","asOf":"2026-10-09T01:47:13.968Z","feature":"ai_credits","type":"metered","entitled":true,"value":300,"sources":[],"used":3,"held":0,"remaining":297,"resetsAt":null,"upgrades":[],"outcome":"\#(outcome)","refusal":\#(refusal),"id":"u_1","holdId":\#(holdID),"mode":"gate","amount":\#(amount),"meterChange":3,"overBy":0,"late":false,"occurredAt":"2026-10-09T01:47:13.968Z","expiresAt":null,"reportedAs":"api",\#(context)}"#
  }

  static let entitlements =
    #"{"customer":"user_1","asOf":"2026-10-09T01:47:13.968Z","entitlements":[{"key":"export_pdf","type":"boolean","entitled":true,"value":true,"sources":[]},{"key":"collaboration","type":"group","entitled":false,"value":0,"sources":[{"type":"group","features":["team_seats"]}]},{"key":"ai_credits","type":"metered","entitled":true,"value":"unlimited","sources":[],"used":2,"held":0,"remaining":"unlimited","resetsAt":null}],\#(context)}"#

  static let summary =
    #"{"id":"c_1","externalId":"user_1","name":"Ada","email":"ada@example.com","environmentId":"env_1","sample":false,"createdAt":"2026-10-09T01:47:13.968Z","plan":{"id":"p_1","key":"free","name":"Free","version":1},"plans":[{"id":"p_1","key":"free","name":"Free","version":1,"product":"app"}],"defaultPlan":{"id":"p_1","key":"free","name":"Free"},"status":"active","kind":"default","metadata":{"team":"a"},"track":{"id":"trk_1","name":"All customers"},"testCustomer":false}"#

  static let detail =
    #"{"customer":\#(summary),"asOf":"2026-10-09T01:47:13.968Z","subscription":{"product":{"key":"app","name":"App"},"plan":{"id":"p_2","key":"pro","name":"Pro"},"version":1,"cohort":null,"period":"monthly","startedAt":"2026-10-01T00:00:00Z","renewsAt":"2026-11-01T00:00:00Z","billing":null,"addOns":[{"plan":{"id":"p_3","key":"sso_addon","name":"SSO"},"version":1,"quantity":1,"countable":false,"addedAt":"2026-10-01T00:00:00Z","movingTo":null,"purchase":{"money":"test","channel":null,"release":2,"change":null,"arm":null}}],"pending":{"type":"cancel","movingTo":{"id":"p_1","key":"free","name":"Free"}},"purchase":{"money":"test","channel":{"provider":"stripe","connectionId":"conn_1"},"release":2,"change":null,"arm":"control"},"override":null},"defaultPlan":null,"products":[],"addOns":[],"entitlements":[],"banked":{"ai_credits":5},"moveOptions":[],"grants":[{"id":"g_1","feature":"sso","value":"true","from":"2026-10-01T00:00:00Z","until":null,"revokedAt":null,"reason":"Trial","by":"key"}],"usage":{"items":[],"next":null},"activity":[{"text":"Registered","at":"2026-10-01T00:00:00Z"}],"selfServe":true,"environment":{"id":"env_1","name":"development","kind":"test"}}"#
}
