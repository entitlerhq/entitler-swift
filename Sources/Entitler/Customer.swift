import Foundation

/// A customer, as both clients return one: ``EntitlerServer/customer(_:)`` and
/// ``EntitlerClient/me``. Gate features and record usage once, in code that takes `some Customer`:
///
/// ```swift
/// func export(for customer: some Customer) async throws {
///   guard await customer.isEntitled(to: Features.exportPDF, default: false) else { return }
///   try await customer.recordUsage(of: Features.aiCredits, amount: 1)
/// }
/// ```
///
/// An unregistered customer is answered from the default plan by every read; writes to one
/// fail with ``ErrorCode/customerNotFound``.
public protocol Customer: Sendable {
  /// The client and customer this value acts through. Opaque: use the methods instead.
  var handle: CustomerHandle { get }
}

/// The client and customer a ``Customer`` acts through. Opaque.
public struct CustomerHandle: Sendable {
  let core: Core
  let path: String

  func request(
    _ method: String, _ segments: [String], body: (any Encodable)? = nil,
    idempotencyKey: String? = nil, timeout: TimeInterval?
  ) throws -> Request {
    var request = try Request(method, ["customers", path] + segments, body: body)
    request.idempotencyKey = try validIdempotencyKey(idempotencyKey)
    request.timeout = timeout
    request.customer = path
    return request
  }

  func call<Answer: Decodable>(
    _ method: String, _ segments: [String], body: (any Encodable)? = nil,
    idempotencyKey: String? = nil, timeout: TimeInterval?
  ) async throws -> Answer {
    try await core.call(
      request(method, segments, body: body, idempotencyKey: idempotencyKey, timeout: timeout))
  }

  func read<Answer: Decodable>(_ segments: [String], visitor: String? = nil, timeout: TimeInterval?)
    async throws -> Answer
  {
    var request = try request("GET", segments, timeout: timeout)
    request.visitor = try validVisitor(visitor)
    return try await core.cachedCall(request)
  }
}

struct UsageBody: Encodable {
  var feature: String
  var amount: Int64
  var mode: UsageMode?
  var occurredAt: Date?
  var register: Bool?
  var ttlSeconds: Int?
}

struct AmountBody: Encodable {
  var amount: Int64
}

struct SnapshotBody: Encodable {
  var ttlSeconds: Int?
}

func requireFeature(_ key: String) throws -> String { try require(key, Messages.feature) }

extension Customer {
  /// Checks one feature, through the cache.
  ///
  /// ```swift
  /// let check = try await customer.check(Features.aiCredits)
  /// print(check.remaining)
  /// ```
  ///
  /// The answer is typed by the constant: a ``MeteredCheck`` for a metered feature, else a
  /// ``Entitler/Check``.
  public func check<Kind>(_ feature: Feature<Kind>, timeout: TimeInterval? = nil) async throws
    -> Kind.Check
  {
    try await handle.read(["entitlements", requireFeature(feature.key)], timeout: timeout)
  }

  /// Checks the feature with this key, through the cache.
  public func check(_ key: String, timeout: TimeInterval? = nil) async throws -> Check {
    try await handle.read(["entitlements", requireFeature(key)], timeout: timeout)
  }

  /// Whether the customer is entitled to a feature, answering `default` instead of failing.
  ///
  /// Any failure, Entitler being unreachable included, answers `default` and goes to
  /// ``EntitlerOptions/onError``; a stale answer counts. Fail closed with `false` for paid
  /// features; pass `true` only where losing a sale is worse than giving the feature away.
  /// Cancelling the task answers `default` without calling `onError`.
  public func isEntitled<Kind>(
    to feature: Feature<Kind>, default fallback: Bool, timeout: TimeInterval? = nil
  ) async -> Bool {
    await isEntitled(to: feature.key, default: fallback, timeout: timeout)
  }

  /// Whether the customer is entitled to the feature with this key, answering `default` instead
  /// of failing. A blank key is a programming error and stops in `preconditionFailure`.
  public func isEntitled(to key: String, default fallback: Bool, timeout: TimeInterval? = nil) async
    -> Bool
  {
    guard !key.trimmed.isEmpty else { preconditionFailure(Messages.feature) }
    do {
      return try await check(key, timeout: timeout).entitled
    } catch let error as EntitlerError {
      handle.core.options.onError?(error)
      return fallback
    } catch {
      return fallback
    }
  }

  /// Every entitlement the customer holds, groups included, through the cache.
  public func entitlements(timeout: TimeInterval? = nil) async throws -> Entitlements {
    try await handle.read(["entitlements"], timeout: timeout)
  }

  /// The customer's plans and every plan and add-on they could move to, through the cache.
  public func planSpace(timeout: TimeInterval? = nil) async throws -> PlanSpace {
    try await handle.read(["plans"], timeout: timeout)
  }

  /// The plans on sale to the customer, through their track, through the cache.
  ///
  /// - Parameter visitor: On the server, the visitor id the customer had while signed out, so
  ///   they keep their experiment arm. An in-app client sends its own.
  public func pricing(visitor: String? = nil, timeout: TimeInterval? = nil) async throws -> Pricing
  {
    try await handle.read(["pricing"], visitor: visitor, timeout: timeout)
  }

  /// The customer's meters and the first page of their usage log.
  public func usage(cursor: String? = nil, timeout: TimeInterval? = nil) async throws
    -> CustomerUsage
  {
    var request = try handle.request("GET", ["usage"], timeout: timeout)
    if let cursor { request.query = [("cursor", cursor)] }
    return try await handle.core.call(request)
  }

  /// The customer's usage log, newest first, each page requested only when iteration reaches it.
  ///
  /// ```swift
  /// for try await event in customer.usageLog() {
  ///   print(event.feature, event.amount)
  /// }
  /// ```
  public func usageLog(timeout: TimeInterval? = nil) -> PagedList<UsageEvent> {
    PagedList { cursor in try await usage(cursor: cursor, timeout: timeout).log }
  }

  /// Records usage of a metered feature. A refusal is an answer: see ``UsageResult/outcome``.
  ///
  /// ```swift
  /// let result = try await customer.recordUsage(of: Features.aiCredits, amount: 3, mode: .observe)
  /// ```
  ///
  /// - Parameters:
  ///   - mode: ``UsageMode/gate`` (the API's default) records only within the allowance;
  ///     ``UsageMode/observe`` always records.
  ///   - occurredAt: When the usage happened, so it counts in that period.
  ///   - register: Registers a customer not registered yet, if the credential may.
  ///   - idempotencyKey: A key from your own unit of work, so a retry from anywhere is
  ///     recognised. The SDK generates one otherwise.
  @discardableResult
  public func recordUsage(
    of feature: Feature<Metered>, amount: Int64, mode: UsageMode? = nil, occurredAt: Date? = nil,
    register: Bool = false, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    try await recordUsage(
      of: feature.key, amount: amount, mode: mode, occurredAt: occurredAt, register: register,
      idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Records usage of the metered feature with this key. The API refuses other features with
  /// ``ErrorCode/notMetered``.
  @discardableResult
  public func recordUsage(
    of key: String, amount: Int64, mode: UsageMode? = nil, occurredAt: Date? = nil,
    register: Bool = false, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    let body = UsageBody(
      feature: try requireFeature(key), amount: amount, mode: mode, occurredAt: occurredAt,
      register: register ? true : nil)
    return try await handle.call(
      "POST", ["usage"], body: body, idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Holds an amount against the allowance until it is settled, released or expires.
  ///
  /// - Parameter ttlSeconds: How long the hold lasts, 1 to 3600 (the API's default is 300).
  public func holdUsage(
    of feature: Feature<Metered>, amount: Int64, ttlSeconds: Int? = nil,
    idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    try await holdUsage(
      of: feature.key, amount: amount, ttlSeconds: ttlSeconds, idempotencyKey: idempotencyKey,
      timeout: timeout)
  }

  /// Holds an amount of the metered feature with this key.
  public func holdUsage(
    of key: String, amount: Int64, ttlSeconds: Int? = nil, idempotencyKey: String? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    let body = UsageBody(feature: try requireFeature(key), amount: amount, ttlSeconds: ttlSeconds)
    return try await handle.call(
      "POST", ["usage", "holds"], body: body, idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Settles a hold with the real amount, from 0 to the amount held.
  @discardableResult
  public func settleUsage(
    hold holdID: String, amount: Int64, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    try await handle.call(
      "POST", ["usage", "holds", require(holdID, Messages.hold), "settle"],
      body: AmountBody(amount: amount), idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Releases a hold. Releasing twice is safe.
  @discardableResult
  public func releaseUsage(
    hold holdID: String, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    try await handle.call(
      "DELETE", ["usage", "holds", require(holdID, Messages.hold)],
      idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Reads a hold back.
  public func hold(id holdID: String, timeout: TimeInterval? = nil) async throws -> UsageHold {
    try await handle.call(
      "GET", ["usage", "holds", require(holdID, Messages.hold)], timeout: timeout)
  }

  /// Holds `amount`, runs `work`, and settles the amount `work` answers.
  ///
  /// ```swift
  /// let tokens = try await customer.withHold(of: Features.aiCredits, amount: 500) { hold in
  ///   try await summarise(document).tokens
  /// }
  /// ```
  ///
  /// A refused hold never runs `work` and throws ``EntitlerError/usageRefused(_:)``. When `work`
  /// throws, the hold is released (a failed release goes to ``EntitlerOptions/onError``, since
  /// the hold expires on its own) and the error propagates. An amount past the hold is recorded
  /// in observe mode with the hold's key plus `:excess`. A failed settlement throws an error
  /// carrying the hold's id, so the app can settle again.
  ///
  /// - Returns: The amount `work` answered.
  @discardableResult
  public func withHold(
    of feature: Feature<Metered>, amount: Int64, ttlSeconds: Int? = nil,
    idempotencyKey: String? = nil, timeout: TimeInterval? = nil,
    _ work: (UsageResult) async throws -> Int64
  ) async throws -> Int64 {
    try await withHold(
      of: feature.key, amount: amount, ttlSeconds: ttlSeconds, idempotencyKey: idempotencyKey,
      timeout: timeout, work)
  }

  /// Holds an amount of the metered feature with this key, runs `work`, and settles it.
  @discardableResult
  public func withHold(
    of key: String, amount: Int64, ttlSeconds: Int? = nil, idempotencyKey: String? = nil,
    timeout: TimeInterval? = nil, _ work: (UsageResult) async throws -> Int64
  ) async throws -> Int64 {
    let idempotencyKey = try validIdempotencyKey(idempotencyKey) ?? UUID().uuidString.lowercased()
    let hold = try await holdUsage(
      of: key, amount: amount, ttlSeconds: ttlSeconds, idempotencyKey: idempotencyKey,
      timeout: timeout)
    guard hold.outcome != .refused, let holdID = hold.holdID else {
      throw EntitlerError.usageRefused(hold)
    }
    let used: Int64
    do {
      used = try await work(hold)
    } catch {
      let customer = self
      let release = Task { try await customer.releaseUsage(hold: holdID, timeout: timeout) }
      do {
        _ = try await release.value
      } catch let failure as EntitlerError {
        handle.core.options.onError?(failure)
      }
      throw error
    }
    do {
      try await settleUsage(hold: holdID, amount: min(used, hold.amount), timeout: timeout)
    } catch let error as EntitlerError {
      throw error.withHoldID(holdID)
    }
    if used > hold.amount {
      try await recordUsage(
        of: key, amount: used - hold.amount, mode: .observe,
        idempotencyKey: idempotencyKey + ":excess", timeout: timeout)
    }
    return used
  }

  /// Signs the customer's entitlements, so an app can check them offline until it expires.
  ///
  /// Meters in a snapshot are frozen when it is signed. Verify it with
  /// ``verifySnapshot(_:expecting:)``.
  ///
  /// - Parameter ttlSeconds: How long it lasts, at most the project's offline days.
  public func snapshot(ttlSeconds: Int? = nil, timeout: TimeInterval? = nil) async throws
    -> IssuedSnapshot
  {
    try await handle.call(
      "POST", ["snapshots"], body: SnapshotBody(ttlSeconds: ttlSeconds), timeout: timeout)
  }
}

/// A paged list: an `AsyncSequence` of every item, requesting each page only when iteration
/// reaches it. Iterate ``pages`` for the pages themselves.
public struct PagedList<Item: Codable & Hashable & Sendable>: AsyncSequence, Sendable {
  /// Each item, across pages.
  public typealias Element = Item

  let fetch: @Sendable (String?) async throws -> Page<Item>

  /// The pages, each requested only when iteration reaches it.
  public var pages: Pages { Pages(fetch: fetch) }

  /// Makes an iterator over every item.
  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(pages: pages.makeAsyncIterator())
  }

  /// Iterates every item across pages.
  public struct AsyncIterator: AsyncIteratorProtocol {
    var pages: Pages.AsyncIterator
    var buffer: [Item] = []

    /// The next item, requesting the next page when this one is used up.
    public mutating func next() async throws -> Item? {
      while buffer.isEmpty {
        guard let page = try await pages.next() else { return nil }
        buffer = page.items.reversed()
      }
      return buffer.popLast()
    }
  }

  /// The pages of a ``PagedList``.
  public struct Pages: AsyncSequence, Sendable {
    /// Each page.
    public typealias Element = Page<Item>

    let fetch: @Sendable (String?) async throws -> Page<Item>

    /// Makes an iterator over the pages.
    public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(fetch: fetch) }

    /// Iterates the pages.
    public struct AsyncIterator: AsyncIteratorProtocol {
      let fetch: @Sendable (String?) async throws -> Page<Item>
      var cursor: String?
      var finished = false

      init(fetch: @escaping @Sendable (String?) async throws -> Page<Item>) {
        self.fetch = fetch
      }

      /// The next page, or `nil` after the last.
      public mutating func next() async throws -> Page<Item>? {
        guard !finished else { return nil }
        let page = try await fetch(cursor)
        cursor = page.next
        finished = page.next == nil
        return page
      }
    }
  }
}
