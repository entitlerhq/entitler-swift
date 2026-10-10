import Foundation

/// The server client: built from a secret key, it acts on any customer.
///
/// ```swift
/// let server = try EntitlerServer(key: ProcessInfo.processInfo.environment["ENTITLER_KEY"] ?? "")
/// let customer = try server.customer("user_123")
/// try await customer.register(name: "Ada Lovelace", email: "ada@example.com")
/// if await customer.isEntitled(to: Features.exportPDF, default: false) { … }
/// ```
///
/// Keep the secret key on your servers. Apps use ``EntitlerClient`` instead.
public final class EntitlerServer: Sendable, CustomStringConvertible, CustomReflectable {
  let core: Core

  /// Creates a server client.
  ///
  /// - Parameters:
  ///   - key: A secret project key from the dashboard. A publishable key (`ent_pk_…`) belongs in
  ///     ``EntitlerClient`` and is refused here.
  ///   - cache: Where answers are kept: by default 1,000 in memory, least recently used out first;
  ///     a store of your own, such as Redis, to share answers between servers; or `nil` for none.
  ///   - options: Timeouts, retries, stale answers and the rest.
  /// - Throws: ``ArgumentError`` when the key is blank or publishable.
  public init(
    key: String, cache: (any CacheStore)? = MemoryCacheStore(capacity: 1_000),
    options: EntitlerOptions = EntitlerOptions()
  ) throws {
    let key = try requireCredential(key, Messages.key)
    guard !key.hasPrefix("ent_pk_") else {
      throw ArgumentError(message: Messages.publishableOnServer)
    }
    core = Core(options: options, cache: cache, credential: .server(key: key), visitor: nil)
  }

  package init(
    key: String, cache: (any CacheStore)?, options: EntitlerOptions, exchange: @escaping Exchange
  ) {
    core = Core(
      options: options, cache: cache, credential: .server(key: key), visitor: nil,
      exchange: exchange)
  }

  /// The base URL and the kind of client, never the key.
  public var description: String { "EntitlerServer(\(core.options.base))" }

  /// The base URL and the kind of client, never the key.
  public var customMirror: Mirror { core.customMirror }

  /// Closes the client: calls in flight and every later call fail with ``ClientClosedError``, and
  /// the in-memory cache is dropped. A store of your own, and an injected session, are left as
  /// they are. Closing twice is safe.
  public func close() { core.close() }

  /// A customer by the id your app uses for them. Makes no request.
  ///
  /// - Throws: ``ArgumentError`` when the id is blank.
  public func customer(_ id: String) throws -> ServerCustomer {
    ServerCustomer(id: try require(id, Messages.customerID), core: core)
  }

  /// Lists and creates customers.
  public var customers: Customers { Customers(core: core) }

  /// Records usage events of any customers, in observe mode, in requests of at most 500 events.
  ///
  /// ```swift
  /// let result = try await server.recordUsageBatch([
  ///   UsageBatchEvent(customer: "user_123", feature: Features.aiCredits, amount: 20,
  ///     idempotencyKey: "job-42:user_123"),
  /// ])
  /// ```
  ///
  /// It never throws for an event or a request: an event the SDK refuses itself is answered
  /// ``UsageEventOutcome/error`` without being sent, and so is every event of a request that fails
  /// after its retries, while the other requests still go. Resend the events answered `error`:
  /// their keys make any resend safe. Each request's `Idempotency-Key` derives from its events, so
  /// the same events always send the same key and replay the first answer.
  ///
  /// - Parameters:
  ///   - events: The events; an input with nothing to send sends nothing.
  ///   - register: Registers customers not registered yet, if the key may.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  /// - Returns: One result per event, in input order, and the totals.
  /// - Throws: Only `CancellationError`, and ``ClientClosedError`` once the client is closed.
  public func recordUsageBatch(
    _ events: [UsageBatchEvent], register: Bool = false, timeout: TimeInterval? = nil
  ) async throws -> UsageBatchResult {
    struct Event: Encodable {
      var customer: String
      var feature: String
      var amount: Int64
      var occurredAt: Date?
      var idempotencyKey: String
    }
    struct Body: Encodable {
      var register: Bool?
      var events: [Event]
    }
    struct Answer: Decodable, Sendable, Replaying {
      struct Result: Decodable, Sendable {
        let index: Int
        let outcome: UsageEventOutcome
        let id: String?
        let late: Bool
        let error: UsageEventError?
      }
      let results: [Result]
      var replayed = false

      enum CodingKeys: String, CodingKey { case results }
    }
    try core.checkOpen()
    var results: [UsageEventResult] = []
    var prepared: [(index: Int, event: Event)] = []
    for (index, event) in events.enumerated() {
      do {
        prepared.append(
          (
            index,
            Event(
              customer: try UsageBatchEvent.check(
                event.customer, .invalidBody, Messages.customerID),
              feature: try UsageBatchEvent.check(event.feature.key, .invalidBody, Messages.feature),
              amount: try UsageBatchEvent.amount(event.amount), occurredAt: event.occurredAt,
              idempotencyKey: try UsageBatchEvent.key(event.idempotencyKey))
          ))
      } catch let error as UsageEventError {
        results.append(
          UsageEventResult(
            index: index, outcome: .error, id: nil, late: false, error: error,
            idempotencyKey: event.idempotencyKey, replayed: false))
      }
    }
    for start in stride(from: 0, to: prepared.count, by: 500) {
      let chunk = Array(prepared[start..<min(start + 500, prepared.count)])
      var request = try Request(
        "POST", ["usage", "events"],
        body: Body(register: register ? true : nil, events: chunk.map(\.event)))
      request.timeout = timeout
      request.idempotencyKey = batchKey(chunk.map(\.event), register: register) {
        [$0.customer, $0.feature, $0.amount, $0.occurredAt, $0.idempotencyKey]
      }
      for customer in Set(chunk.map(\.event.customer)) {
        await core.state.bump(customer, at: Hooks.current.now())
      }
      do {
        let answer: Answer = try await core.call(request)
        for result in answer.results where chunk.indices.contains(result.index) {
          let sent = chunk[result.index]
          results.append(
            UsageEventResult(
              index: sent.index, outcome: result.outcome, id: result.id, late: result.late,
              error: result.error, idempotencyKey: sent.event.idempotencyKey,
              replayed: answer.replayed))
        }
      } catch let error as EntitlerError {
        let failure: UsageEventError =
          switch error {
          case .api(let error): UsageEventError(code: error.code, message: error.message)
          case .timeout(let error): UsageEventError(code: .timedOut, message: error.message)
          default: UsageEventError(code: .connectionFailed, message: error.description)
          }
        results += chunk.map { sent in
          UsageEventResult(
            index: sent.index, outcome: .error, id: nil, late: false, error: failure,
            idempotencyKey: sent.event.idempotencyKey, replayed: false)
        }
      }
    }
    results.sort { $0.index < $1.index }
    return UsageBatchResult(
      results: results,
      recorded: results.filter { $0.outcome == .recorded }.count,
      duplicates: results.filter { $0.outcome == .duplicate }.count,
      errors: results.filter { $0.outcome == .error }.count)
  }

  /// The plans on sale to a signed-out visitor, for a pricing page, through the cache.
  ///
  /// - Parameters:
  ///   - visitor: The visitor's id from ``newVisitorID()``, kept in a first-party cookie, so
  ///     they see the same experiment arm on every page.
  ///   - revalidate: Asks Entitler again even when a kept answer is still fresh.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  public func pricing(
    visitor: String? = nil, revalidate: Bool = false, timeout: TimeInterval? = nil
  )
    async throws -> Pricing
  {
    var request = try Request("GET", ["pricing"])
    request.visitor = try validVisitor(visitor)
    request.revalidate = revalidate
    request.timeout = timeout
    return try await core.cachedCall(request)
  }

  /// The features of the catalogue the All customers track serves, through the cache.
  public func features(revalidate: Bool = false, timeout: TimeInterval? = nil) async throws
    -> FeatureList
  {
    var request = try Request("GET", ["pricing", "features"])
    request.revalidate = revalidate
    request.timeout = timeout
    return try await core.cachedCall(request)
  }

  /// The scopes the key holds, for deciding which controls to show. Each call asks again.
  public func scopes(timeout: TimeInterval? = nil) async throws -> CredentialScopes {
    try await core.scopes(timeout: timeout)
  }

  /// The public keys that verify snapshots. Needs no credential.
  public func snapshotKeys(timeout: TimeInterval? = nil) async throws -> SnapshotKeys {
    try await core.snapshotKeys(timeout: timeout)
  }

  /// Verifies an offline snapshot; the same as ``verifySnapshot(_:expecting:)``.
  public func verifySnapshot(_ token: String, expecting expected: SnapshotExpectation) throws
    -> VerifiedSnapshot
  {
    try Entitler.verifySnapshot(token, expecting: expected)
  }

  /// A new visitor id for the app to keep; the same as ``Entitler/newVisitorID()``.
  public func newVisitorID() -> String { Entitler.newVisitorID() }
}

func batchKey<Event>(
  _ events: [Event], register: Bool, fields: (Event) -> [(any Sendable)?]
) -> String {
  func json(_ value: (any Sendable)?) -> String {
    switch value {
    case let text as String: jsonString(text)
    case let number as Int64: String(number)
    case let date as Date: jsonString(formatInstant(date))
    default: "null"
    }
  }
  let rows = events.map { "[" + fields($0).map(json).joined(separator: ",") + "]" }
  return "batch:"
    + sha256(
      "[\"entitler-batch-v1\",\(register),[" + rows.joined(separator: ",") + "]]")
}

/// One usage event of a batch.
public struct UsageBatchEvent: Hashable, Sendable {
  /// The customer's external id.
  public var customer: String
  /// The metered feature.
  public var feature: Feature<Metered>
  /// The amount, from 1 to 2^53 − 1.
  public var amount: Int64
  /// When the usage happened.
  public var occurredAt: Date?
  /// A key from your own unit of work, such as a job id plus the customer's id.
  public var idempotencyKey: String

  /// Creates an event.
  public init(
    customer: String, feature: Feature<Metered>, amount: Int64, occurredAt: Date? = nil,
    idempotencyKey: String
  ) {
    self.customer = customer
    self.feature = feature
    self.amount = amount
    self.occurredAt = occurredAt
    self.idempotencyKey = idempotencyKey
  }

  static func check(_ value: String, _ code: ErrorCode, _ message: String) throws -> String {
    guard !value.trimmed.isEmpty else { throw UsageEventError(code: code, message: message) }
    return value
  }

  static func amount(_ amount: Int64) throws -> Int64 {
    guard (1...maxAmount).contains(amount) else {
      throw UsageEventError(code: .invalidAmount, message: Messages.amount)
    }
    return amount
  }

  static func key(_ key: String) throws -> String {
    do {
      return try validIdempotencyKey(key) ?? key
    } catch let error as ArgumentError {
      throw UsageEventError(code: .invalidIdempotencyKey, message: error.message)
    }
  }
}

/// The server's customer list: ``EntitlerServer/customers``.
public struct Customers: Sendable {
  let core: Core

  /// Every customer of the environment, each page requested only when iteration reaches it.
  ///
  /// ```swift
  /// for try await customer in server.customers.list(query: "acme") {
  ///   print(customer.externalID)
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - query: Text to find in the external id, name or email.
  ///   - cohort: Only the customers holding a cohort, as `<plan key or id>:<n>`.
  ///   - track: Only one track's members, by its id.
  ///   - includeTest: In a live environment, also the test customers.
  ///   - cursor: A page's ``Page/next``, to start the iteration at that page, so a stateless admin
  ///     page can link to page 3.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  public func list(
    query: String? = nil, cohort: String? = nil, track: String? = nil, includeTest: Bool = false,
    cursor: String? = nil, timeout: TimeInterval? = nil
  ) -> PagedList<CustomerSummary> {
    let core = core
    let options =
      [
        ("q", query), ("cohort", cohort), ("track", track),
        ("includeTest", includeTest ? "true" : nil),
      ]
      .compactMap { name, value in value.map { (name: name, value: $0) } }
    var list = PagedList<CustomerSummary> { cursor in
      var request = try Request("GET", ["customers"])
      request.query = options + (cursor.map { [("cursor", $0)] } ?? [])
      request.timeout = timeout
      return try await core.call(request)
    }
    list.start = cursor
    return list
  }

  /// Creates a customer with an external id and a name, on the plan given or the default plan.
  @discardableResult
  public func create(
    id: String, name: String, email: String? = nil, plan: String? = nil, period: String? = nil,
    metadata: [String: String]? = nil, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> CustomerDetail {
    struct Body: Encodable {
      var externalId: String
      var name: String
      var email: String?
      var plan: String?
      var period: String?
      var metadata: [String: String]?
    }
    var request = try Request(
      "POST", ["customers"],
      body: Body(
        externalId: require(id, Messages.customerID), name: name, email: email, plan: plan,
        period: period, metadata: metadata))
    request.idempotencyKey = try validIdempotencyKey(idempotencyKey)
    request.timeout = timeout
    request.customer = id
    return try await core.call(request)
  }
}

/// The kind of credential an ``EntitlerClient`` holds.
public protocol ClientCredential: Sendable {}

/// A credential that names a signed-in customer: a customer token or an identity token.
public protocol SignedInCredential: ClientCredential {}

/// A customer token minted by your server: ``EntitlerClient/init(token:visitor:cache:options:)``.
public enum TokenCredential: SignedInCredential {}

/// A publishable key and an identity token from your sign-in provider:
/// ``EntitlerClient/init(key:identityToken:visitor:cache:options:)``.
public enum IdentityCredential: SignedInCredential {}

/// A publishable key alone, for a signed-out paywall or pricing page:
/// ``EntitlerClient/init(key:visitor:cache:options:)``.
public enum PublishableCredential: ClientCredential {}

/// The in-app client, for apps on phones, desktops and the web: it acts on the signed-in
/// customer only, ``me``, or with a publishable key alone reads signed-out ``pricing(visitor:revalidate:timeout:)``.
///
/// ```swift
/// let client = try EntitlerClient(tokenProvider: { try await api.entitlerToken() })
/// let canExport = await client.me.isEntitled(to: Features.exportPDF, default: false)
/// ```
///
/// It never takes a secret key: anything shipped in an app can be read out of it. It takes a
/// customer token your server mints for one customer, or a publishable key (`ent_pk_…`) holding
/// only product scopes, with or without an identity token from your sign-in provider.
///
/// Create one client when a person signs in, keep it where the app keeps state for the session
/// (not in one screen's view model), and ``close()`` it when they sign out, so nothing kept for
/// one person is ever answered to another.
public final class EntitlerClient<Credential: ClientCredential>: Sendable, CustomStringConvertible,
  CustomReflectable
{
  let core: Core

  init(
    credential: Entitler.Credential, visitor: String?, cache: MemoryCacheStore?,
    options: EntitlerOptions
  ) throws {
    core = Core(
      options: options, cache: cache, credential: credential,
      visitor: try validVisitor(visitor) ?? storedVisitor())
  }

  /// The visitor id sent on every request, so an experiment's arm stays the same before and after
  /// registration.
  public var visitor: String { core.visitor ?? "" }

  /// The base URL and the kind of client, never the credential.
  public var description: String { "EntitlerClient(\(core.kind), \(core.options.base))" }

  /// The base URL and the kind of client, never the credential.
  public var customMirror: Mirror { core.customMirror }

  /// Closes the client, for example at sign-out: calls in flight, the pending token refresh and
  /// every later call fail with ``ClientClosedError``, and the in-memory cache is dropped. Closing
  /// twice is safe. It returns at once, so call it from anywhere.
  public func close() { core.close() }

  /// The public keys that verify snapshots. Needs no credential.
  public func snapshotKeys(timeout: TimeInterval? = nil) async throws -> SnapshotKeys {
    try await core.snapshotKeys(timeout: timeout)
  }

  /// Verifies an offline snapshot; the same as ``verifySnapshot(_:expecting:)``.
  public func verifySnapshot(_ token: String, expecting expected: SnapshotExpectation) throws
    -> VerifiedSnapshot
  {
    try Entitler.verifySnapshot(token, expecting: expected)
  }
}

extension EntitlerClient where Credential: SignedInCredential {
  /// The signed-in customer. Makes no request.
  public var me: SignedInCustomer {
    SignedInCustomer(handle: CustomerHandle(core: core, path: "me"))
  }

  /// The scopes the credential holds, for deciding which controls to show. Each call asks again.
  public func scopes(timeout: TimeInterval? = nil) async throws -> CredentialScopes {
    try await core.scopes(timeout: timeout)
  }
}

extension EntitlerClient where Credential == TokenCredential {
  /// Creates a client from a customer token. A fixed token cannot be refreshed, so a `401` fails.
  ///
  /// - Parameters:
  ///   - token: A customer token your server minted with ``ServerCustomer/token(scopes:ttlSeconds:timeout:)``.
  ///   - visitor: A visitor id to use instead of the one the client keeps.
  ///   - cache: The in-memory cache: by default 1,000 answers, or `nil` for none.
  ///   - options: Timeouts, retries, stale answers and the rest.
  public convenience init(
    token: String, visitor: String? = nil,
    cache: MemoryCacheStore? = MemoryCacheStore(capacity: 1_000),
    options: EntitlerOptions = EntitlerOptions()
  ) throws {
    let token = try requireCredential(token, Messages.customerToken)
    try self.init(
      credential: .token(TokenSource(fixed: token)), visitor: visitor, cache: cache,
      options: options)
  }

  /// Creates a client that asks your server for customer tokens, before the first request, before
  /// the kept one expires, and after a `401`.
  public convenience init(
    tokenProvider: @escaping TokenProvider, visitor: String? = nil,
    cache: MemoryCacheStore? = MemoryCacheStore(capacity: 1_000),
    options: EntitlerOptions = EntitlerOptions()
  ) throws {
    try self.init(
      credential: .token(
        TokenSource(provider: tokenProvider, blankMessage: Messages.customerToken)),
      visitor: visitor, cache: cache, options: options)
  }
}

extension EntitlerClient where Credential == IdentityCredential {
  /// Creates a client from a publishable key and an identity token.
  ///
  /// - Parameters:
  ///   - key: A publishable project key (`ent_pk_…`). A secret key is refused.
  ///   - identityToken: An identity token from a sign-in provider registered on the project.
  ///   - visitor: A visitor id to use instead of the one the client keeps.
  ///   - cache: The in-memory cache: by default 1,000 answers, or `nil` for none.
  ///   - options: Timeouts, retries, stale answers and the rest.
  public convenience init(
    key: String, identityToken: String, visitor: String? = nil,
    cache: MemoryCacheStore? = MemoryCacheStore(capacity: 1_000),
    options: EntitlerOptions = EntitlerOptions()
  ) throws {
    let key = try requireCredential(key, Messages.key)
    let token = try requireCredential(identityToken, Messages.identityToken)
    try self.init(
      credential: .identity(key: try requirePublishable(key), TokenSource(fixed: token)),
      visitor: visitor, cache: cache, options: options)
  }

  /// Creates a client from a publishable key and a provider of identity tokens.
  public convenience init(
    key: String, identityTokenProvider: @escaping TokenProvider, visitor: String? = nil,
    cache: MemoryCacheStore? = MemoryCacheStore(capacity: 1_000),
    options: EntitlerOptions = EntitlerOptions()
  ) throws {
    let key = try requirePublishable(requireCredential(key, Messages.key))
    try self.init(
      credential: .identity(
        key: key, TokenSource(provider: identityTokenProvider, blankMessage: Messages.identityToken)
      ),
      visitor: visitor, cache: cache, options: options)
  }

  /// Registers the signed-in person as a customer. An existing customer is answered without being
  /// created again, so call it after each sign-in.
  ///
  /// It fails with ``ErrorCode/registrationClosed`` when the sign-in provider does not let people
  /// register themselves (``CredentialScopes/registration`` says so ahead).
  @discardableResult
  public func register(idempotencyKey: String? = nil, timeout: TimeInterval? = nil) async throws
    -> RegisteredCustomer
  {
    try await me.handle.call("PUT", [], idempotencyKey: idempotencyKey, timeout: timeout)
  }
}

extension EntitlerClient where Credential == PublishableCredential {
  /// Creates a client from a publishable key alone, for a signed-out paywall or pricing page.
  ///
  /// - Parameters:
  ///   - key: A publishable project key (`ent_pk_…`) with `plans:read`. A secret key is refused.
  ///   - visitor: A visitor id to use instead of the one the client keeps.
  ///   - cache: The in-memory cache: by default 1,000 answers, or `nil` for none.
  ///   - options: Timeouts, retries, stale answers and the rest.
  public convenience init(
    key: String, visitor: String? = nil,
    cache: MemoryCacheStore? = MemoryCacheStore(capacity: 1_000),
    options: EntitlerOptions = EntitlerOptions()
  ) throws {
    let key = try requirePublishable(requireCredential(key, Messages.key))
    try self.init(
      credential: .publishable(key: key), visitor: visitor, cache: cache, options: options)
  }

  /// The plans on sale to the signed-out visitor, through the cache.
  ///
  /// - Parameters:
  ///   - visitor: A visitor id to send instead of the client's, for this request only.
  ///   - revalidate: Asks Entitler again even when a kept answer is still fresh.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  public func pricing(
    visitor: String? = nil, revalidate: Bool = false, timeout: TimeInterval? = nil
  )
    async throws -> Pricing
  {
    var request = try Request("GET", ["pricing"])
    request.visitor = try validVisitor(visitor)
    request.revalidate = revalidate
    request.timeout = timeout
    return try await core.cachedCall(request)
  }
}

func requirePublishable(_ key: String) throws -> String {
  guard key.hasPrefix("ent_pk_") else { throw ArgumentError(message: Messages.secretInApp) }
  return key
}

/// The signed-in customer of an in-app client: ``EntitlerClient/me``.
public struct SignedInCustomer: Customer, CustomStringConvertible, CustomReflectable {
  /// The client and customer this value acts through. Opaque.
  public let handle: CustomerHandle

  /// The id your app uses for the customer, from the latest answer: `nil` before the first one.
  public var id: String? {
    get async { await handle.core.state.signedInID }
  }

  /// `SignedInCustomer(me)`.
  public var description: String { "SignedInCustomer(me)" }

  /// Nothing but the path, never the credential.
  public var customMirror: Mirror { Mirror(self, children: ["path": "me"]) }
}

/// The public keys that verify snapshots, read with no credential, as `entitler snapshot-keys`
/// reads them.
package func fetchSnapshotKeys(options: EntitlerOptions) async throws -> SnapshotKeys {
  try await Core(options: options, cache: nil, credential: .server(key: ""), visitor: nil)
    .snapshotKeys(timeout: nil)
}

extension Core {
  func scopes(timeout: TimeInterval?) async throws -> CredentialScopes {
    var request = try Request("GET", ["keys", "self"])
    request.timeout = timeout
    let answer: KeySelf = try await call(request)
    return CredentialScopes(scopes: Scope.known(answer.scopes), registration: answer.registration)
  }

  func snapshotKeys(timeout: TimeInterval?) async throws -> SnapshotKeys {
    var request = try Request("GET", ["customers", "snapshot-keys"])
    request.timeout = timeout
    request.authenticated = false
    return try await call(request)
  }
}
