import Foundation

/// A hold on a metered feature's allowance, from
/// ``Customer/startHold(of:amount:idempotencyKey:ttlSeconds:timeout:)``, answered before any work
/// starts, so a route can answer a refusal before it streams.
///
/// ```swift
/// let hold = try await customer.startHold(of: Features.aiCredits, amount: 2_000,
///   idempotencyKey: message.id)
/// try await hold.run { hold in
///   try hold.use(0)
///   for try await chunk in stream {
///     try hold.use(chunk.tokensSoFar)
///   }
/// }
/// ```
///
/// End it with one of ``finish()``, ``release()`` or ``run(_:)``; only the first acts, and a
/// later call answers its result without a request. Each runs in a task of its own, so cancelling
/// the caller cannot stop it halfway. A hold never ended this way expires after its `ttlSeconds`,
/// recording nothing: Swift cannot await in `deinit` or `defer`, so ``run(_:)`` is the scope that
/// disposes of it.
///
/// While the hold is open, ``UsageResult/remaining`` drops by the whole amount held, and rises
/// when it settles; a live meter shows ``UsageResult/held`` apart.
public final class Hold: Sendable {
  /// The hold's id.
  public let id: String
  /// The answer that placed the hold.
  public let result: UsageResult
  let customer: any Customer
  let feature: Feature<Metered>
  let key: String
  let timeout: TimeInterval?
  private let used = LockedValue<Int64?>(nil)
  private let ending = LockedValue<Task<UsageResult, any Error>?>(nil)

  init(
    id: String, result: UsageResult, customer: any Customer, feature: Feature<Metered>,
    key: String, timeout: TimeInterval?
  ) {
    self.id = id
    self.result = result
    self.customer = customer
    self.feature = feature
    self.key = key
    self.timeout = timeout
  }

  /// The amount held.
  public var amount: Int64 { result.amount }

  /// When the hold expires unless it is settled or released first.
  public var expiresAt: Date? { result.expiresAt }

  /// True when another caller holds the same key and may be doing the same work, so the app can
  /// wait for that caller's result instead of paying for the work twice.
  public var isDuplicate: Bool { result.outcome == .duplicate }

  /// Reports the total amount the work has really used so far, with no request. A later call
  /// replaces an earlier one. Work that reports as it goes calls `use(0)` before it starts, so
  /// ending it after a failure that used nothing frees the whole hold.
  ///
  /// - Throws: ``ArgumentError`` for an amount outside 0 to 2^53 − 1.
  public func use(_ amount: Int64) throws {
    guard (0...maxAmount).contains(amount) else {
      throw ArgumentError(message: Messages.amountUsed)
    }
    used.set(amount)
  }

  /// Ends the work, whether it succeeded, failed or was cut off, and charges for the work that
  /// happened: it settles the amount reported with ``use(_:)``, or the held amount when none was.
  ///
  /// Up to the held amount is settled, and any excess is recorded in observe mode under the hold's
  /// key plus `:excess`. When the hold expired first, the whole amount is recorded under that key,
  /// since the work happened.
  ///
  /// - Returns: The settlement, or the excess report when the hold had expired.
  /// - Throws: ``EntitlerError/usageSettlement(_:)`` when settling or recording the excess fails
  ///   after its retries: keep the work's output and settle again before the hold expires.
  @discardableResult
  public func finish() async throws -> UsageResult {
    let reported = used.read() ?? amount
    return try await end { hold in try await hold.settle(reported) }
  }

  /// Frees the hold, recording nothing, for work that never ran.
  @discardableResult
  public func release() async throws -> UsageResult {
    try await end { hold in
      try await hold.customer.releaseUsage(hold: hold.id, timeout: hold.timeout)
    }
  }

  /// Runs `body`, then ends the hold: ``finish()`` when `body` returns; when it throws or the task
  /// is cancelled, settles the amount reported with ``use(_:)``, or releases the hold when none
  /// was, then rethrows. A failure while doing so goes to ``EntitlerOptions/onError``.
  ///
  /// - Returns: `body`'s result.
  /// - Throws: `body`'s error, `CancellationError`, or ``EntitlerError/usageSettlement(_:)``
  ///   carrying `body`'s result when `finish()` fails.
  public func run<Result: Sendable>(_ body: (Hold) async throws -> Result) async throws -> Result {
    let output: Result
    do {
      output = try await body(self)
      try Task.checkCancellation()
    } catch {
      await dispose()
      throw error
    }
    do {
      try await finish()
    } catch EntitlerError.usageSettlement(var failure) {
      failure.result = output
      throw EntitlerError.usageSettlement(failure)
    }
    return output
  }

  func dispose() async {
    let reported = used.read()
    do {
      _ = try await end { hold in
        if let reported { return try await hold.settle(reported) }
        return try await hold.customer.releaseUsage(hold: hold.id, timeout: hold.timeout)
      }
    } catch {
      customer.handle.core.report(error)
    }
  }

  private func end(_ action: @escaping @Sendable (Hold) async throws -> UsageResult) async throws
    -> UsageResult
  {
    let task = ending.update { task in
      if let task { return task }
      let started = Task { try await action(self) }
      task = started
      return started
    }
    return try await task.value
  }

  private func settle(_ reported: Int64) async throws -> UsageResult {
    let settling = min(reported, amount)
    let excess = reported - settling
    func failure(_ amount: Int64, _ excess: Int64, _ error: any Error) -> EntitlerError {
      .usageSettlement(
        UsageSettlementError(
          holdID: id, amount: amount, excess: excess > 0 ? excess : nil, underlyingError: error,
          result: nil))
    }
    let settled: UsageResult
    do {
      settled = try await customer.settleUsage(hold: id, amount: settling, timeout: timeout)
    } catch EntitlerError.api(let error) where error.code == .holdExpired {
      guard reported > 0 else { return result }
      do {
        return try await recordExcess(reported)
      } catch let error as EntitlerError {
        throw failure(0, reported, error)
      }
    } catch let error as EntitlerError {
      throw failure(settling, excess, error)
    }
    guard excess > 0 else { return settled }
    do {
      try await recordExcess(excess)
    } catch let error as EntitlerError {
      throw failure(0, excess, error)
    }
    return settled
  }

  @discardableResult
  private func recordExcess(_ excess: Int64) async throws -> UsageResult {
    try await customer.recordUsage(
      of: feature, amount: excess, idempotencyKey: key + ":excess", mode: .observe,
      timeout: timeout)
  }
}
