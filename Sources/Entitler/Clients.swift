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
  ///   - key: A secret project key from the dashboard.
  ///   - options: Timeouts, retries, the cache and the rest.
  /// - Throws: ``ArgumentError`` when the key is blank or `asOf` is not a valid date.
  public init(key: String, options: EntitlerOptions = EntitlerOptions()) throws {
    core = try Core(
      options: options, credential: .server(key: requireCredential(key, Messages.key)), visitor: nil
    )
  }

  /// The base URL and the kind of client, never the key.
  public var description: String { "EntitlerServer(\(core.options.base))" }

  /// The base URL and the kind of client, never the key.
  public var customMirror: Mirror { core.customMirror }

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
  /// Every event needs an idempotency key: its own, else one the SDK generates. A request that
  /// fails after its retries answers its events with ``UsageEventOutcome/error``, and the next
  /// request still goes: resend those events with the same keys. Keys derived from your own unit
  /// of work make any resend safe.
  ///
  /// - Parameters:
  ///   - events: The events; an empty list sends nothing.
  ///   - register: Registers customers not registered yet, if the key may.
  ///   - idempotencyKey: A key for the batch; each request sends it plus `:<request index>`.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  /// - Returns: One result per event, in input order, and the totals.
  /// - Throws: Only ``ArgumentError`` and `CancellationError`.
  public func recordUsageBatch(
    _ events: [UsageBatchEvent], register: Bool = false, idempotencyKey: String? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> UsageBatchResult {
    struct Event: Encodable {
      var customer: String
      var feature: String
      var amount: Int64?
      var occurredAt: Date?
      var idempotencyKey: String
    }
    struct Body: Encodable {
      var register: Bool?
      var events: [Event]
    }
    struct Answer: Decodable {
      struct Result: Decodable {
        let index: Int
        let outcome: UsageEventOutcome
        let id: String?
        let late: Bool
        let error: UsageEventError?
      }
      let results: [Result]
    }
    let prepared = try events.map { event in
      Event(
        customer: try require(event.customer, Messages.customerID),
        feature: try requireFeature(event.feature.key), amount: try event.amount.map(validAmount),
        occurredAt: event.occurredAt,
        idempotencyKey: try validIdempotencyKey(event.idempotencyKey)
          ?? UUID().uuidString.lowercased())
    }
    let batchKey = try validIdempotencyKey(
      idempotencyKey, maxLength: 190, message: Messages.batchKey)
    var results: [UsageEventResult] = []
    for (index, start) in stride(from: 0, to: prepared.count, by: 500).enumerated() {
      let chunk = Array(prepared[start..<min(start + 500, prepared.count)])
      var request = try Request(
        "POST", ["usage", "events"], body: Body(register: register ? true : nil, events: chunk))
      request.timeout = timeout
      request.idempotencyKey = batchKey.map { "\($0):\(index)" }
      for customer in Set(chunk.map(\.customer)) {
        await core.state.bump(customer, at: Hooks.current.now())
      }
      do {
        let answer: Answer = try await core.call(request)
        for result in answer.results where chunk.indices.contains(result.index) {
          results.append(
            UsageEventResult(
              index: start + result.index, outcome: result.outcome, id: result.id,
              late: result.late,
              error: result.error, idempotencyKey: chunk[result.index].idempotencyKey))
        }
      } catch let error as EntitlerError {
        let failure: UsageEventError =
          switch error {
          case .api(let error): UsageEventError(code: error.code, message: error.message)
          case .timeout(let error): UsageEventError(code: .timedOut, message: error.message)
          default: UsageEventError(code: .connectionFailed, message: error.description)
          }
        results += chunk.enumerated().map { offset, event in
          UsageEventResult(
            index: start + offset, outcome: .error, id: nil, late: false, error: failure,
            idempotencyKey: event.idempotencyKey)
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
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  public func pricing(visitor: String? = nil, timeout: TimeInterval? = nil) async throws -> Pricing
  {
    var request = try Request("GET", ["pricing"])
    request.visitor = try validVisitor(visitor)
    request.timeout = timeout
    return try await core.cachedCall(request)
  }

  /// The features of the catalogue the All customers track serves, through the cache.
  public func features(timeout: TimeInterval? = nil) async throws -> FeatureList {
    var request = try Request("GET", ["pricing", "features"])
    request.timeout = timeout
    return try await core.cachedCall(request)
  }

  /// The scopes the key holds, for deciding what to show. Each call asks again.
  public func scopes(timeout: TimeInterval? = nil) async throws -> CredentialScopes {
    try await core.scopes(timeout: timeout)
  }

  /// The public keys that verify snapshots. Needs no credential.
  public func snapshotKeys(timeout: TimeInterval? = nil) async throws -> JSONWebKeySet {
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

/// One usage event of a batch.
public struct UsageBatchEvent: Hashable, Sendable {
  /// The customer's external id.
  public var customer: String
  /// The metered feature.
  public var feature: Feature<Metered>
  /// The amount, from 1 to 2^53 − 1; the API's default is 1.
  public var amount: Int64?
  /// When the usage happened.
  public var occurredAt: Date?
  /// A key from your own unit of work; the SDK generates one otherwise.
  public var idempotencyKey: String?

  /// Creates an event.
  public init(
    customer: String, feature: Feature<Metered>, amount: Int64? = nil, occurredAt: Date? = nil,
    idempotencyKey: String? = nil
  ) {
    self.customer = customer
    self.feature = feature
    self.amount = amount
    self.occurredAt = occurredAt
    self.idempotencyKey = idempotencyKey
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
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  public func list(
    query: String? = nil, cohort: String? = nil, track: String? = nil, includeTest: Bool = false,
    timeout: TimeInterval? = nil
  ) -> PagedList<CustomerSummary> {
    let core = core
    let options =
      [
        ("q", query), ("cohort", cohort), ("track", track),
        ("includeTest", includeTest ? "true" : nil),
      ]
      .compactMap { name, value in value.map { (name: name, value: $0) } }
    return PagedList { cursor in
      var request = try Request("GET", ["customers"])
      request.query = options + (cursor.map { [("cursor", $0)] } ?? [])
      request.timeout = timeout
      return try await core.call(request)
    }
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

/// A customer token minted by your server: ``EntitlerClient/init(token:visitor:options:)``.
public enum TokenCredential: ClientCredential {}

/// A publishable key and an identity token from your sign-in provider:
/// ``EntitlerClient/init(key:identityToken:visitor:options:)``.
public enum IdentityCredential: ClientCredential {}

/// The in-app client, for apps on phones, desktops and the web: it acts on the signed-in
/// customer only, ``me``.
///
/// ```swift
/// let client = try EntitlerClient(tokenProvider: { try await api.entitlerToken() })
/// let canExport = await client.me.isEntitled(to: Features.exportPDF, default: false)
/// ```
///
/// It never takes a secret key: anything shipped in an app can be read out of it. It takes a
/// customer token your server mints for one customer, or a publishable key holding only product
/// scopes with an identity token from your sign-in provider.
public final class EntitlerClient<Credential: ClientCredential>: Sendable, CustomStringConvertible,
  CustomReflectable
{
  let core: Core

  init(credential: Entitler.Credential, visitor: String?, options: EntitlerOptions) throws {
    core = try Core(
      options: options, credential: credential,
      visitor: try validVisitor(visitor) ?? storedVisitor())
  }

  /// The signed-in customer. Makes no request.
  public var me: SignedInCustomer {
    SignedInCustomer(handle: CustomerHandle(core: core, path: "me"))
  }

  /// The visitor id sent on every request, so an experiment's arm stays the same before and after
  /// registration.
  public var visitor: String { core.visitor ?? "" }

  /// The base URL and the kind of client, never the credential.
  public var description: String { "EntitlerClient(\(core.kind), \(core.options.base))" }

  /// The base URL and the kind of client, never the credential.
  public var customMirror: Mirror { core.customMirror }

  /// The scopes the credential holds, for deciding what to show. Each call asks again.
  public func scopes(timeout: TimeInterval? = nil) async throws -> CredentialScopes {
    try await core.scopes(timeout: timeout)
  }

  /// The public keys that verify snapshots. Needs no credential.
  public func snapshotKeys(timeout: TimeInterval? = nil) async throws -> JSONWebKeySet {
    try await core.snapshotKeys(timeout: timeout)
  }

  /// Verifies an offline snapshot; the same as ``verifySnapshot(_:expecting:)``.
  public func verifySnapshot(_ token: String, expecting expected: SnapshotExpectation) throws
    -> VerifiedSnapshot
  {
    try Entitler.verifySnapshot(token, expecting: expected)
  }
}

extension EntitlerClient where Credential == TokenCredential {
  /// Creates a client from a customer token. A fixed token cannot be refreshed, so a `401` fails.
  ///
  /// - Parameters:
  ///   - token: A customer token your server minted with ``ServerCustomer/token(scopes:ttlSeconds:idempotencyKey:timeout:)``.
  ///   - visitor: A visitor id to use instead of the one the client keeps.
  ///   - options: Timeouts, retries, the cache and the rest.
  public convenience init(
    token: String, visitor: String? = nil, options: EntitlerOptions = EntitlerOptions()
  )
    throws
  {
    let token = try requireCredential(token, Messages.customerToken)
    try self.init(credential: .token(TokenSource(fixed: token)), visitor: visitor, options: options)
  }

  /// Creates a client that asks your server for customer tokens, before the first request, before
  /// the kept one expires, and after a `401`.
  public convenience init(
    tokenProvider: @escaping TokenProvider, visitor: String? = nil,
    options: EntitlerOptions = EntitlerOptions()
  ) throws {
    try self.init(
      credential: .token(
        TokenSource(provider: tokenProvider, blankMessage: Messages.customerToken)),
      visitor: visitor, options: options)
  }
}

extension EntitlerClient where Credential == IdentityCredential {
  /// Creates a client from a publishable key and an identity token.
  ///
  /// - Parameters:
  ///   - key: A publishable project key holding only product scopes. Never a secret key.
  ///   - identityToken: An identity token from a sign-in provider registered on the project.
  ///   - visitor: A visitor id to use instead of the one the client keeps.
  ///   - options: Timeouts, retries, the cache and the rest.
  public convenience init(
    key: String, identityToken: String, visitor: String? = nil,
    options: EntitlerOptions = EntitlerOptions()
  ) throws {
    let key = try requireCredential(key, Messages.key)
    let token = try requireCredential(identityToken, Messages.identityToken)
    try self.init(
      credential: .identity(key: key, TokenSource(fixed: token)), visitor: visitor, options: options
    )
  }

  /// Creates a client from a publishable key and a provider of identity tokens.
  public convenience init(
    key: String, identityTokenProvider: @escaping TokenProvider, visitor: String? = nil,
    options: EntitlerOptions = EntitlerOptions()
  ) throws {
    let key = try requireCredential(key, Messages.key)
    try self.init(
      credential: .identity(
        key: key, TokenSource(provider: identityTokenProvider, blankMessage: Messages.identityToken)
      ),
      visitor: visitor, options: options)
  }

  /// Registers the signed-in person as a customer, if the sign-in provider lets them.
  @discardableResult
  public func register(idempotencyKey: String? = nil, timeout: TimeInterval? = nil) async throws
    -> RegisteredCustomer
  {
    try await me.handle.call("PUT", [], idempotencyKey: idempotencyKey, timeout: timeout)
  }
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

extension Core {
  func scopes(timeout: TimeInterval?) async throws -> CredentialScopes {
    var request = try Request("GET", ["keys", "self"])
    request.timeout = timeout
    let answer: KeySelf = try await call(request)
    return CredentialScopes(scopes: Scope.known(answer.scopes), registration: answer.registration)
  }

  func snapshotKeys(timeout: TimeInterval?) async throws -> JSONWebKeySet {
    var request = try Request("GET", ["customers", "snapshot-keys"])
    request.timeout = timeout
    request.authenticated = false
    return try await call(request)
  }
}
