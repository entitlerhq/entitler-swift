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
  var deadline: @Sendable (TimeInterval) async throws -> Void = { seconds in
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
  var method: String
  var path: String
  var query: [(name: String, value: String)] = []
  var body: Data?
  var idempotencyKey: String?
  var visitor: String?
  var timeout: TimeInterval?
  var customer: String?
  var changesAnswers = true
  var authenticated = true

  init(_ method: String, _ segments: [String], body: (any Encodable)? = nil) throws {
    guard !segments.contains(where: { !$0.isEmpty && $0.allSatisfy { $0 == "." } }) else {
      throw ArgumentError(message: Messages.dots)
    }
    self.method = method
    path = "/" + segments.map(\.componentEncoded).joined(separator: "/")
    if let body { self.body = try JSON.encoder().encode(body) }
  }
}

struct Response: Sendable {
  let status: Int
  let body: Data
  let etag: String?
  let cacheControl: String?
  let age: Int?
  let retryAfter: TimeInterval?
  var requestID: String? = nil

  var noStore: Bool { cacheControl?.lowercased().contains("no-store") ?? false }
}

struct Named: Decodable {
  let customer: String
}

actor ClientState {
  private var generations: [String: (generation: UInt64, at: Date)] = [:]
  private var counter: UInt64 = 0
  private var outageUntil: Date?
  private var probing = false
  private(set) var signedInID: String?

  func bump(_ customer: String, at now: Date) {
    counter += 1
    generations[customer] = (counter, now)
    if generations.count > 10_000 {
      generations = generations.filter { now.timeIntervalSince($0.value.at) < 86_400 }
    }
  }

  func generation(of customer: String?) -> (generation: UInt64, at: Date?) {
    guard let customer, let kept = generations[customer] else { return (0, nil) }
    return (kept.generation, kept.at)
  }

  func servesFromCache(at now: Date) -> Bool {
    guard let outageUntil else { return false }
    if now < outageUntil || probing { return true }
    probing = true
    return false
  }

  func reachable() {
    outageUntil = nil
    probing = false
  }

  func unreachable(until date: Date) {
    outageUntil = max(outageUntil ?? date, date)
    probing = false
  }

  func setSignedInID(_ id: String) { signedInID = id }
}

final class RedirectRefuser: NSObject, URLSessionTaskDelegate, Sendable {
  static let shared = RedirectRefuser()

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

@usableFromInline let defaultSession: URLSession = {
  let configuration = URLSessionConfiguration.default
  configuration.urlCache = nil
  configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
  return URLSession(
    configuration: configuration, delegate: RedirectRefuser.shared, delegateQueue: nil)
}()

final class Core: Sendable, CustomReflectable {
  let options: EntitlerOptions
  let credential: Credential
  let visitor: String?
  let state = ClientState()

  init(options: EntitlerOptions, credential: Credential, visitor: String?) throws {
    self.options = try options.validated()
    self.credential = credential
    self.visitor = visitor
  }

  var kind: String {
    switch credential {
    case .server: "server"
    case .token: "in-app, customer token"
    case .identity: "in-app, identity token"
    }
  }

  var isInApp: Bool {
    if case .server = credential { return false }
    return true
  }

  var customMirror: Mirror { Mirror(self, children: ["baseURL": options.base, "kind": kind]) }

  func report(_ error: any Error) {
    options.onError?(error)
  }

  func call<Answer: Decodable>(_ request: Request) async throws -> Answer {
    let response = try await send(request)
    return try decode(response)
  }

  private func decode<Answer: Decodable>(_ response: Response) throws -> Answer {
    do {
      let answer = try JSON.decoder().decode(Answer.self, from: response.body)
      if let checked = answer as? any MeterChecked, !checked.hasValidMeters {
        throw DecodingError.dataCorrupted(
          DecodingError.Context(codingPath: [], debugDescription: "A meter's remaining is true."))
      }
      return answer
    } catch {
      throw EntitlerError.api(
        APIError(
          status: response.status, code: .invalidResponse,
          message: "Entitler sent an answer this SDK cannot read.", requestID: response.requestID,
          retryAfter: nil, idempotencyKey: nil, payment: nil, listingGaps: [], listingProblems: [],
          underlyingError: error))
    }
  }

  func cachedCall<Answer: Decodable>(_ request: Request) async throws -> Answer {
    guard let cache = options.cache else { return try await call(request) }
    let hooks = Hooks.current
    let token: String?
    do {
      token = request.authenticated ? try await currentToken() : nil
    } catch let error as EntitlerError {
      guard case .token = error, let previous = await previousToken(),
        let kept = await entry(cacheKey(request, token: previous), in: cache),
        hooks.now().timeIntervalSince(kept.receivedAt) < options.staleFor
      else { throw error }
      report(error)
      return markedStale(try decode(Response(kept)))
    }
    let key = cacheKey(request, token: token)
    let kept = await entry(key, in: cache)
    let started = await state.generation(of: request.customer)
    if let kept, kept.isFresh(at: hooks.now()), started.at.map({ $0 < kept.receivedAt }) ?? true {
      return try decode(Response(kept))
    }
    if let kept, hooks.now().timeIntervalSince(kept.receivedAt) < options.staleFor,
      await state.servesFromCache(at: hooks.now())
    {
      return markedStale(try decode(Response(kept)))
    }
    do {
      let response = try await send(request, token: token, ifNoneMatch: kept?.etag)
      var entry: CacheEntry?
      if response.status == 304 {
        guard let kept else {
          throw EntitlerError.api(
            APIError(
              status: 304, code: .httpError, message: "Entitler answered with HTTP 304.",
              requestID: response.requestID, retryAfter: nil, idempotencyKey: nil, payment: nil,
              listingGaps: [],
              listingProblems: []))
        }
        entry = CacheEntry(
          body: kept.body, etag: response.etag ?? kept.etag,
          cacheControl: response.cacheControl ?? kept.cacheControl, age: response.age ?? kept.age,
          receivedAt: hooks.now())
      } else if !response.noStore,
        response.etag != nil || response.cacheControl?.lowercased().contains("max-age") == true
      {
        entry = CacheEntry(
          body: String(decoding: response.body, as: UTF8.self), etag: response.etag,
          cacheControl: response.cacheControl, age: response.age, receivedAt: hooks.now())
      }
      let answer: Answer = try decode(entry.map(Response.init) ?? response)
      await state.reachable()
      if var entry {
        if await state.generation(of: request.customer).generation != started.generation {
          entry.cacheControl = (entry.cacheControl.map { $0 + ", " } ?? "") + "no-cache"
        }
        await store(entry, key: key, in: cache)
      }
      return answer
    } catch let error as EntitlerError where error.isUnreachable {
      let retryAfter = error.apiError?.retryAfter ?? 0
      await state.unreachable(until: hooks.now().addingTimeInterval(max(30, retryAfter)))
      guard let kept, hooks.now().timeIntervalSince(kept.receivedAt) < options.staleFor else {
        throw error
      }
      report(error)
      return markedStale(try decode(Response(kept)))
    }
  }

  private func entry(_ key: String, in cache: any CacheStore) async -> CacheEntry? {
    do {
      return try await cache.entry(forKey: key)
    } catch {
      report(error)
      return nil
    }
  }

  private func store(_ entry: CacheEntry, key: String, in cache: any CacheStore) async {
    do {
      try await cache.setEntry(
        entry, forKey: key, timeToLive: options.staleFor + (entry.maxAge ?? 0))
    } catch {
      report(error)
    }
  }

  private func previousToken() async -> String? {
    switch credential {
    case .server: return nil
    case .token(let source), .identity(_, let source):
      if let current = await source.current { return current }
      return await source.previous
    }
  }

  func cacheKey(_ request: Request, token: String?) -> String {
    let kind: String
    let secret: String
    switch credential {
    case .server(let key):
      kind = "key"
      secret = key
    case .token:
      kind = "customer-token"
      secret = token ?? ""
    case .identity(let key, _):
      kind = "identity"
      secret = key + "\n" + (token ?? "")
    }
    let parts: [String?] = [
      "entitler-cache-v1", request.method.uppercased(), urlString(for: request), kind,
      sha256(secret),
      options.asOf.map(formatInstant), request.visitor ?? visitor,
    ]
    return sha256("[" + parts.map { $0.map(jsonString) ?? "null" }.joined(separator: ",") + "]")
  }

  func urlString(for request: Request) -> String {
    guard !request.query.isEmpty else { return options.base + request.path }
    return options.base + request.path + "?"
      + request.query.map { "\($0.name.componentEncoded)=\($0.value.componentEncoded)" }
      .joined(separator: "&")
  }

  func url(for request: Request) -> URL { URL(string: urlString(for: request))! }

  func send(_ request: Request, token: String? = nil, ifNoneMatch etag: String? = nil) async throws
    -> Response
  {
    if request.method != "GET", request.changesAnswers, let customer = request.customer {
      await state.bump(customer, at: Hooks.current.now())
    }
    var token = token
    if token == nil, request.authenticated { token = try await currentToken() }
    let hooks = Hooks.current
    let idempotencyKey =
      request.method == "GET" ? nil : request.idempotencyKey ?? UUID().uuidString.lowercased()
    let timeout = request.timeout ?? options.timeout
    var retries = 0
    var refreshed = false
    while true {
      var urlRequest = URLRequest(
        url: url(for: request), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout
      )
      urlRequest.httpMethod = request.method
      urlRequest.httpBody = request.body
      for (name, value) in headers(
        request, token: token, idempotencyKey: idempotencyKey, etag: etag)
      {
        urlRequest.setValue(value, forHTTPHeaderField: name)
      }
      let failure: EntitlerError
      do {
        let (body, http) = try await attempt(
          urlRequest, timeout: timeout, idempotencyKey: idempotencyKey)
        if http.statusCode == 401, !refreshed, let sent = token,
          let fresh = try await refresh(replacing: sent), fresh != sent
        {
          refreshed = true
          token = fresh
          continue
        }
        let response = Response(http, body: body, now: hooks.now())
        if (200..<300).contains(http.statusCode) || (http.statusCode == 304 && etag != nil) {
          if isInApp, let named = try? JSON.decoder().decode(Named.self, from: body) {
            await state.setSignedInID(named.customer)
          }
          return response
        }
        let error = apiError(http, body: body, idempotencyKey: idempotencyKey, now: hooks.now())
        guard [408, 429, 500, 502, 503, 504].contains(http.statusCode), retries < options.maxRetries
        else { throw EntitlerError.api(error) }
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

  private func attempt(_ request: URLRequest, timeout: TimeInterval, idempotencyKey: String?)
    async throws -> (Data, HTTPURLResponse)
  {
    let session = options.session
    let hooks = Hooks.current
    do {
      let answer = try await withThrowingTaskGroup(of: (Data, URLResponse)?.self) { group in
        group.addTask { try await session.data(for: request, delegate: RedirectRefuser.shared) }
        group.addTask {
          try await hooks.deadline(timeout)
          return nil
        }
        defer { group.cancelAll() }
        return try await group.next() ?? nil
      }
      guard let (body, response) = answer else {
        throw EntitlerError.timeout(TimeoutError(timeout: timeout, idempotencyKey: idempotencyKey))
      }
      guard let http = response as? HTTPURLResponse else {
        throw EntitlerError.connection(
          ConnectionError(
            underlyingError: URLError(.badServerResponse), idempotencyKey: idempotencyKey))
      }
      return (body, http)
    } catch let error as EntitlerError {
      throw error
    } catch {
      if Task.isCancelled || error is CancellationError { throw CancellationError() }
      guard let urlError = error as? URLError else {
        throw EntitlerError.connection(
          ConnectionError(underlyingError: URLError(.unknown), idempotencyKey: idempotencyKey))
      }
      if urlError.code == .timedOut {
        throw EntitlerError.timeout(TimeoutError(timeout: timeout, idempotencyKey: idempotencyKey))
      }
      throw EntitlerError.connection(
        ConnectionError(underlyingError: URLError(urlError.code), idempotencyKey: idempotencyKey))
    }
  }

  private func headers(_ request: Request, token: String?, idempotencyKey: String?, etag: String?)
    -> [String: String]
  {
    var headers = ["Accept": "application/json", "User-Agent": userAgent]
    if request.body != nil { headers["Content-Type"] = "application/json" }
    if let idempotencyKey { headers["Idempotency-Key"] = idempotencyKey }
    if let etag { headers["If-None-Match"] = etag }
    guard request.authenticated else { return headers }
    switch credential {
    case .identity(let key, _):
      headers["Authorization"] = "Bearer \(key)"
      headers["Entitler-Identity-Token"] = token
    default:
      if let token { headers["Authorization"] = "Bearer \(token)" }
    }
    if let visitor = request.visitor ?? visitor { headers["Entitler-Visitor"] = visitor }
    if let asOf = options.asOf { headers["Entitler-As-Of"] = formatInstant(asOf) }
    return headers
  }

  private func currentToken() async throws -> String {
    switch credential {
    case .server(let key): key
    case .token(let source), .identity(_, let source):
      try await source.token(now: Hooks.current.now(), timeout: options.timeout)
    }
  }

  private func refresh(replacing token: String) async throws -> String? {
    switch credential {
    case .server: nil
    case .token(let source), .identity(_, let source):
      try await source.refresh(replacing: token, now: Hooks.current.now(), timeout: options.timeout)
    }
  }

  private func apiError(_ http: HTTPURLResponse, body: Data, idempotencyKey: String?, now: Date)
    -> APIError
  {
    let status = http.statusCode
    let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    let detail = (300..<400).contains(status) ? nil : object?["error"] as? [String: Any]
    func text(_ key: String) -> String? {
      (detail?[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
    func items<Item: Decodable>(_ key: String) -> [Item] {
      guard let array = detail?[key] as? [Any],
        let data = try? JSONSerialization.data(withJSONObject: array)
      else { return [] }
      return (try? JSON.decoder().decode([Item].self, from: data)) ?? []
    }
    var payment: Payment?
    if status == 402, let object = detail?["payment"] as? [String: Any],
      let raw = object["status"] as? String, case let paymentStatus = PaymentStatus(rawValue: raw),
      [.declined, .requiresAction, .processing, .pending].contains(paymentStatus)
    {
      payment = Payment(status: paymentStatus, url: object["url"] as? String)
    }
    return APIError(
      status: status,
      code: text("code").map(ErrorCode.init(rawValue:)) ?? .httpError,
      message: text("message") ?? "Entitler answered with HTTP \(status).",
      requestID: http.value(forHTTPHeaderField: "x-request-id"),
      retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap {
        retryAfter($0, now: now)
      },
      idempotencyKey: idempotencyKey,
      payment: payment,
      listingGaps: items("listingGaps"),
      listingProblems: items("listingProblems"))
  }
}

func sha256(_ text: String) -> String {
  sha256(Data(text.utf8))
}

func sha256(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func jsonString(_ text: String) -> String {
  var out = "\""
  for scalar in text.unicodeScalars {
    switch scalar {
    case "\"": out += "\\\""
    case "\\": out += "\\\\"
    case "\n": out += "\\n"
    case "\r": out += "\\r"
    case "\t": out += "\\t"
    case "\u{08}": out += "\\b"
    case "\u{0C}": out += "\\f"
    case let scalar where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
    default: out.unicodeScalars.append(scalar)
    }
  }
  return out + "\""
}

func retryAfter(_ value: String, now: Date) -> TimeInterval? {
  let value = value.trimmingCharacters(in: .whitespaces)
  if !value.isEmpty, value.utf8.allSatisfy({ (0x30...0x39).contains($0) }) {
    return TimeInterval(value) ?? .greatestFiniteMagnitude
  }
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(identifier: "GMT")
  for format in [
    "EEE, dd MMM yyyy HH:mm:ss 'GMT'", "EEEE, dd-MMM-yy HH:mm:ss 'GMT'", "EEE MMM d HH:mm:ss yyyy",
  ] {
    formatter.dateFormat = format
    if let date = formatter.date(from: value.replacingOccurrences(of: "  ", with: " ")) {
      return max(0, date.timeIntervalSince(now))
    }
  }
  return nil
}

extension Response {
  init(_ entry: CacheEntry) {
    self.init(
      status: 200, body: Data(entry.body.utf8), etag: entry.etag, cacheControl: entry.cacheControl,
      age: entry.age, retryAfter: nil)
  }

  init(_ http: HTTPURLResponse, body: Data, now: Date) {
    self.init(
      status: http.statusCode,
      body: body,
      etag: http.value(forHTTPHeaderField: "ETag"),
      cacheControl: http.value(forHTTPHeaderField: "Cache-Control"),
      age: http.value(forHTTPHeaderField: "Age").flatMap { Int($0.trimmed) },
      retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap {
        Entitler.retryAfter($0, now: now)
      },
      requestID: http.value(forHTTPHeaderField: "x-request-id"))
  }
}

let userAgent: String = {
  #if swift(>=6.4)
    let swift = "6.4"
  #elseif swift(>=6.3)
    let swift = "6.3"
  #elseif swift(>=6.2)
    let swift = "6.2"
  #elseif swift(>=6.1)
    let swift = "6.1"
  #else
    let swift = "6.0"
  #endif
  return "entitler-swift/\(entitlerSDKVersion) swift/\(swift)"
}()
