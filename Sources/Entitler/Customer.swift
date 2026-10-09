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
    idempotencyKey: String? = nil, changesAnswers: Bool = true, timeout: TimeInterval?
  ) async throws -> Answer {
    var request = try request(
      method, segments, body: body, idempotencyKey: idempotencyKey, timeout: timeout)
    request.changesAnswers = changesAnswers
    return try await core.call(request)
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

/// The hold `withHold(of:amount:)` placed, passed to its work.
///
/// Report the total the work really used with ``use(_:)``; a later call replaces an earlier one.
/// When the work never reports an amount, the held amount is settled.
public final class OpenHold: Sendable {
  /// The answer that placed the hold.
  public let result: UsageResult
  /// The hold's id.
  public let holdID: String
  private let used = LockedValue<Int64?>(nil)

  init(result: UsageResult, holdID: String) {
    self.result = result
    self.holdID = holdID
  }

  /// The amount held.
  public var amount: Int64 { result.amount }

  /// Reports the total amount the work used, from 0 to 2^53 − 1.
  ///
  /// - Throws: ``ArgumentError`` for an amount out of range.
  public func use(_ amount: Int64) throws {
    guard (0...maxAmount).contains(amount) else {
      throw ArgumentError(message: Messages.amountUsed)
    }
    used.set(amount)
  }

  var reported: Int64? { used.read() }
}

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
  /// Any failure, Entitler being unreachable or a blank key included, answers `default` and goes
  /// to ``EntitlerOptions/onError``; a stale answer counts. Fail closed with `false` for paid
  /// features; pass `true` only where losing a sale is worse than giving the feature away.
  /// Cancelling the task answers `default` without calling `onError`.
  public func isEntitled<Kind>(
    to feature: Feature<Kind>, default fallback: Bool, timeout: TimeInterval? = nil
  ) async -> Bool {
    await isEntitled(to: feature.key, default: fallback, timeout: timeout)
  }

  /// Whether the customer is entitled to the feature with this key, answering `default` instead
  /// of failing.
  public func isEntitled(to key: String, default fallback: Bool, timeout: TimeInterval? = nil) async
    -> Bool
  {
    do {
      return try await check(key, timeout: timeout).entitled
    } catch is CancellationError {
      return fallback
    } catch {
      if !Task.isCancelled { handle.core.report(error) }
      return fallback
    }
  }

  /// Every entitlement the customer holds, groups included, through the cache.
  public func entitlements(timeout: TimeInterval? = nil) async throws -> Entitlements {
    try await handle.read(["entitlements"], timeout: timeout)
  }

  /// The plans the customer holds and every plan they can move to, through the cache.
  ///
  /// On an in-app client it needs the organisation's customer portal capability, or answers
  /// `409 limit_reached`.
  public func plans(timeout: TimeInterval? = nil) async throws -> CustomerPlans {
    try await handle.read(["plans"], timeout: timeout)
  }

  /// The plans on sale to the customer, through their track, through the cache.
  ///
  /// - Parameters:
  ///   - visitor: On the server, the visitor id the customer had while signed out, so they keep
  ///     their experiment arm. An in-app client sends its own unless this replaces it.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  public func pricing(visitor: String? = nil, timeout: TimeInterval? = nil) async throws -> Pricing
  {
    try await handle.read(["pricing"], visitor: visitor, timeout: timeout)
  }

  /// The customer's meters and the first page of their usage log; ``usageLog(timeout:)`` iterates
  /// every entry.
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
  /// Declare a plain key as `Feature<Metered>("ai_credits")`.
  ///
  /// - Parameters:
  ///   - feature: The metered feature.
  ///   - amount: A whole number in the feature's unit, from 1 to 2^53 − 1.
  ///   - mode: ``UsageMode/gate`` (the API's default) records only within the allowance;
  ///     ``UsageMode/observe`` always records.
  ///   - occurredAt: When the usage happened, so it counts in that period.
  ///   - register: Registers a customer not registered yet, if the credential may.
  ///   - idempotencyKey: A key from your own unit of work, so a retry from anywhere is
  ///     recognised. The SDK generates one otherwise.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  @discardableResult
  public func recordUsage(
    of feature: Feature<Metered>, amount: Int64, mode: UsageMode? = nil, occurredAt: Date? = nil,
    register: Bool = false, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    let body = UsageBody(
      feature: try requireFeature(feature.key), amount: try validAmount(amount), mode: mode,
      occurredAt: occurredAt, register: register ? true : nil)
    return try await handle.call(
      "POST", ["usage"], body: body, idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Holds an amount against the allowance until it is settled, released or expires.
  ///
  /// - Parameters:
  ///   - feature: The metered feature.
  ///   - amount: How much to hold, from 1 to 2^53 − 1.
  ///   - ttlSeconds: How long the hold lasts, 1 to 3600 (the API's default is 300).
  ///   - idempotencyKey: A key from your own unit of work, so a retry from anywhere is
  ///     recognised. The SDK generates one otherwise.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  public func holdUsage(
    of feature: Feature<Metered>, amount: Int64, ttlSeconds: Int? = nil,
    idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    let body = UsageBody(
      feature: try requireFeature(feature.key), amount: try validAmount(amount),
      ttlSeconds: ttlSeconds)
    return try await handle.call(
      "POST", ["usage", "holds"], body: body, idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Settles a hold with the real amount, from 0 to the amount held.
  @discardableResult
  public func settleUsage(
    hold holdID: String, amount: Int64, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    guard (0...maxAmount).contains(amount) else {
      throw ArgumentError(message: Messages.settledAmount)
    }
    return try await handle.call(
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

  /// Holds `amount`, runs `work`, and settles the amount the work reports.
  ///
  /// ```swift
  /// let summary = try await customer.withHold(of: Features.aiCredits, amount: 500) { hold in
  ///   let answer = try await summarise(document)
  ///   try hold.use(answer.tokens)
  ///   return answer.summary
  /// }
  /// ```
  ///
  /// - `work` runs only when the hold is placed, or replays a hold that is still open. A refused
  ///   hold, or a replay of one settled, released or expired, throws
  ///   ``EntitlerError/usageRefused(_:)`` without running it.
  /// - The amount reported with ``OpenHold/use(_:)`` is settled, up to the held amount; the held
  ///   amount when none is reported. Any excess is recorded in observe mode under the hold's key
  ///   plus `:excess`, and so is the whole amount when the hold expired while `work` ran.
  /// - When `work` throws or the task is cancelled, the hold is released outside the cancelled
  ///   task, then the error propagates. A failed release goes to ``EntitlerOptions/onError``,
  ///   since the hold expires on its own.
  /// - When settling or recording the excess fails, it throws
  ///   ``EntitlerError/usageSettlement(_:)`` carrying `work`'s result.
  ///
  /// The accounting happens exactly once per key, but `work` does not: two callers using the same
  /// key at the same time may both run it. Coordinate `work` yourself when it must run once.
  ///
  /// - Parameters:
  ///   - feature: The metered feature.
  ///   - amount: How much to hold, from 1 to 2^53 − 1.
  ///   - ttlSeconds: How long the hold lasts, 1 to 3600 (the API's default is 300).
  ///   - idempotencyKey: A key from your own unit of work, 1 to 193 printable ASCII characters,
  ///     so `:excess` still fits. The SDK generates one otherwise.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  ///   - work: The work, passed the hold.
  /// - Returns: `work`'s result.
  public func withHold<Result: Sendable>(
    of feature: Feature<Metered>, amount: Int64, ttlSeconds: Int? = nil,
    idempotencyKey: String? = nil, timeout: TimeInterval? = nil,
    _ work: (OpenHold) async throws -> Result
  ) async throws -> Result {
    let key =
      try validIdempotencyKey(idempotencyKey, maxLength: 193, message: Messages.holdKey)
      ?? UUID().uuidString.lowercased()
    let placed = try await holdUsage(
      of: feature, amount: amount, ttlSeconds: ttlSeconds, idempotencyKey: key, timeout: timeout)
    guard placed.outcome == .held || placed.outcome == .duplicate, let holdID = placed.holdID else {
      throw EntitlerError.usageRefused(placed)
    }
    let hold = OpenHold(result: placed, holdID: holdID)
    let result: Result
    do {
      result = try await work(hold)
      try Task.checkCancellation()
    } catch {
      let customer = self
      let core = handle.core
      await Task {
        do {
          try await customer.releaseUsage(hold: holdID, timeout: timeout)
        } catch {
          core.report(error)
        }
      }.value
      throw error
    }
    let used = hold.reported ?? placed.amount
    var settle = min(used, placed.amount)
    var excess = used - settle
    do {
      try await settleUsage(hold: holdID, amount: settle, timeout: timeout)
      settle = 0
    } catch EntitlerError.api(let error) where error.code == .holdExpired {
      settle = 0
      excess = used
    } catch let error as EntitlerError {
      throw EntitlerError.usageSettlement(
        UsageSettlementError(
          holdID: holdID, amount: settle, excess: excess > 0 ? excess : nil, underlyingError: error,
          result: result))
    }
    guard excess > 0 else { return result }
    do {
      try await recordUsage(
        of: feature, amount: excess, mode: .observe, idempotencyKey: key + ":excess",
        timeout: timeout)
    } catch let error as EntitlerError {
      throw EntitlerError.usageSettlement(
        UsageSettlementError(
          holdID: holdID, amount: 0, excess: excess, underlyingError: error, result: result))
    }
    return result
  }

  /// Signs the customer's entitlements, so an app can check them offline until it expires.
  ///
  /// Meters in a snapshot are frozen when it is signed. Verify it with
  /// ``verifySnapshot(_:expecting:)``.
  ///
  /// - Parameters:
  ///   - ttlSeconds: How long it lasts, at most the project's offline days.
  ///   - idempotencyKey: Sent as `Idempotency-Key`; minting writes nothing.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  public func snapshot(
    ttlSeconds: Int? = nil, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  )
    async throws -> IssuedSnapshot
  {
    try await handle.call(
      "POST", ["snapshots"], body: SnapshotBody(ttlSeconds: ttlSeconds),
      idempotencyKey: idempotencyKey,
      changesAnswers: false, timeout: timeout)
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
