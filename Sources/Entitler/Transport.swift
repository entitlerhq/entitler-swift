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
    try await Task.sleep(nanoseconds: nanoseconds(seconds))
  }
  var deadline: @Sendable (TimeInterval) async throws -> Void = { seconds in
    try await Task.sleep(nanoseconds: nanoseconds(seconds))
  }
  var random: @Sendable (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
}

func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
  UInt64(min(max(0, seconds), 1_000_000_000) * 1_000_000_000)
}

func validTimeout(_ timeout: TimeInterval) throws -> TimeInterval {
  guard timeout.isFinite, timeout > 0 else { throw ArgumentError(message: Messages.timeout) }
  return timeout
}

typealias Exchange = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

struct Request: Sendable {
  var method: String
  var path: String
  var query: [(name: String, value: String)] = []
  var timeout: TimeInterval?
  var revalidate = false
}

struct Response: Sendable {
  let status: Int
  let body: Data
  let etag: String?
  let cacheControl: String?
  let age: Int?
  var requestID: String? = nil

  var noStore: Bool { cacheControl?.lowercased().contains("no-store") ?? false }
}

enum OutageAnswer: Sendable {
  case ask
  case serveKept
  case probe
}

actor ClientState {
  private var outageUntil: Date?
  private var lastStamp: Date?
  private var probing = false

  func stamp(_ now: Date) -> Date {
    let next = lastStamp.map { now > $0 ? now : $0.addingTimeInterval(0.000_001) } ?? now
    lastStamp = next
    return next
  }

  func outageAnswer(at now: Date) -> OutageAnswer {
    guard let outageUntil else { return .ask }
    if now < outageUntil || probing { return .serveKept }
    probing = true
    return .probe
  }

  func endProbe() { probing = false }

  func reachable() {
    outageUntil = nil
    probing = false
  }

  func unreachable(until date: Date) {
    outageUntil = max(outageUntil ?? date, date)
    probing = false
  }
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

extension URLSession {
  #if canImport(FoundationNetworking)
    func answer(to request: URLRequest) async throws -> (Data, URLResponse) {
      typealias Waiting = CheckedContinuation<(Data, URLResponse), any Error>
      let pending = LockedValue<(waiting: Waiting?, cancelled: Bool)>((nil, false))
      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          let cancelled = pending.update { state in
            if !state.cancelled { state.waiting = continuation }
            return state.cancelled
          }
          guard !cancelled else { return continuation.resume(throwing: CancellationError()) }
          let task = dataTask(with: request) { body, response, error in
            guard let waiting = pending.update({ $0.waiting.take() }) else { return }
            if let body, let response {
              waiting.resume(returning: (body, response))
            } else {
              waiting.resume(throwing: error ?? URLError(.badServerResponse))
            }
          }
          task.delegate = RedirectRefuser.shared
          task.resume()
        }
      } onCancel: {
        let waiting = pending.update { state in
          state.cancelled = true
          return state.waiting.take()
        }
        guard let waiting else { return }
        DispatchQueue.global().async { waiting.resume(throwing: CancellationError()) }
      }
    }
  #else
    func answer(to request: URLRequest) async throws -> (Data, URLResponse) {
      try await data(for: request, delegate: RedirectRefuser.shared)
    }
  #endif
}

extension Optional {
  fileprivate mutating func take() -> Wrapped? {
    defer { self = nil }
    return self
  }
}

/// The session the SDK uses unless ``EntitlerOptions/session`` names another: no `URLCache`.
@usableFromInline let defaultSession: URLSession = {
  let configuration = URLSessionConfiguration.default
  configuration.urlCache = nil
  configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
  return URLSession(
    configuration: configuration, delegate: RedirectRefuser.shared, delegateQueue: nil)
}()

final class Core: Sendable, CustomReflectable {
  let options: EntitlerOptions
  let cache: (any CacheStore)?
  let key: String
  let exchange: Exchange?
  let hooks: Hooks
  let state = ClientState()
  private let closed = LockedValue(false)
  private let running = LockedValue<[UInt64: @Sendable () -> Void]>([:])
  private let counter = LockedValue<UInt64>(0)

  init(
    options: EntitlerOptions, cache: (any CacheStore)?, key: String, exchange: Exchange? = nil,
    hooks: Hooks = Hooks()
  ) throws {
    _ = try validTimeout(options.timeout)
    self.options = options
    self.cache = cache
    self.key = key
    self.exchange = exchange
    self.hooks = hooks
  }

  func close() {
    guard !closed.swap(true) else { return }
    for cancel in running.swap([:]).values { cancel() }
    if let memory = cache as? MemoryCacheStore { Task { await memory.removeAll() } }
  }

  func checkOpen() throws {
    if closed.read() { throw ClientClosedError() }
  }

  func guarded<Value: Sendable>(_ work: @escaping @Sendable () async throws -> Value)
    async throws -> Value
  {
    try checkOpen()
    let task = Task { try await work() }
    let id = counter.update { value -> UInt64 in
      value += 1
      return value
    }
    running.update { $0[id] = { task.cancel() } }
    if closed.read() { task.cancel() }
    defer { running.update { $0[id] = nil } }
    do {
      return try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
    } catch {
      if closed.read() { throw ClientClosedError() }
      throw error
    }
  }

  var customMirror: Mirror { Mirror(self, children: ["baseURL": options.base]) }

  func report(_ error: any Error) {
    options.onError?(error)
  }

  func cachedCall<Answer: Sendable>(
    _ request: Request, decode: @escaping @Sendable (Data) throws -> Answer
  ) async throws -> Answer {
    _ = try request.timeout.map(validTimeout)
    guard let cache else {
      return try await guarded { [self] in try decoded(await send(request), decode) }
    }
    return try await guarded { [self] in
      try await cachedAnswer(request, cache: cache, decode: decode)
    }
  }

  private func decoded<Answer>(_ response: Response, _ decode: (Data) throws -> Answer) throws
    -> Answer
  {
    do {
      return try decode(response.body)
    } catch {
      var failure = APIError(
        status: response.status, code: grpcCode(status: 500), reason: .responseInvalid,
        parameters: [:], requestID: response.requestID, retryAfter: nil, idempotencyKey: nil)
      failure.underlyingError = error
      throw EntitlerError.api(failure)
    }
  }

  private func cachedAnswer<Answer>(
    _ request: Request, cache: any CacheStore, decode: (Data) throws -> Answer
  ) async throws -> Answer {
    let key = cacheKey(request)
    let kept = await entry(key, in: cache)
    if !request.revalidate, let kept, kept.isFresh(at: hooks.now()) {
      return try decoded(Response(kept), decode)
    }
    var outage = OutageAnswer.ask
    if let kept, hooks.now().timeIntervalSince(kept.receivedAt) < options.staleFor {
      outage = await state.outageAnswer(at: hooks.now())
      if outage == .serveKept { return markedStale(try decoded(Response(kept), decode)) }
    }
    do {
      let answer = try await askAPI(request, key: key, kept: kept, cache: cache, decode: decode)
      if outage == .probe { await state.endProbe() }
      return answer
    } catch {
      if outage == .probe { await state.endProbe() }
      throw error
    }
  }

  private func askAPI<Answer>(
    _ request: Request, key: String, kept: CacheEntry?, cache: any CacheStore,
    decode: (Data) throws -> Answer
  ) async throws -> Answer {
    do {
      let response = try await send(request, ifNoneMatch: kept?.etag)
      let receivedAt = await state.stamp(hooks.now())
      var entry: CacheEntry?
      if response.status == 304, let kept {
        entry = CacheEntry(
          body: kept.body, etag: response.etag ?? kept.etag,
          cacheControl: response.cacheControl ?? kept.cacheControl, age: response.age ?? kept.age,
          receivedAt: receivedAt)
      } else if !response.noStore,
        response.etag != nil || response.cacheControl?.lowercased().contains("max-age") == true
      {
        entry = CacheEntry(
          body: String(decoding: response.body, as: UTF8.self), etag: response.etag,
          cacheControl: response.cacheControl, age: response.age, receivedAt: receivedAt)
      }
      let answer = try decoded(
        response.status == 304 ? entry.map(Response.init) ?? response : response, decode)
      if let entry { await store(entry, key: key, in: cache) }
      return answer
    } catch let error as EntitlerError where error.isUnreachable {
      let retryAfter = error.apiError?.retryAfter ?? 0
      let window = min(max(30, retryAfter), options.staleFor, 86_400 * 365)
      await state.unreachable(until: hooks.now().addingTimeInterval(window))
      guard let kept, hooks.now().timeIntervalSince(kept.receivedAt) < options.staleFor else {
        throw error
      }
      report(error)
      return markedStale(try decoded(Response(kept), decode))
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

  func cacheKey(_ request: Request) -> String {
    let parts = ["entitler-cache-v2", request.method, urlString(for: request), "key", sha256(key)]
    return sha256("[" + parts.map(jsonString).joined(separator: ",") + "]")
  }

  func urlString(for request: Request) -> String {
    guard !request.query.isEmpty else { return options.base + request.path }
    return options.base + request.path + "?"
      + request.query.map { "\($0.name.componentEncoded)=\($0.value.componentEncoded)" }
      .joined(separator: "&")
  }

  func send(_ request: Request, ifNoneMatch etag: String? = nil) async throws -> Response {
    let timeout = try validTimeout(request.timeout ?? options.timeout)
    let url = URL(string: urlString(for: request))!
    var retries = 0
    while true {
      var urlRequest = URLRequest(
        url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
      urlRequest.httpMethod = request.method
      for (name, value) in headers(etag: etag) {
        urlRequest.setValue(value, forHTTPHeaderField: name)
      }
      let failure: EntitlerError
      do {
        let (body, http) = try await attempt(urlRequest, timeout: timeout)
        let response = Response(http, body: body)
        if (200..<300).contains(http.statusCode) || (http.statusCode == 304 && etag != nil) {
          await state.reachable()
          return response
        }
        let error = apiError(http, body: body, now: hooks.now())
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

  private func attempt(_ request: URLRequest, timeout: TimeInterval) async throws -> (
    Data, HTTPURLResponse
  ) {
    let session = options.session
    let exchange = exchange
    let hooks = hooks
    do {
      let answer = try await withThrowingTaskGroup(of: (Data, URLResponse)?.self) { group in
        group.addTask {
          if let exchange { return try await exchange(request) }
          return try await session.answer(to: request)
        }
        group.addTask {
          try await hooks.deadline(timeout)
          return nil
        }
        defer { group.cancelAll() }
        return try await group.next() ?? nil
      }
      guard let (body, response) = answer else {
        throw EntitlerError.timeout(TimeoutError(timeout: timeout, idempotencyKey: nil))
      }
      guard let http = response as? HTTPURLResponse else {
        throw EntitlerError.connection(
          ConnectionError(underlyingError: URLError(.badServerResponse), idempotencyKey: nil))
      }
      return (body, http)
    } catch let error as EntitlerError {
      throw error
    } catch {
      if Task.isCancelled || error is CancellationError { throw CancellationError() }
      guard let urlError = error as? URLError else {
        throw EntitlerError.connection(
          ConnectionError(underlyingError: URLError(.unknown), idempotencyKey: nil))
      }
      if urlError.code == .timedOut {
        throw EntitlerError.timeout(TimeoutError(timeout: timeout, idempotencyKey: nil))
      }
      throw EntitlerError.connection(
        ConnectionError(underlyingError: URLError(urlError.code), idempotencyKey: nil))
    }
  }

  private func headers(etag: String?) -> [String: String] {
    var headers = [
      "Accept": "application/json", "User-Agent": userAgent, "Authorization": "Bearer \(key)",
    ]
    if let etag { headers["If-None-Match"] = etag }
    return headers
  }

  private func apiError(_ http: HTTPURLResponse, body: Data, now: Date) -> APIError {
    let status = http.statusCode
    let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    let detail = object?["error"] as? [String: Any]
    let code = (detail?["code"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    let reason = (detail?["reason"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    return APIError(
      status: status,
      code: code ?? grpcCode(status: status),
      reason: reason.map(Reason.init(rawValue:)),
      parameters: detail?["parameters"] as? [String: String] ?? [:],
      requestID: http.value(forHTTPHeaderField: "x-request-id"),
      retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap {
        retryAfterSeconds($0, now: now)
      },
      idempotencyKey: nil)
  }
}

func sha256(_ text: String) -> String {
  SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
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
    case let scalar where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
    default: out.unicodeScalars.append(scalar)
    }
  }
  return out + "\""
}

func retryAfterSeconds(_ value: String, now: Date) -> TimeInterval? {
  let value = value.trimmingCharacters(in: .whitespaces)
  if let seconds = headerNumber(value) { return TimeInterval(seconds) }
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(identifier: "GMT")
  formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
  return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
}

extension Response {
  init(_ entry: CacheEntry) {
    self.init(
      status: 200, body: Data(entry.body.utf8), etag: entry.etag, cacheControl: entry.cacheControl,
      age: entry.age)
  }

  init(_ http: HTTPURLResponse, body: Data) {
    self.init(
      status: http.statusCode,
      body: body,
      etag: http.value(forHTTPHeaderField: "ETag"),
      cacheControl: http.value(forHTTPHeaderField: "Cache-Control"),
      age: http.value(forHTTPHeaderField: "Age").flatMap(headerNumber),
      requestID: http.value(forHTTPHeaderField: "x-request-id"))
  }
}

let userAgent = "entitler-swift/\(entitlerSDKVersion)"
