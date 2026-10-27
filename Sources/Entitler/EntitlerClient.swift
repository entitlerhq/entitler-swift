import Foundation

/// Answers a fresh token, such as one your server minted for the signed-in customer. The client
/// calls it when it has no token, and once more when Entitler refuses the one it has. Concurrent
/// calls share one pending request.
public typealias TokenProvider = @Sendable () async throws -> String

/// How an in-app client signs in, extensible: a kind this SDK does not list is kept as it is.
public struct ClientKind: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
  /// The kind as the SDK spells it, such as `token`.
  public let rawValue: String

  /// Creates a kind from its spelling.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// The kind's spelling.
  public var description: String { rawValue }

  /// A customer token your server minted.
  public static let token = ClientKind(rawValue: "token")
  /// A publishable key and your sign-in provider's identity token.
  public static let identity = ClientKind(rawValue: "identity")
}

/// The signed-in customer of an ``EntitlerClient``, on the `/v1/customers/me` routes.
public struct SignedInCustomer: Customer, CustomStringConvertible, CustomReflectable {
  /// `me`.
  public let id = "me"
  /// The client this customer acts through. Opaque.
  public let handle: CustomerHandle

  /// `SignedInCustomer(me)`.
  public var description: String { "SignedInCustomer(me)" }

  /// No credential.
  public var customMirror: Mirror { Mirror(self, children: ["id": id]) }
}

/// The in-app client for iOS, macOS and other apps, for one signed-in customer. Build it with a
/// customer token from your server or a provider for one, or with a publishable key and your
/// sign-in provider's identity token. Keep one per signed-in customer, and close it at sign-out.
///
/// ```swift
/// let entitler = try EntitlerClient(tokenProvider: { try await api.entitlerToken() })
/// if await entitler.me.isEntitled(to: "export_pdf", default: false) { showExport() }
/// ```
///
/// Answers are kept in memory only, since they belong to one signed-in customer.
public final class EntitlerClient: Sendable, CustomStringConvertible, CustomReflectable {
  /// How the client signs in.
  public let kind: ClientKind
  /// The signed-in customer.
  public let me: SignedInCustomer
  let core: Core

  /// Creates a client from a customer token your server minted. When Entitler refuses it, calls
  /// fail; use ``init(tokenProvider:cache:options:)`` to fetch a fresh one instead.
  ///
  /// - Throws: ``ArgumentError`` for a blank token.
  public convenience init(
    token: String, cache: MemoryCacheStore? = MemoryCacheStore(capacity: 1_000),
    options: EntitlerOptions = EntitlerOptions()
  ) throws {
    let token = try requireCredential(token, Messages.customerToken)
    try self.init(kind: .token, cache: cache, options: options, exchange: nil, hooks: Hooks()) {
      _, _ in Credentials(authorise: { signed(token, key: nil) })
    }
  }

  /// Creates a client that asks `tokenProvider` for a customer token from your server.
  public convenience init(
    tokenProvider: @escaping TokenProvider,
    cache: MemoryCacheStore? = MemoryCacheStore(capacity: 1_000),
    options: EntitlerOptions = EntitlerOptions()
  ) throws {
    try self.init(
      kind: .token, cache: cache, options: options, exchange: nil, hooks: Hooks(),
      credentials: provided(tokenProvider, key: nil))
  }

  /// Creates a client from a publishable key and your sign-in provider's identity token.
  ///
  /// - Throws: ``ArgumentError`` for a blank key or token.
  public convenience init(
    key: String, identityToken: String,
    cache: MemoryCacheStore? = MemoryCacheStore(capacity: 1_000),
    options: EntitlerOptions = EntitlerOptions()
  ) throws {
    let key = try requireCredential(key, Messages.publishableKey)
    let token = try requireCredential(identityToken, Messages.identityToken)
    try self.init(kind: .identity, cache: cache, options: options, exchange: nil, hooks: Hooks()) {
      _, _ in Credentials(authorise: { signed(token, key: key) })
    }
  }

  /// Creates a client from a publishable key, asking `identityTokenProvider` for your sign-in
  /// provider's current identity token.
  ///
  /// ```swift
  /// let entitler = try EntitlerClient(
  ///   key: publishableKey, identityTokenProvider: { try await signIn.currentIDToken() })
  /// try await entitler.register()
  /// ```
  ///
  /// - Throws: ``ArgumentError`` for a blank key.
  public convenience init(
    key: String, identityTokenProvider: @escaping TokenProvider,
    cache: MemoryCacheStore? = MemoryCacheStore(capacity: 1_000),
    options: EntitlerOptions = EntitlerOptions()
  ) throws {
    let key = try requireCredential(key, Messages.publishableKey)
    try self.init(
      kind: .identity, cache: cache, options: options, exchange: nil, hooks: Hooks(),
      credentials: provided(identityTokenProvider, key: key))
  }

  init(
    kind: ClientKind, cache: MemoryCacheStore?, options: EntitlerOptions, exchange: Exchange?,
    hooks: Hooks, credentials: (Hooks, TimeInterval) -> Credentials
  ) throws {
    self.kind = kind
    core = try Core(
      options: options, cache: cache, credentials: credentials(hooks, options.timeout),
      exchange: exchange, hooks: hooks)
    me = SignedInCustomer(handle: CustomerHandle(core: core))
  }

  /// Registers the signed-in person as a customer. Call it after each sign-in: a customer
  /// registered already is answered as they are. Entitler answers `PermissionDenied` when the
  /// sign-in provider doesn't let people register themselves.
  @discardableResult
  public func register(timeout: TimeInterval? = nil) async throws -> RegisteredCustomer {
    var request = try Wire.customersRegisterCustomer.request(["customer.external_id": me.id])
    request.body = Data("{}".utf8)
    request.timeout = timeout
    return try await core.call(request, decode: decodeRegistered).answer
  }

  /// Closes the client at sign-out: cancels every call in flight and the pending token request,
  /// drops the in-memory cache, and makes every later call throw ``ClientClosedError``. Closing
  /// twice is safe.
  public func close() { core.close() }

  /// Shows the base URL and the kind, never the credential.
  public var description: String { "EntitlerClient(\(kind), \(core.options.base))" }

  /// Shows the base URL and the kind, never the credential.
  public var customMirror: Mirror {
    Mirror(self, children: ["baseURL": core.options.base, "kind": kind])
  }
}

func provided(_ provider: @escaping TokenProvider, key: String?)
  -> (Hooks, TimeInterval) -> Credentials
{
  { hooks, timeout in
    let source = TokenSource(provider: provider, hooks: hooks)
    return Credentials(
      authorise: { signed(try await source.get(timeout: timeout), key: key) },
      refuse: { used in await source.refuse(used.token) },
      cancel: { Task { await source.cancel() } })
  }
}

func signed(_ token: String, key: String?) -> Authorised {
  guard let key else {
    return Authorised(
      headers: ["Authorization": "Bearer \(token)"], credential: token, token: token)
  }
  return Authorised(
    headers: ["Authorization": "Bearer \(key)", "Entitler-Identity-Token": token],
    credential: key + "\n" + token, token: token)
}

actor TokenSource {
  private let provider: TokenProvider
  private let hooks: Hooks
  private var current: String?
  private var refused: Set<String> = []
  private var pending: Task<String, any Error>?

  init(provider: @escaping TokenProvider, hooks: Hooks) {
    self.provider = provider
    self.hooks = hooks
  }

  func get(timeout: TimeInterval) async throws -> String {
    if let current { return current }
    let task = pending ?? ask(timeout: timeout)
    pending = task
    defer { if pending == task { pending = nil } }
    let token = try await task.value
    guard !refused.contains(token) else {
      throw EntitlerError.token(
        TokenError(message: Messages.tokenRefused, underlyingError: nil))
    }
    current = token
    return token
  }

  func refuse(_ token: String) {
    refused.insert(token)
    if current == token { current = nil }
  }

  func cancel() {
    pending?.cancel()
    pending = nil
  }

  private func ask(timeout: TimeInterval) -> Task<String, any Error> {
    let provider = provider
    let hooks = hooks
    return Task {
      let answer: String?
      do {
        answer = try await withThrowingTaskGroup(of: String?.self) { group in
          group.addTask { try await provider() }
          group.addTask {
            try await hooks.deadline(timeout)
            return nil
          }
          defer { group.cancelAll() }
          return try await group.next() ?? nil
        }
      } catch {
        if Task.isCancelled { throw CancellationError() }
        throw EntitlerError.token(
          TokenError(message: Messages.tokenFailed, underlyingError: error))
      }
      guard let answer else {
        throw EntitlerError.token(
          TokenError(
            message: "The token provider did not answer within \(timeout.formatted()) seconds.",
            underlyingError: nil))
      }
      let token = answer.trimmed
      guard !token.isEmpty, token.isHeaderSafe else {
        throw EntitlerError.token(TokenError(message: Messages.tokenBlank, underlyingError: nil))
      }
      return token
    }
  }
}
