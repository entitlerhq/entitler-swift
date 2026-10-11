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
  /// How long, in seconds, a kept answer may stand in while Entitler is unreachable.
  public var staleFor: TimeInterval
  /// Called with each error a fallback absorbed: a stale answer, an `isEntitled` default (an
  /// ``ArgumentError`` for a blank key included), a hold's failed release or disposal, or a custom
  /// store's own failure. It never changes a call's answer.
  public var onError: (@Sendable (any Error) -> Void)?
  /// The session requests go through, for tests, proxies and instrumentation.
  ///
  /// The SDK refuses redirects and bypasses `URLCache` on every request, an injected session's
  /// included. The default session has no `URLCache`. Closing a client leaves the session open.
  public var session: URLSession

  /// Creates options; each one left out takes its default.
  public init(
    baseURL: URL = URL(string: "https://api.entitler.dev")!,
    timeout: TimeInterval = 10,
    maxRetries: Int = 2,
    maxRetryDelay: TimeInterval = 10,
    staleFor: TimeInterval = 86_400,
    onError: (@Sendable (any Error) -> Void)? = nil,
    session: URLSession = defaultSession
  ) {
    self.baseURL = baseURL
    self.timeout = timeout
    self.maxRetries = maxRetries
    self.maxRetryDelay = maxRetryDelay
    self.staleFor = staleFor
    self.onError = onError
    self.session = session
  }

  var base: String {
    var text = baseURL.absoluteString
    while text.hasSuffix("/") { text.removeLast() }
    return text
  }
}
