import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Options both clients take.
///
/// ```swift
/// let server = try EntitlerServer(key: key, options: EntitlerOptions(timeout: 5))
/// ```
public struct EntitlerOptions: Sendable {
  /// The API's address. Trailing slashes are removed.
  public var baseURL: URL
  /// How long each attempt may take, in seconds, from connecting to the last byte.
  public var timeout: TimeInterval
  /// How many times to retry after the first attempt.
  public var maxRetries: Int
  /// The longest `Retry-After`, in seconds, the SDK waits for before retrying.
  public var maxRetryDelay: TimeInterval
  /// The answer cache, or `nil` to turn caching off.
  public var cache: (any CacheStore)?
  /// How long, in seconds, a kept answer may stand in while Entitler is unreachable.
  public var staleFor: TimeInterval
  /// Called with each error a fallback absorbed: a stale answer, or an `isEntitled` default.
  public var onError: (@Sendable (EntitlerError) -> Void)?
  /// Read the API at another instant. Needs the organisation's `as_of` capability.
  public var asOf: Date?
  /// The session requests go through, for tests, proxies and instrumentation.
  public var session: URLSession

  /// Creates options; each one left out takes its default.
  public init(
    baseURL: URL = URL(string: "https://api.entitler.dev")!,
    timeout: TimeInterval = 10,
    maxRetries: Int = 2,
    maxRetryDelay: TimeInterval = 10,
    cache: (any CacheStore)? = MemoryCacheStore(capacity: 1_000),
    staleFor: TimeInterval = 86_400,
    onError: (@Sendable (EntitlerError) -> Void)? = nil,
    asOf: Date? = nil,
    session: URLSession = .shared
  ) {
    self.baseURL = baseURL
    self.timeout = timeout
    self.maxRetries = maxRetries
    self.maxRetryDelay = maxRetryDelay
    self.cache = cache
    self.staleFor = staleFor
    self.onError = onError
    self.asOf = asOf
    self.session = session
  }

  var base: String {
    var text = baseURL.absoluteString
    while text.hasSuffix("/") { text.removeLast() }
    return text
  }

  func validated() throws -> EntitlerOptions {
    if let asOf, !asOf.timeIntervalSince1970.isFinite {
      throw ArgumentError(message: Messages.asOf)
    }
    return self
  }
}
