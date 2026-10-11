import Foundation

/// A customer, as both clients return one: ``EntitlerServer/customer(_:)`` and
/// ``EntitlerClient/me``. Gate features, record usage and offer the customer's own billing
/// choices once, in code that takes `some Customer`:
///
/// ```swift
/// func export(for customer: some Customer, job: Job) async throws {
///   guard await customer.isEntitled(to: Features.exportPDF, default: false) else { return }
///   try await customer.recordUsage(of: Features.aiCredits, amount: 1, idempotencyKey: job.id)
/// }
/// ```
///
/// An unregistered customer is answered from the default plan by every read; writes to one
/// fail with ``ErrorCode/customerNotFound``, except those given `register: true`.
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

  func call<Answer: Decodable & Sendable>(
    _ method: String, _ segments: [String], body: (any Encodable)? = nil,
    query: [(name: String, value: String)] = [], idempotencyKey: String? = nil,
    changesAnswers: Bool = true, timeout: TimeInterval?
  ) async throws -> Answer {
    var request = try request(
      method, segments, body: body, idempotencyKey: idempotencyKey, timeout: timeout)
    request.query = query
    request.changesAnswers = changesAnswers
    return try await core.call(request)
  }

  func read<Answer: Decodable & Sendable>(
    _ segments: [String], visitor: String? = nil, revalidate: Bool, asOf: Date? = nil,
    timeout: TimeInterval?
  ) async throws -> Answer {
    var request = try request("GET", segments, timeout: timeout)
    request.visitor = try validVisitor(visitor)
    request.revalidate = revalidate
    request.asOf = try validAsOf(asOf)
    return try await core.cachedCall(request)
  }

  func usage(cursor: String?, asOf: Date?, timeout: TimeInterval?) async throws -> CustomerUsage {
    var request = try request("GET", ["usage"], timeout: timeout)
    if let cursor { request.query = [("cursor", cursor)] }
    request.asOf = try validAsOf(asOf)
    return try await core.call(request)
  }

  func isEntitled(
    _ key: String, default fallback: Bool, revalidate: Bool, asOf: Date?, timeout: TimeInterval?
  ) async -> Bool {
    do {
      let check: Check = try await read(
        ["entitlements", requireFeature(key)], revalidate: revalidate, asOf: asOf, timeout: timeout)
      return check.entitled
    } catch is CancellationError {
      return fallback
    } catch {
      if !Task.isCancelled { core.report(error) }
      return fallback
    }
  }
}

func validAsOf(_ asOf: Date?) throws -> Date? {
  guard let asOf else { return nil }
  guard (-62_135_596_800..<253_402_300_800).contains(asOf.timeIntervalSince1970) else {
    throw ArgumentError(message: Messages.asOf)
  }
  return asOf
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

struct SubscribeBody: Encodable {
  var plan: String
  var period: String?
  var quantity: Int?
  var returnUrl: URL?
  var register: Bool?
}

struct ReturnBody: Encodable {
  var returnUrl: URL
}

func requireFeature(_ key: String) throws -> String { try require(key, Messages.feature) }

func requireUsageKey(_ key: String, maxLength: Int = 200, message: String = Messages.idempotencyKey)
  throws -> String
{
  try validIdempotencyKey(key, maxLength: maxLength, message: message) ?? key
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
  /// ``Entitler/Check``. A metered feature's ``Check/entitled`` means allowance remains, and
  /// ``Check/upgrades`` lists the plans that would entitle the customer when they are not.
  ///
  /// - Parameters:
  ///   - feature: The feature.
  ///   - revalidate: Asks Entitler again even when a kept answer is still fresh, for example back
  ///     from paying; a `304` still answers the kept body.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  public func check<Kind>(
    _ feature: Feature<Kind>, revalidate: Bool = false, timeout: TimeInterval? = nil
  ) async throws -> Kind.Check {
    try await handle.read(
      ["entitlements", requireFeature(feature.key)], revalidate: revalidate, timeout: timeout)
  }

  /// Checks the feature with this key, through the cache.
  public func check(_ key: String, revalidate: Bool = false, timeout: TimeInterval? = nil)
    async throws -> Check
  {
    try await handle.read(
      ["entitlements", requireFeature(key)], revalidate: revalidate, timeout: timeout)
  }

  /// Whether the customer is entitled to a feature, answering `default` instead of failing.
  ///
  /// Any failure, Entitler being unreachable or a blank key included, answers `default` and goes
  /// to ``EntitlerOptions/onError``; a stale answer counts. Fail closed with `false` for paid
  /// features; pass `true` only where losing a sale is worse than giving the feature away.
  /// Cancelling the task answers `default` without calling `onError`.
  public func isEntitled<Kind>(
    to feature: Feature<Kind>, default fallback: Bool, revalidate: Bool = false,
    timeout: TimeInterval? = nil
  ) async -> Bool {
    await handle.isEntitled(
      feature.key, default: fallback, revalidate: revalidate, asOf: nil, timeout: timeout)
  }

  /// Whether the customer is entitled to the feature with this key, answering `default` instead
  /// of failing.
  public func isEntitled(
    to key: String, default fallback: Bool, revalidate: Bool = false, timeout: TimeInterval? = nil
  ) async -> Bool {
    await handle.isEntitled(
      key, default: fallback, revalidate: revalidate, asOf: nil, timeout: timeout)
  }

  /// Every entitlement the customer holds, groups included, through the cache.
  public func entitlements(revalidate: Bool = false, timeout: TimeInterval? = nil) async throws
    -> Entitlements
  {
    try await handle.read(["entitlements"], revalidate: revalidate, timeout: timeout)
  }

  /// The plans the customer holds and every plan they can move to, through the cache: the one
  /// read for a paywall and a billing page.
  ///
  /// Each ``MoveOption/action`` decides its button, ``MoveOption/skus`` are the products to buy
  /// through StoreKit, and a held plan's ``HeldPlan/billedBy`` decides between the store's own
  /// management page and ``billingPortal(returnURL:timeout:)``. On an in-app client it needs the
  /// organisation's customer portal capability (``ErrorCode/capabilityRequired`` otherwise).
  public func plans(revalidate: Bool = false, timeout: TimeInterval? = nil) async throws
    -> CustomerPlans
  {
    try await handle.read(["plans"], revalidate: revalidate, timeout: timeout)
  }

  /// The plans on sale to the customer, through their track, through the cache.
  ///
  /// - Parameters:
  ///   - visitor: On the server, the visitor id the customer had while signed out, so they keep
  ///     their experiment arm. An in-app client sends its own unless this replaces it.
  ///   - revalidate: Asks Entitler again even when a kept answer is still fresh.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  public func pricing(
    visitor: String? = nil, revalidate: Bool = false, timeout: TimeInterval? = nil
  ) async throws -> Pricing {
    try await handle.read(["pricing"], visitor: visitor, revalidate: revalidate, timeout: timeout)
  }

  /// The customer's meters and the first page of their usage log; ``usageLog(timeout:)`` iterates
  /// every entry.
  public func usage(cursor: String? = nil, timeout: TimeInterval? = nil) async throws
    -> CustomerUsage
  {
    try await handle.usage(cursor: cursor, asOf: nil, timeout: timeout)
  }

  /// The customer's usage log, newest first, each page requested only when iteration reaches it.
  ///
  /// ```swift
  /// for try await event in customer.usageLog() {
  ///   print(event.feature, event.amount)
  /// }
  /// ```
  public func usageLog(timeout: TimeInterval? = nil) -> PagedList<UsageEvent> {
    let handle = handle
    return PagedList { cursor in
      try await handle.usage(cursor: cursor, asOf: nil, timeout: timeout).log
    }
  }

  /// Records usage of a metered feature. A refusal is an answer: see ``UsageResult/outcome``.
  ///
  /// ```swift
  /// let result = try await customer.recordUsage(
  ///   of: Features.aiCredits, amount: 3, idempotencyKey: job.id, mode: .observe)
  /// ```
  ///
  /// Declare a plain key as `Feature<Metered>("ai_credits")`. Reports sent with customer and
  /// identity tokens count towards 100 every 10 seconds per customer, shared by all their devices;
  /// counting on a device is advisory, since a modified app can skip it.
  ///
  /// - Parameters:
  ///   - feature: The metered feature.
  ///   - amount: A whole number in the feature's unit, from 1 to 2^53 − 1.
  ///   - idempotencyKey: A key from your own unit of work, naming the event (this message, this
  ///     job, this webhook delivery), never an object whose state changes: the API keeps it for
  ///     ever, and a reused key replays the first answer and records nothing.
  ///   - mode: ``UsageMode/gate`` (the API's default) records only within the allowance, for work
  ///     that must not start without it; ``UsageMode/observe`` always records, for work that
  ///     already happened.
  ///   - occurredAt: When the usage happened, so it counts in that period.
  ///   - register: Registers a customer not registered yet, if the credential may.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  @discardableResult
  public func recordUsage(
    of feature: Feature<Metered>, amount: Int64, idempotencyKey: String, mode: UsageMode? = nil,
    occurredAt: Date? = nil, register: Bool = false, timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    let body = UsageBody(
      feature: try requireFeature(feature.key), amount: try validAmount(amount), mode: mode,
      occurredAt: occurredAt, register: register ? true : nil)
    return try await handle.call(
      "POST", ["usage"], body: body, idempotencyKey: requireUsageKey(idempotencyKey),
      timeout: timeout)
  }

  /// Holds an amount against the allowance and answers a ``Hold`` to end it, before any work
  /// starts.
  ///
  /// ```swift
  /// let hold = try await customer.startHold(of: Features.aiCredits, amount: estimate,
  ///   idempotencyKey: message.id)
  /// ```
  ///
  /// - Parameters:
  ///   - feature: The metered feature.
  ///   - amount: How much to hold, from 1 to 2^53 − 1.
  ///   - idempotencyKey: A key from your own unit of work, 1 to 193 printable ASCII characters,
  ///     so the hold's key plus `:excess` still fits.
  ///   - ttlSeconds: How long the hold lasts, 1 to 3600 (the API's default is 300).
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  /// - Throws: ``EntitlerError/usageRefused(_:)`` when no allowance remains, and
  ///   ``EntitlerError/usageReplayed(_:)`` when the key's hold was already settled, released or
  ///   expired.
  public func startHold(
    of feature: Feature<Metered>, amount: Int64, idempotencyKey: String, ttlSeconds: Int? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> Hold {
    let key = try requireUsageKey(idempotencyKey, maxLength: 193, message: Messages.holdKey)
    let placed = try await holdUsage(
      of: feature, amount: amount, idempotencyKey: key, ttlSeconds: ttlSeconds, timeout: timeout)
    switch placed.outcome {
    case .held, .duplicate:
      guard let id = placed.holdID else { throw EntitlerError.usageReplayed(placed) }
      return Hold(
        id: id, result: placed, customer: self, feature: feature, key: key, timeout: timeout)
    case .refused: throw EntitlerError.usageRefused(placed)
    default: throw EntitlerError.usageReplayed(placed)
    }
  }

  /// Holds `amount`, runs `work`, and charges for the work that happened: ``startHold(of:amount:idempotencyKey:ttlSeconds:timeout:)``
  /// then ``Hold/run(_:)``.
  ///
  /// ```swift
  /// let summary = try await customer.withHold(of: Features.aiCredits, amount: 500,
  ///   idempotencyKey: job.id) { hold in
  ///   let answer = try await summarise(document)
  ///   try hold.use(answer.tokens)
  ///   return answer.summary
  /// }
  /// ```
  ///
  /// - When `work` returns, the amount it reported with ``Hold/use(_:)`` is settled (the held
  ///   amount when none was), and any excess is recorded under the key plus `:excess`.
  /// - When `work` throws or the task is cancelled, the amount it reported is settled, or the
  ///   hold released when it reported none, then the error propagates: a disconnect after 3,000
  ///   tokens charges for 3,000 tokens.
  ///
  /// The accounting happens exactly once per key, but `work` does not: a caller sharing the key
  /// sees ``Hold/isDuplicate``. Coordinate `work` yourself when it must run once.
  ///
  /// - Returns: `work`'s result.
  /// - Throws: ``EntitlerError/usageRefused(_:)`` or ``EntitlerError/usageReplayed(_:)`` without
  ///   running `work`; `work`'s error; or ``EntitlerError/usageSettlement(_:)`` carrying `work`'s
  ///   result when settling fails.
  public func withHold<Result: Sendable>(
    of feature: Feature<Metered>, amount: Int64, idempotencyKey: String, ttlSeconds: Int? = nil,
    timeout: TimeInterval? = nil, _ work: (Hold) async throws -> Result
  ) async throws -> Result {
    try await startHold(
      of: feature, amount: amount, idempotencyKey: idempotencyKey, ttlSeconds: ttlSeconds,
      timeout: timeout
    ).run(work)
  }

  /// Holds an amount against the allowance until it is settled, released or expires, answering
  /// the hold's ``UsageResult``, for a hold settled from another process. Most apps use
  /// ``startHold(of:amount:idempotencyKey:ttlSeconds:timeout:)``.
  public func holdUsage(
    of feature: Feature<Metered>, amount: Int64, idempotencyKey: String, ttlSeconds: Int? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    let body = UsageBody(
      feature: try requireFeature(feature.key), amount: try validAmount(amount),
      ttlSeconds: ttlSeconds)
    return try await handle.call(
      "POST", ["usage", "holds"], body: body, idempotencyKey: requireUsageKey(idempotencyKey),
      timeout: timeout)
  }

  /// Settles a hold with the real amount, from 0 to the amount held. Settling the same amount
  /// again answers ``UsageOutcome/duplicate``.
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

  /// Releases a hold, recording nothing. Releasing twice is safe.
  @discardableResult
  public func releaseUsage(
    hold holdID: String, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> UsageResult {
    try await handle.call(
      "DELETE", ["usage", "holds", require(holdID, Messages.hold)],
      idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Signs the customer's entitlements, so an app can check them offline until it expires.
  ///
  /// Meters in a snapshot are frozen when it is signed. Verify it with
  /// ``verifySnapshot(_:expecting:)``.
  ///
  /// - Parameters:
  ///   - ttlSeconds: How long it lasts, at most the project's offline days.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  public func snapshot(ttlSeconds: Int? = nil, timeout: TimeInterval? = nil) async throws
    -> IssuedSnapshot
  {
    try await handle.call(
      "POST", ["snapshots"], body: SnapshotBody(ttlSeconds: ttlSeconds), changesAnswers: false,
      timeout: timeout)
  }

  /// Subscribes the customer to a plan or an add-on, as they choose themselves, and answers the
  /// next step.
  ///
  /// ```swift
  /// switch try await customer.subscribe(to: "pro", period: "monthly", returnURL: link) {
  /// case .done(let change): show(change)
  /// case .pay(let url): open(url)
  /// case .confirming: showPending()
  /// case .manage(let store): openStoreSubscriptions(store)
  /// case .unknown: break
  /// }
  /// ```
  ///
  /// The move must be one ``plans(revalidate:timeout:)`` lists along a self-serve path, or the API
  /// refuses it with ``ErrorCode/notSelfServe``; the project's policies decide when it takes
  /// effect. A customer credential never charges a saved payment method, so a paid change from an
  /// app always answers ``SubscribeStep/pay(_:)``. In an app it needs `billing:self` in the token's
  /// scopes. A declined card throws ``EntitlerError/api(_:)`` with ``ErrorCode/paymentRequired``.
  /// It can also fail with ``ErrorCode/returnURLRequired``, ``ErrorCode/notSelfServe``,
  /// ``ErrorCode/scopeRequired``, ``ErrorCode/customerNotFound`` and
  /// ``ErrorCode/capabilityRequired``.
  ///
  /// - Parameters:
  ///   - plan: The plan or add-on, by its key or public id. An add-on is added, has its quantity
  ///     set when held, or replaces another, as `plans()` lists the move.
  ///   - period: The period's key, such as `monthly`.
  ///   - quantity: How many of a countable add-on.
  ///   - returnURL: Where the provider's page sends the customer back, paid or not: a page of your
  ///     own, or a universal link in an app. Needed whenever Stripe may bill the customer.
  ///   - register: Registers a customer not registered yet, if the credential may.
  ///   - idempotencyKey: A key naming this choice, so a retry from anywhere is recognised. The SDK
  ///     generates one otherwise.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  @discardableResult
  public func subscribe(
    to plan: String, period: String? = nil, quantity: Int? = nil, returnURL: URL? = nil,
    register: Bool = false, idempotencyKey: String? = nil, timeout: TimeInterval? = nil
  ) async throws -> SubscribeStep {
    try await handle.call(
      "POST", ["subscription"],
      body: SubscribeBody(
        plan: require(plan, Messages.plan), period: period, quantity: quantity,
        returnUrl: returnURL, register: register ? true : nil),
      idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Cancels the customer's plan, or the add-on `addOn` names, as they choose themselves. The
  /// project's policy decides whether it ends now or at renewal.
  ///
  /// A cancel the customer may not make (a sales-led plan) fails with ``ErrorCode/notSelfServe``;
  /// nothing to cancel answers ``PlanChange/changed`` false.
  ///
  /// - Parameters:
  ///   - addOn: The add-on to cancel, by its key or public id, instead of the plan.
  ///   - product: The product's key, when they hold plans in several.
  ///   - idempotencyKey: A key naming this choice. The SDK generates one otherwise.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  /// - Throws: ``ArgumentError`` when given both `addOn` and `product`, or a blank `addOn`.
  @discardableResult
  public func cancel(
    addOn: String? = nil, product: String? = nil, idempotencyKey: String? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> PlanChange {
    let (segments, query) = try subscriptionTarget(addOn: addOn, product: product, suffix: [])
    return try await handle.call(
      "DELETE", segments, query: query, idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// Undoes the change booked for the customer's renewal (a move or a cancel), on their plan or on
  /// the add-on `addOn` names. Nothing pending answers ``PlanChange/changed`` false.
  ///
  /// - Throws: ``ArgumentError`` when given both `addOn` and `product`, or a blank `addOn`.
  @discardableResult
  public func undoPendingChange(
    addOn: String? = nil, product: String? = nil, idempotencyKey: String? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> PlanChange {
    let (segments, query) = try subscriptionTarget(
      addOn: addOn, product: product, suffix: ["pending"])
    return try await handle.call(
      "DELETE", segments, query: query, idempotencyKey: idempotencyKey, timeout: timeout)
  }

  /// The payment provider's page where the customer updates payment details and sees invoices.
  ///
  /// It changes no plan. A customer the provider has never billed answers `404`
  /// ``ErrorCode/notFound``. In an app, open the URL in `ASWebAuthenticationSession`.
  ///
  /// - Parameters:
  ///   - returnURL: Where the page sends the customer back.
  ///   - timeout: How long each attempt may take, in seconds; the client's timeout when `nil`.
  public func billingPortal(returnURL: URL, timeout: TimeInterval? = nil) async throws
    -> ProviderPage
  {
    try await handle.call(
      "POST", ["billing-portal"], body: ReturnBody(returnUrl: returnURL), changesAnswers: false,
      timeout: timeout)
  }

  /// Reads the customer's state from the payment provider now, so the page the provider returns
  /// to shows the plan just paid for. Call ``plans(revalidate:timeout:)`` with `revalidate: true`
  /// after it.
  public func syncBilling(timeout: TimeInterval? = nil) async throws -> BillingSync {
    try await handle.call("POST", ["billing", "sync"], timeout: timeout)
  }

  private func subscriptionTarget(addOn: String?, product: String?, suffix: [String]) throws
    -> ([String], [(name: String, value: String)])
  {
    guard addOn == nil || product == nil else {
      throw ArgumentError(message: Messages.addOnOrProduct)
    }
    if let addOn {
      return (["subscription", "add-ons", try require(addOn, Messages.plan)] + suffix, [])
    }
    return (["subscription"] + suffix, product.map { [("product", $0)] } ?? [])
  }
}

/// A paged list: an `AsyncSequence` of every item, requesting each page only when iteration
/// reaches it. Iterate ``pages`` for the pages themselves.
public struct PagedList<Item: Codable & Hashable & Sendable>: AsyncSequence, Sendable {
  /// Each item, across pages.
  public typealias Element = Item

  let fetch: @Sendable (String?) async throws -> Page<Item>
  var start: String? = nil

  /// The pages, each requested only when iteration reaches it.
  public var pages: Pages { Pages(fetch: fetch, start: start) }

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
    let start: String?

    /// Makes an iterator over the pages.
    public func makeAsyncIterator() -> AsyncIterator {
      AsyncIterator(fetch: fetch, cursor: start)
    }

    /// Iterates the pages.
    public struct AsyncIterator: AsyncIteratorProtocol {
      let fetch: @Sendable (String?) async throws -> Page<Item>
      var cursor: String?
      var finished = false

      init(fetch: @escaping @Sendable (String?) async throws -> Page<Item>, cursor: String?) {
        self.fetch = fetch
        self.cursor = cursor
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
