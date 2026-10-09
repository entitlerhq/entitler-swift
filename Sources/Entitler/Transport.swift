import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
#if canImport(CryptoKit)
  import CryptoKit
#else
  import Crypto
#endif

struct Hooks: Sendable {
  var now: @Sendable () -> Date = { Date() }
  var sleep: @Sendable (TimeInterval) async throws -> Void = { seconds in
    try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
  }
  var random: @Sendable (ClosedRange<Double>) -> Double = { Double.random(in: $0) }

  @TaskLocal static var current = Hooks()
}

enum Credential: Sendable {
  case server(key: String)
  case token(TokenSource)
  case identity(key: String, TokenSource)
}

struct Request: Sendable {
  var method = "GET"
  var path: String
  var query: [(name: String, value: String)] = []
  var body: Data?
  var idempotencyKey: String?
  var visitor: String?
  var timeout: TimeInterval?
  var cached = false
  var customer: String?
  var authenticated = true

  init(_ method: String, _ segments: [String], body: (any Encodable)? = nil) throws {
    self.method = method
    path = "/" + segments.map(\.componentEncoded).joined(separator: "/")
    if let body { self.body = try JSON.encoder().encode(body) }
  }
}

struct Response: Sendable {
  let status: Int
  let body: Data
  let etag: String?
  let maxAge: TimeInterval?
  let noStore: Bool
}

struct Named: Decodable {
  let customer: String
}

actor SignedInID {
  private(set) var id: String?

  func set(_ id: String) { self.id = id }
}

actor WriteLog {
  private var times: [String: Date] = [:]
  private var longestMaxAge: TimeInterval = 0

  func record(_ customer: String, at now: Date) {
    times[customer] = now
    if times.count > 1_000 {
      times = times.filter { now.timeIntervalSince($0.value) <= longestMaxAge }
    }
  }

  func wrote(to customer: String, since date: Date) -> Bool {
    times[customer].map { $0 >= date } ?? false
  }

  func noteMaxAge(_ maxAge: TimeInterval) {
    longestMaxAge = max(longestMaxAge, maxAge)
  }
}

final class Core: Sendable, CustomReflectable {
  let options: EntitlerOptions
  let credential: Credential
  let visitor: String?
  let writes = WriteLog()
  let signedIn: SignedInID?

  init(options: EntitlerOptions, credential: Credential, visitor: String?) throws {
    self.options = try options.validated()
    self.credential = credential
    self.visitor = visitor
    if case .server = credential { signedIn = nil } else { signedIn = SignedInID() }
  }

  var kind: String {
    switch credential {
    case .server: "server"
    case .token: "in-app, customer token"
    case .identity: "in-app, identity token"
    }
  }

  var customMirror: Mirror { Mirror(self, children: ["baseURL": options.base, "kind": kind]) }

  func call<Answer: Decodable>(_ request: Request) async throws -> Answer {
    try decode(try await send(request))
  }

  func cachedCall<Answer: Decodable>(_ request: Request) async throws -> Answer {
    var request = request
    request.cached = true
    let (response, stale) = try await read(request)
    let answer: Answer = try decode(response)
    return stale ? markedStale(answer) : answer
  }

  private func decode<Answer: Decodable>(_ response: Response) throws -> Answer {
    do {
      return try JSON.decoder().decode(Answer.self, from: response.body)
    } catch {
      throw EntitlerError.api(
        APIError(
          status: response.status, code: .httpError,
          message: "Entitler answered with a body this SDK cannot read.", requestID: nil,
          retryAfter: nil, idempotencyKey: nil, payment: nil, listingGaps: [], listingProblems: []))
    }
  }

  private func read(_ request: Request) async throws -> (Response, stale: Bool) {
    guard let cache = options.cache else { return (try await send(request), false) }
    let hooks = Hooks.current
    let key = try await cacheKey(request)
    let kept = await cache.entry(forKey: key)
    if let kept, let maxAge = kept.maxAge, hooks.now().timeIntervalSince(kept.receivedAt) < maxAge {
      let written = await request.customer.asyncMap { await writes.wrote(to: $0, since: kept.receivedAt) }
      if written != true { return (Response(status: 200, body: kept.body), false) }
    }
    do {
      let response = try await send(request, ifNoneMatch: kept?.etag)
      if response.status == 304 {
        guard let kept else {
          throw EntitlerError.api(
            APIError(
              status: 304, code: .httpError, message: "Entitler request failed with HTTP 304.",
              requestID: nil, retryAfter: nil, idempotencyKey: nil, payment: nil, listingGaps: [],
              listingProblems: []))
        }
        await keep(response, body: kept.body, etag: response.etag ?? kept.etag, key: key, in: cache)
        return (Response(status: 200, body: kept.body), false)
      }
      await keep(response, body: response.body, etag: response.etag, key: key, in: cache)
      return (response, false)
    } catch let error as EntitlerError where error.isUnreachable {
      guard let kept, hooks.now().timeIntervalSince(kept.receivedAt) < options.staleFor else { throw error }
      options.onError?(error)
      return (Response(status: 200, body: kept.body), true)
    }
  }

  private func keep(_ response: Response, body: Data, etag: String?, key: String, in cache: any CacheStore) async {
    guard !response.noStore, etag != nil || response.maxAge != nil else { return }
    if let maxAge = response.maxAge { await writes.noteMaxAge(maxAge) }
    await cache.setEntry(
      CacheEntry(body: body, etag: etag, maxAge: response.maxAge, receivedAt: Hooks.current.now()),
      forKey: key)
  }

  private func cacheKey(_ request: Request) async throws -> String {
    let principal: String
    switch credential {
    case .server(let key):
      principal = key
    case .token(let source):
      principal = JWT.principal(try await source.token(now: Hooks.current.now()), claims: ["iss", "eid", "sub"])
    case .identity(let key, let source):
      let token = try await source.token(now: Hooks.current.now())
      principal = key + "\n" + JWT.principal(token, claims: ["iss", "sub"])
    }
    let parts = [
      request.method, url(for: request).absoluteString, options.asOf.map(formatInstant) ?? "",
      request.visitor ?? visitor ?? "", principal,
    ]
    return SHA256.hash(data: Data(parts.joined(separator: "\n").utf8))
      .map { String(format: "%02x", $0) }.joined()
  }

  func url(for request: Request) -> URL {
    var text = options.base + request.path
    if !request.query.isEmpty {
      text += "?" + request.query.map { "\($0.name.componentEncoded)=\($0.value.componentEncoded)" }
        .joined(separator: "&")
    }
    return URL(string: text)!
  }

  func send(_ request: Request, ifNoneMatch etag: String? = nil) async throws -> Response {
    guard request.method != "GET", let customer = request.customer else {
      return try await exchange(request, ifNoneMatch: etag)
    }
    await writes.record(customer, at: Hooks.current.now())
    do {
      let response = try await exchange(request, ifNoneMatch: etag)
      await writes.record(customer, at: Hooks.current.now())
      return response
    } catch {
      await writes.record(customer, at: Hooks.current.now())
      throw error
    }
  }

  private func exchange(_ request: Request, ifNoneMatch etag: String?) async throws -> Response {
    let hooks = Hooks.current
    let idempotencyKey = request.method == "GET" ? nil : request.idempotencyKey ?? UUID().uuidString.lowercased()
    let timeout = request.timeout ?? options.timeout
    var retries = 0
    var refreshed = false
    while true {
      let token = request.authenticated ? try await currentToken() : nil
      var urlRequest = URLRequest(url: url(for: request), timeoutInterval: timeout)
      urlRequest.httpMethod = request.method
      urlRequest.httpBody = request.body
      for (name, value) in headers(request, token: token, idempotencyKey: idempotencyKey, etag: etag) {
        urlRequest.setValue(value, forHTTPHeaderField: name)
      }
      let failure: EntitlerError
      do {
        let (body, http) = try await attempt(urlRequest, timeout: timeout, idempotencyKey: idempotencyKey)
        if http.statusCode == 401, !refreshed, let token, let fresh = try await refresh(replacing: token),
          fresh != token
        {
          refreshed = true
          continue
        }
        let response = Response(http, body: body)
        if (200..<300).contains(http.statusCode) || (http.statusCode == 304 && etag != nil) {
          if let signedIn, let named = try? JSON.decoder().decode(Named.self, from: body) {
            await signedIn.set(named.customer)
          }
          return response
        }
        let error = apiError(http, body: body, idempotencyKey: idempotencyKey, now: hooks.now())
        guard [408, 429, 500, 502, 503, 504].contains(http.statusCode), retries < options.maxRetries else {
          throw EntitlerError.api(error)
        }
        if let retryAfter = error.retryAfter {
          guard retryAfter <= options.maxRetryDelay else { throw EntitlerError.api(error) }
          try await hooks.sleep(retryAfter)
          retries += 1
          continue
        }
        failure = .api(error)
      } catch let error as EntitlerError {
        switch error {
        case .connection, .timeout: failure = error
        default: throw error
        }
      }
      guard retries < options.maxRetries else { throw failure }
      try await hooks.sleep(hooks.random(0...min(8, 0.5 * pow(2, Double(retries)))))
      retries += 1
    }
  }

  private func attempt(
    _ request: URLRequest, timeout: TimeInterval, idempotencyKey: String?
  ) async throws -> (Data, HTTPURLResponse) {
    let session = options.session
    let hooks = Hooks.current
    do {
      let (body, response) = try await withThrowingTaskGroup(of: (Data, URLResponse)?.self) { group in
        group.addTask { try await session.data(for: request) }
        group.addTask {
          try await hooks.sleep(timeout)
          return nil
        }
        defer { group.cancelAll() }
        guard let first = try await group.next(), let answer = first else {
          throw EntitlerError.timeout(TimeoutError(timeout: timeout, idempotencyKey: idempotencyKey))
        }
        return answer
      }
      guard let http = response as? HTTPURLResponse else {
        throw EntitlerError.connection(ConnectionError(underlyingError: URLError(.badServerResponse), idempotencyKey: idempotencyKey))
      }
      return (body, http)
    } catch let error as EntitlerError {
      throw error
    } catch {
      if Task.isCancelled || error is CancellationError { throw CancellationError() }
      if let error = error as? URLError, error.code == .timedOut {
        throw EntitlerError.timeout(TimeoutError(timeout: timeout, idempotencyKey: idempotencyKey))
      }
      throw EntitlerError.connection(ConnectionError(underlyingError: error, idempotencyKey: idempotencyKey))
    }
  }

  private func headers(_ request: Request, token: String?, idempotencyKey: String?, etag: String?) -> [String: String] {
    var headers = ["Accept": "application/json", "User-Agent": userAgent]
    if let token { headers["Authorization"] = "Bearer \(token)" }
    if case .identity(let key, _) = credential, let token {
      headers["Authorization"] = "Bearer \(key)"
      headers["Entitler-Identity-Token"] = token
    }
    if request.body != nil { headers["Content-Type"] = "application/json" }
    if let idempotencyKey { headers["Idempotency-Key"] = idempotencyKey }
    if let visitor = request.visitor ?? visitor { headers["Entitler-Visitor"] = visitor }
    if let asOf = options.asOf { headers["Entitler-As-Of"] = formatInstant(asOf) }
    if let etag { headers["If-None-Match"] = etag }
    return headers
  }

  private func currentToken() async throws -> String {
    switch credential {
    case .server(let key): key
    case .token(let source), .identity(_, let source): try await source.token(now: Hooks.current.now())
    }
  }

  private func refresh(replacing token: String) async throws -> String? {
    switch credential {
    case .server: nil
    case .token(let source), .identity(_, let source): try await source.refresh(replacing: token)
    }
  }

  private func apiError(_ http: HTTPURLResponse, body: Data, idempotencyKey: String?, now: Date) -> APIError {
    struct Body: Decodable {
      struct Detail: Decodable {
        let code: ErrorCode?
        let message: String?
        let payment: Payment?
        let listingGaps: [ListingGap]?
        let listingProblems: [ListingProblem]?
      }
      let error: Detail?
    }
    let detail = (try? JSON.decoder().decode(Body.self, from: body))?.error
    return APIError(
      status: http.statusCode,
      code: detail?.code ?? .httpError,
      message: detail?.message ?? "Entitler request failed with HTTP \(http.statusCode).",
      requestID: http.value(forHTTPHeaderField: "x-request-id"),
      retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap { retryAfter($0, now: now) },
      idempotencyKey: idempotencyKey,
      payment: detail?.payment,
      listingGaps: detail?.listingGaps ?? [],
      listingProblems: detail?.listingProblems ?? [])
  }
}

func retryAfter(_ value: String, now: Date) -> TimeInterval? {
  let value = value.trimmed
  if let seconds = TimeInterval(value), seconds >= 0 { return seconds }
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(identifier: "GMT")
  formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
  return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
}

extension Response {
  init(status: Int, body: Data) {
    self.init(status: status, body: body, etag: nil, maxAge: nil, noStore: false)
  }

  init(_ http: HTTPURLResponse, body: Data) {
    let directives = (http.value(forHTTPHeaderField: "Cache-Control") ?? "").lowercased()
      .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    self.init(
      status: http.statusCode,
      body: body,
      etag: http.value(forHTTPHeaderField: "ETag"),
      maxAge: directives.first { $0.hasPrefix("max-age=") }.flatMap { TimeInterval($0.dropFirst(8)) },
      noStore: directives.contains("no-store"))
  }
}

extension Optional {
  func asyncMap<Mapped>(_ transform: (Wrapped) async throws -> Mapped) async rethrows -> Mapped? {
    guard let self else { return nil }
    return try await transform(self)
  }
}

let userAgent: String = {
  #if os(iOS)
    let system = "iOS"
  #elseif os(macOS)
    let system = "macOS"
  #elseif os(tvOS)
    let system = "tvOS"
  #elseif os(watchOS)
    let system = "watchOS"
  #elseif os(visionOS)
    let system = "visionOS"
  #elseif os(Linux)
    let system = "Linux"
  #else
    let system = "unknown"
  #endif
  let version = ProcessInfo.processInfo.operatingSystemVersion
  return "entitler-swift/\(entitlerSDKVersion) \(system)/\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
}()
